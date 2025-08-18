# Makefile for deploying and managing the RabbitMQ cluster
# Usage examples:
#   make deploy        # Create .env if missing, start stack, wait for health, show status
#   make up            # Start in background
#   make down          # Stop and remove containers (preserve volumes)
#   make restart       # Restart services
#   make status        # Show compose status
#   make logs          # Show recent logs
#   make tail          # Follow logs
#   make wait          # Wait until rabbitmq nodes are healthy
#   make init-env      # Create .env from sample.env if missing
#   make clean         # Stop the stack and remove named volumes (data destructive)
#   make nginx-config DOMAIN=queue.example.com [options]  # Generate Nginx stream TLS config

SHELL := /bin/sh

DOCKER_COMPOSE ?= docker compose
COMPOSE_FILE ?= docker-compose.yml
SERVICES := rabbitmq1 rabbitmq2 haproxy
RABBIT_SERVICES := rabbitmq1 rabbitmq2
VOLUMES := rabbitmq1-data rabbitmq2-data

# Defaults for nginx stream config generation
DOMAIN ?=
LISTEN_PORT ?= 5671
BACKEND_HOST ?= 127.0.0.1
BACKEND_PORT ?= 5672

# If CERT_DIR not set, use Let's Encrypt default for DOMAIN
CERT_DIR ?=
CERT_FULLCHAIN ?=
CERT_KEY ?=

# Nginx commands (override if using systemctl wrappers or different paths)
NGINX_TEST ?= nginx -t
NGINX_RELOAD ?= nginx -s reload

# Optional override for destination directory; if empty we auto-detect
# Common paths we will try: /etc/nginx/streams-enabled, /etc/nginx/stream.d, /etc/nginx/conf.d, /etc/nginx/sites-enabled
NGINX_STREAM_DIR ?=

# Filename for the generated config
NGINX_CONFIG_NAME ?= nginx-rabbitmq-$(DOMAIN).conf

.PHONY: help deploy up down restart status ps logs tail wait init-env clean volumes nginx-config

help:
	@echo "Available targets:"
	@echo "  deploy        - Ensure .env exists, start stack, wait for health, and show status"
	@echo "  up            - Start services in background (detached)"
	@echo "  down          - Stop and remove containers (keeps volumes)"
	@echo "  restart       - Restart services"
	@echo "  status        - Show 'docker compose ps' output"
	@echo "  ps            - Alias for status"
	@echo "  logs          - Show last 100 lines of logs for all services"
	@echo "  tail          - Follow logs for all services"
	@echo "  wait          - Wait for RabbitMQ services to become healthy"
	@echo "  init-env      - Create .env from sample.env if it does not exist"
	@echo "  clean         - Down stack and remove named volumes ($(VOLUMES))"
	@echo "  nginx-config  - Generate Nginx stream TLS config for AMQPS and reload Nginx" \
		"(DOMAIN=queue.example.com [NGINX_STREAM_DIR=...] [CERT_DIR=...] [CERT_FULLCHAIN=...] [CERT_KEY=...] [LISTEN_PORT=5671] [BACKEND_PORT=5672])"
	@echo "  certbot-setup - Interactive: confirm DNS, install Nginx+Certbot, and obtain Let's Encrypt cert (DOMAIN=... EMAIL=...)"
	@echo "  tls-setup     - Runs certbot-setup then nginx-config (full AMQPS setup)"

# High-level deployment
.deploy-check-env:
	@$(MAKE) --no-print-directory init-env

deploy: .deploy-check-env up wait status
	@echo "Deployment completed successfully."

# Service lifecycle
up:
	$(DOCKER_COMPOSE) -f $(COMPOSE_FILE) up -d

down:
	$(DOCKER_COMPOSE) -f $(COMPOSE_FILE) down

restart:
	$(DOCKER_COMPOSE) -f $(COMPOSE_FILE) restart

status ps:
	$(DOCKER_COMPOSE) -f $(COMPOSE_FILE) ps

logs:
	$(DOCKER_COMPOSE) -f $(COMPOSE_FILE) logs --tail=100

tail:
	$(DOCKER_COMPOSE) -f $(COMPOSE_FILE) logs -f

# Health wait loop for brokers that have compose healthchecks
wait:
	@echo "Waiting for RabbitMQ services to be healthy..."
	@set -e; \
	for s in $(RABBIT_SERVICES); do \
	  printf " - %s: " "$$s"; \
	  success=0; \
	  for i in `seq 1 60`; do \
	    status=`docker inspect -f '{{json .State.Health.Status}}' $$s 2>/dev/null | tr -d '"'`; \
	    if [ "$$status" = "healthy" ]; then \
	      echo healthy; success=1; break; \
	    fi; \
	    sleep 2; \
	  done; \
	  if [ $$success -ne 1 ]; then \
	    echo timeout; exit 1; \
	  fi; \
	done
	@echo "All RabbitMQ services are healthy."

# Initialize environment file from sample
init-env:
	@if [ ! -f .env ]; then \
	  if [ -f sample.env ]; then \
	    cp sample.env .env; \
	    echo "Created .env from sample.env. Please review and update secrets before production."; \
	  else \
	    echo "sample.env not found; cannot create .env"; exit 1; \
	  fi; \
	else \
	  echo ".env already exists"; \
	fi

# Remove named volumes for a clean slate (DANGEROUS: deletes persisted data)
clean: down
	@set -e; \
	for v in $(VOLUMES); do \
	  echo "Removing volume $$v (if exists)..."; \
	  docker volume rm $$v >/dev/null 2>&1 || true; \
	done
	@echo "Cleanup complete."

# ------------------------------------------------------------------------------
# Generate Nginx stream config for AMQPS (TLS termination) -> HAProxy backend
# Usage:
#   make nginx-config DOMAIN=queue.example.com
# Optional:
#   NGINX_STREAM_DIR=/etc/nginx/streams-enabled
#   CERT_DIR=/etc/letsencrypt/live/queue.example.com
#   CERT_FULLCHAIN=/path/fullchain.pem CERT_KEY=/path/privkey.pem
#   LISTEN_PORT=5671 BACKEND_HOST=127.0.0.1 BACKEND_PORT=5672
# ------------------------------------------------------------------------------

nginx-config:
	@chmod +x ./gen-nginx-config.sh
	@DOMAIN="$(DOMAIN)" LISTEN_PORT="$(LISTEN_PORT)" BACKEND_HOST="$(BACKEND_HOST)" BACKEND_PORT="$(BACKEND_PORT)" \
	CERT_DIR="$(CERT_DIR)" CERT_FULLCHAIN="$(CERT_FULLCHAIN)" CERT_KEY="$(CERT_KEY)" \
	NGINX_STREAM_DIR="$(NGINX_STREAM_DIR)" NGINX_CONFIG_NAME="$(NGINX_CONFIG_NAME)" \
	NGINX_TEST="$(NGINX_TEST)" NGINX_RELOAD="$(NGINX_RELOAD)" \
	./gen-nginx-config.sh

# Install Nginx and Certbot, verify DNS, and obtain Let's Encrypt cert (interactive)
.PHONY: certbot-setup tls-setup
certbot-setup:
	@chmod +x ./setup-certbot.sh
	@DOMAIN="$(DOMAIN)" EMAIL="$(EMAIL)" ./setup-certbot.sh

# Full TLS setup: get certs and generate Nginx AMQPS stream config
# Usage:
#   make tls-setup DOMAIN=queue.example.com EMAIL=admin@example.com [LISTEN_PORT=5671] [BACKEND_HOST=127.0.0.1] [BACKEND_PORT=5672]
# This will prompt for confirmations, obtain certs, generate config, and reload Nginx.
tls-setup: certbot-setup nginx-config
	@echo "TLS setup complete for domain: $(DOMAIN)"