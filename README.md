# Docker RabbitMQ Cluster (2-node) with HAProxy and optional Nginx/Certbot TLS

This repository provides a production-ready starting point for running a small RabbitMQ cluster via Docker Compose, fronted by HAProxy for AMQP and the Management UI. It also includes helper scripts and Make targets to set up TLS with Nginx and Let's Encrypt (Certbot).

Production posture, operational runbooks, and security guidance are included below.

---

## Contents
- Overview and architecture
- Prerequisites
- Quick start (local/dev)
- Configuration (.env and files)
- Deploy to a server (production)
- TLS and secure endpoints (Nginx + Certbot)
- Operations (scale, restart, rolling changes)
- Security hardening
- Observability and monitoring
- Backup and restore
- Disaster recovery notes
- Troubleshooting
- Makefile targets

---

## Overview and architecture

Services (docker-compose.yml):
- rabbitmq1, rabbitmq2: RabbitMQ 3.13 (management-alpine) with clustering enabled.
- haproxy: TCP load balancer exposing:
  - 127.0.0.1:15672 -> RabbitMQ management UI (admin console)
  - 0.0.0.0:5745 -> AMQP port (plain AMQP to backend 5672)

Optional:
- Nginx on the host for terminating TLS (AMQPS and/or HTTPS for the management UI) and Certbot for obtaining Let's Encrypt certificates.

High-level flow:
- AMQP clients connect to HAProxy on port 5745 (default). HAProxy balances to rabbitmq1:5672 and rabbitmq2:5672.
- Management UI is reachable at http://127.0.0.1:15672 by default. For remote/secure access, use Nginx + TLS.

---

## Prerequisites
- Docker 24+ and Docker Compose Plugin (docker compose) on the target host.
- A Linux server (recommended) with public DNS if you plan to use Let's Encrypt.
- For TLS: Ability to run Nginx and Certbot on the host (via sudo).

---

## Quick start (local/dev)
1) Copy sample.env to .env and adjust values:
   - RABBITMQ_ERLANG_COOKIE must be a long random secret and identical across nodes.
   - RABBITMQ_DEFAULT_USER/PASS are initial admin credentials used by rabbitmq1.

   make init-env

2) Start the stack:

   make up

3) Wait for health checks and verify:

   make wait
   make status

4) Access the Management UI from the same host:
- URL: http://127.0.0.1:15672
- Login: RABBITMQ_DEFAULT_USER / RABBITMQ_DEFAULT_PASS

5) AMQP connection string example:
- amqp://username:password@<host>:5745/<vhost>

Dev cleanup:

   make down

Destructive cleanup (removes volumes):

   make clean

---

## Configuration (.env and files)
- .env (created from sample.env via make init-env):
  - RABBITMQ_ERLANG_COOKIE=... (required; keep secret)
  - RABBITMQ_DEFAULT_USER, RABBITMQ_DEFAULT_PASS (bootstrap admin for rabbitmq1)
  - RABBITMQ_DEFAULT_VHOST (default "/")
- rabbitmq.conf: RabbitMQ server config (mounted read-only in containers). Adjust as needed.
- haproxy.cfg: Load balancing for AMQP and Management UI.
- cluster-entrypoint.sh: Handles first node vs. joining node logic (idempotent cluster join).
- docker-compose.yml: Service definitions and ports.

Notes:
- The Management UI is only bound to 127.0.0.1 by default. For remote access, put Nginx in front with TLS.
- AMQP is exposed publicly on port 5745. Consider restricting this to known CIDRs or enabling TLS termination.

---

## Deploy to a server (production)
1) On the server, clone the repo and set up .env:

   make init-env
   # Then edit .env and set strong values. Never commit real secrets.

2) Start and verify:

   make deploy
   # Equivalent to: make up && make wait && make status

3) Security: Ensure the server firewall allows only the required ports:
- 5745/tcp from your client networks (AMQP via HAProxy)
- 22/tcp (SSH), 80/tcp (temporary for HTTP-01), 443/tcp (if using TLS with Nginx)
- 15672/tcp should remain local-only unless proxied via TLS.

---

## TLS and secure endpoints (Nginx + Certbot)
There are two common patterns:

A) Secure Management UI (HTTPS)
- Use the helper script to generate an Nginx site for the management UI and obtain a certificate.

   # On the host (with sudo), install Nginx+Certbot interactively and get a cert:
   sudo make certbot-setup DOMAIN=queue.example.com EMAIL=admin@example.com

   # Generate and enable an Nginx vhost that proxies 443 -> http://127.0.0.1:15672
   sudo make nginx-config DOMAIN=queue.example.com

   # After this, access: https://queue.example.com

B) Secure AMQP (AMQPS)
- Terminate TLS at Nginx stream and forward to HAProxy 5672.

   # After certbot-setup, you’ll have certs in /etc/letsencrypt/live/<domain>
   sudo make nginx-config DOMAIN=queue.example.com \
     LISTEN_PORT=5671 BACKEND_PORT=5672

- Validate and reload Nginx automatically via the Make target (overrides are available in the Makefile).

Important:
- DNS must point your domain to the server’s public IP and port 80 must be reachable during certificate issuance.
- Renewals: Certbot handles renewals; ensure a systemd timer or cron is set up by Certbot install method.

---

## Operations
- Start:

   make up

- Stop and remove containers (keep data volumes):

   make down

- Restart:

   make restart

- Tail logs:

   make tail

- Health wait:

   make wait

- Scale: This example defines two nodes. To add a third, you can duplicate the service stanza in docker-compose.yml (rabbitmq3), join to rabbitmq1 via JOIN_CLUSTER_HOST, add it to haproxy.cfg, then:

   make up
   make wait
   make restart  # to apply HAProxy mapping changes if you altered config

Rolling changes:
- Modify config files, apply with make restart. For sensitive RabbitMQ changes, consult RabbitMQ docs for clustering-safe procedures.

---

## Security hardening
- Secrets:
  - Use a long random RABBITMQ_ERLANG_COOKIE and store it securely.
  - Rotate RABBITMQ_DEFAULT_PASS after bootstrap; create fine-grained users and permissions.
- Network exposure:
  - Keep Management UI bound to localhost; expose it via TLS reverse proxy only.
  - Consider IP allowlists and security groups on 5745.
- TLS:
  - Prefer AMQPS for clients over public networks. Use Nginx stream TLS termination or native RabbitMQ TLS.
- OS hardening:
  - Keep host patched; restrict sudo access; enable a firewall; enforce SSH best practices.

---

## Observability and monitoring
- Logs: Use make logs or make tail for ad-hoc diagnostics.
- Metrics: Consider Prometheus exporters or RabbitMQ native metrics.
- HAProxy stats: haproxy.cfg exposes an HTTP stats page on :1936 by default (adjust as needed; restrict access).

---

## Backup and restore
- Volumes: rabbitmq1-data and rabbitmq2-data store state.
- Backups: Snapshot Docker volumes regularly (e.g., via filesystem snapshots or docker run --rm -v <vol>:/data busybox tar). Ensure consistency by quiescing traffic or using RabbitMQ native export/import if suitable.
- Disaster recovery: Maintain off-host backups and document restore steps.

---

## Disaster recovery notes
- Loss of one node: The remaining node continues. Replace the lost node by recreating its service and rejoining the cluster.
- Loss of all nodes: Restore from backups. Ensure Erlang cookie matches the original cluster.

---

## Troubleshooting
- Containers won’t become healthy:
  - Check make tail for rabbitmq1/rabbitmq2 errors.
  - Ensure RABBITMQ_ERLANG_COOKIE matches across nodes.
- Cannot obtain certificate:
  - Confirm DNS A/AAAA record points to this host and port 80 is open.
  - Rerun sudo make certbot-setup DOMAIN=… EMAIL=…
- Management UI not accessible remotely:
  - By default, it binds to 127.0.0.1 via HAProxy. Use Nginx TLS proxy to publish it securely.
- AMQP connection refused:
  - Verify firewall, HAProxy is up, and rabbitmq services are healthy. Port 5745 should be open to clients.

---

## Makefile targets
- make deploy: Ensure .env exists, start stack, wait for health, show status
- make up: Start services in background
- make down: Stop and remove containers (volumes preserved)
- make restart: Restart services
- make status (ps): Show compose status
- make logs: Show recent logs for all services
- make tail: Follow logs for all services
- make wait: Wait for RabbitMQ services to be healthy
- make init-env: Create .env from sample.env if missing
- make clean: Stop stack and remove named volumes (destructive)
- make nginx-config DOMAIN=…: Generate Nginx config and reload Nginx
- make certbot-setup DOMAIN=… EMAIL=…: Interactive Nginx + Certbot setup
- make tls-setup DOMAIN=… EMAIL=…: Full TLS flow (certs + nginx-config)

---

## Notes on Windows
- The runtime stack runs in containers and is OS-agnostic, but TLS helper scripts (nginx/certbot) assume a Linux host for Nginx/Certbot installation.
- If deploying on Windows Server, handle TLS termination using a Windows-native reverse proxy (IIS/NGINX on Windows) or place a Linux reverse proxy in front.

---

## License
This project is provided as-is under the MIT License (or adapt as needed).