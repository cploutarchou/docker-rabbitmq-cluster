# Deploying RabbitMQ Cluster in Docker

This guide aims to explore several effective methods to deploy a RabbitMQ cluster using Docker. A key emphasis is placed on using Docker's official RabbitMQ images, granting flexibility and ensuring access to the latest versions.

## Installation Process
Follow the steps below to install:

1. **Clone the repository:**

   Use the following command to clone the repository:

   ```Shell
   git clone https://github.com/cploutarchou/docker-rabbitmq-cluster
   ```

2. **Change to the downloaded directory:**

   Navigate to the directory where the repository has been cloned:

   ```Shell
   cd docker-rabbitmq-cluster
   ```

3. **Launch the cluster:**

   Use Docker Compose to start the services defined in your docker-compose configuration file:

   ```Shell
   docker-compose up
   ```

### Key Attributes

Below are the default settings for the service:

- Standard credentials: `guest`/`guest`.
- Access for Broker: `localhost:5672`.
- Management interface: `localhost:15672`.

## Personalize Your Cluster

By modifying the `.env` file, you can tweak the default settings like username, password, and the virtual host.

## Integrating HA Proxy

Our `docker-compose.yml` file includes the use of the latest HA Proxy version, a highly recognized tool for high availability load balancing and proxy services. By adding [`port mapping`](https://docs.docker.com/compose/compose-file/#ports), communication with specific broker nodes becomes fairly easy.