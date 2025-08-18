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
#   make clean         # Stop stack and remove named volumes

SHELL := /bin/sh

DOCKER_COMPOSE ?= docker compose
COMPOSE_FILE ?= docker-compose.yml
SERVICES := rabbitmq1 rabbitmq2 haproxy
RABBIT_SERVICES := rabbitmq1 rabbitmq2
VOLUMES := rabbitmq1-data rabbitmq2-data

.PHONY: help deploy up down restart status ps logs tail wait init-env clean volumes

help:
	@echo "Available targets:"
	@echo "  deploy     - Ensure .env exists, start stack, wait for health, and show status"
	@echo "  up         - Start services in background (detached)"
	@echo "  down       - Stop and remove containers (keeps volumes)"
	@echo "  restart    - Restart services"
	@echo "  status     - Show 'docker compose ps' output"
	@echo "  ps         - Alias for status"
	@echo "  logs       - Show last 100 lines of logs for all services"
	@echo "  tail       - Follow logs for all services"
	@echo "  wait       - Wait for RabbitMQ services to become healthy"
	@echo "  init-env   - Create .env from sample.env if it does not exist"
	@echo "  clean      - Down stack and remove named volumes ($(VOLUMES))"

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
