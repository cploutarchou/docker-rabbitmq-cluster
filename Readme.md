# Deploying a Production-Ready RabbitMQ Cluster in Docker

This project provides a simple, production‑oriented setup for a two‑node RabbitMQ cluster fronted by HAProxy. It uses official images, pins stable versions, adds health checks, and persists data across restarts.

## Prerequisites
- Docker and Docker Compose (v2 recommended)
- Ports available: 5672 (AMQP) and 15672 (management via HAProxy)

## Installation

1. Clone the repository:

   ```Shell
   git clone https://github.com/cploutarchou/docker-rabbitmq-cluster
   cd docker-rabbitmq-cluster
   ```

2. Create an `.env` file (do not use defaults in production):

   ```Shell
   cp sample.env .env
   # Edit .env and set strong values, especially RABBITMQ_ERLANG_COOKIE and password
   ```

3. Launch the cluster:

   ```Shell
   docker compose up -d
   ```

### What you get
- Two RabbitMQ nodes (rabbitmq1 and rabbitmq2) using `rabbitmq:3.13-management-alpine`
- HAProxy `2.8` that load balances AMQP (5672) and management (15672)
- Persistent volumes for broker data
- Healthchecks for RabbitMQ nodes

### Default Access
- Broker (AMQP): `localhost:5672`
- Management UI (via HAProxy): `http://localhost:15672`
  - Credentials are set from `.env` for the first node. Change them immediately for production.

## Configuration

All configuration is driven via the `.env` file:
- `RABBITMQ_ERLANG_COOKIE` must be the same on all nodes; treat it as a secret.
- `RABBITMQ_DEFAULT_USER`, `RABBITMQ_DEFAULT_PASS`, `RABBITMQ_DEFAULT_VHOST` bootstrap the first node only.

HAProxy configuration lives in `haproxy.cfg`. The compose file mounts it read‑only.

## Scaling to 3 Nodes
This example ships with two nodes. To add a third node:
1. Duplicate the `rabbitmq2` service in `docker-compose.yml` as `rabbitmq3`.
2. Set `hostname: rabbitmq3` and `environment: [JOIN_CLUSTER_HOST=rabbitmq1, RABBITMQ_ERLANG_COOKIE=${RABBITMQ_ERLANG_COOKIE}]`.
3. Add a new named volume for `rabbitmq3` data.
4. Add a `server rabbitmq3` line in both `rabbitmq` and `mgmt` sections of `haproxy.cfg`.
5. `docker compose up -d` to start the new node.

## Production Notes
- Credentials: Never use `guest/guest`. Use strong admin credentials and rotate regularly.
- Persistence: This setup uses named volumes (`rabbitmq1-data`, `rabbitmq2-data`). Ensure your Docker host is backed up.
- Health: Each node exposes a healthcheck via `rabbitmq-diagnostics ping`. HAProxy also performs TCP health checks.
- Security:
  - Management UI is exposed via HAProxy on localhost only in compose. If deploying remotely, restrict access (firewalls, security groups, VPN).
  - Consider enabling TLS for AMQP and management in a production deployment. This example does not configure TLS by default.
- Upgrades: Images are pinned to stable versions. To upgrade, change tags in `docker-compose.yml` and redeploy.
- Logs: Container logs are available via `docker logs`. The join script tails RabbitMQ logs on peer nodes.

## Using a Local HAProxy Instead
If you prefer a locally installed HAProxy, remove or comment out the HAProxy service in `docker-compose.yml`, and replicate the ports and backends defined in `haproxy.cfg` on your host HAProxy. Ensure it can reach the Docker network or map host ports directly to the containers.

## Troubleshooting
- Cluster Join Issues: Ensure `RABBITMQ_ERLANG_COOKIE` is identical across nodes. The entrypoint script is idempotent and skips join if already clustered.
- Permission Errors: Docker handles the Erlang cookie; the script will fix permissions if needed.
- Ports in Use: Change published ports in compose or stop conflicting services.

## Makefile Usage
You can deploy and manage the stack using the provided Makefile. Common commands:
- make deploy
  - Ensures .env exists (copies from sample.env if missing), starts services, waits for health, and shows status.
- make up
  - Starts services in detached mode.
- make down
  - Stops and removes containers (volumes are preserved).
- make status (or make ps)
  - Shows docker compose ps.
- make logs
  - Shows last 100 lines of logs for all services.
- make tail
  - Follows logs for all services.
- make wait
  - Waits until rabbitmq1 and rabbitmq2 are healthy (based on healthchecks).
- make init-env
  - Creates .env from sample.env if missing.
- make clean
  - Stops the stack and removes named volumes (data destructive).
