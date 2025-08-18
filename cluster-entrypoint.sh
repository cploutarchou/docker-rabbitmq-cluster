#!/bin/sh

set -eu

# Ensure Erlang cookie exists and has correct permissions
if [ -f /var/lib/rabbitmq/.erlang.cookie ]; then
  chmod 400 /var/lib/rabbitmq/.erlang.cookie || true
fi

# Get hostname from environment
HOSTNAME=$(env hostname)
echo "Starting RabbitMQ Server for host: $HOSTNAME"

if [ -z "${JOIN_CLUSTER_HOST:-}" ]; then
  # First node: run in foreground so container keeps running
  exec /usr/local/bin/docker-entrypoint.sh rabbitmq-server
else
  # Peer node: start detached, join cluster idempotently, then keep running in foreground
  /usr/local/bin/docker-entrypoint.sh rabbitmq-server -detached
  # Wait for node to be up
  rabbitmqctl wait /var/lib/rabbitmq/mnesia/rabbit@"$HOSTNAME".pid

  # If already in cluster, skip join
  if rabbitmqctl cluster_status | grep -q "rabbit@$JOIN_CLUSTER_HOST"; then
    echo "Node already part of cluster with rabbit@$JOIN_CLUSTER_HOST; skipping join."
  else
    echo "Joining cluster rabbit@$JOIN_CLUSTER_HOST ..."
    rabbitmqctl stop_app
    rabbitmqctl join_cluster "rabbit@$JOIN_CLUSTER_HOST" || {
      echo "Join failed; will continue with standalone node."
    }
    rabbitmqctl start_app
  fi

  # Replace backgrounded node with foreground process to keep container alive
  exec tail -f /var/lib/rabbitmq/*.log
fi