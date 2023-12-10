# Deploying RabbitMQ Cluster in Docker

This guide explores several efficient methods for deploying a RabbitMQ cluster using Docker. We emphasize using Docker's official RabbitMQ images, providing flexibility and ensuring you utilize the latest versions.

## Installation Process

Follow these steps to install:

1. **Clone the repository:**

   ```Shell
   git clone https://github.com/cploutarchou/docker-rabbitmq-cluster
   ```

2. **Change to the downloaded directory:**

   ```Shell
   cd docker-rabbitmq-cluster
   ```

3. **Create an `.env` file:**

   Copy the provided `sample.env` file and rename it to `.env`. Modify this new file to reflect your own settings.

   ```Shell
   cp sample.env .env
   ```

4. **Launch the cluster:**

   ```Shell
   docker-compose up
   ```

### Key Attributes

- Standard credentials: `guest`/`guest`.
- Access for Broker: `localhost:5672`.
- Management interface: `localhost:15672`.

## Personalize Your Cluster

By modifying the `.env` file, you can customize default settings like username, password, and the virtual host.

## Integrating HA Proxy

Our `docker-compose.yml` file includes the latest version of HA Proxy, a renowned tool for high availability, load balancing and proxy services. Adding [`port mapping`](https://docs.docker.com/compose/compose-file/#ports) allows easy communication with specific broker nodes.

### Using Local HA Proxy

Alternatively, if you have HA Proxy installed on your local system, you could opt to use that instead of docker-based HA Proxy. Before you do this, ensure that you have HA Proxy correctly set up on your local machine and that it's properly configured to communicate with your Docker services.

To use the local HA Proxy, comment out or remove the HA Proxy service from your `docker-compose.yml` file. Make sure your local HA Proxy listens on the same port defined in your `docker-compose.yml` or make necessary changes in the configuration to reflect the connectivity. Local HA Proxy will direct the traffic to the Docker-based RabbitMQ nodes.