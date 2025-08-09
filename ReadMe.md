# SIPS Connect Platform Easy Deployment Guide.

This guide provides a straightforward approach to deploying the SIPS Connect Platform using Docker and Docker Compose. It is designed for users who may not be familiar with Docker or containerization.

## Prerequisites

1. **Docker**: Ensure Docker is installed on your system. You can download it from [Docker's official website](https://www.docker.com/get-started).
2. **Docker Compose**: This is typically included with Docker Desktop installations. If you're using Linux, you may need to install it separately. Follow the instructions on [Docker Compose's official documentation](https://docs.docker.com/compose/install/).
3. **Git**: Ensure Git is installed to clone the repository. You can download it from [Git's official website](https://git-scm.com/downloads).


## Important Environment Variables

| Variable              | Description                                                      |
|-----------------------|------------------------------------------------------------------|
| DB_PASSWORD           | Database password used by Postgres, Keycloak, and SIPS Connect   |
| HOST_MACHINE_IP       | The IP address of your host machine (used for service URLs)      |
| KEYCLOAK_KEYSTORE_PASSWORD | Password for Keycloak's PKCS#12 SSL certificate (keycloak.p12) |
| SIPS_CONNECT_TLS_PFX_PASSWORD | Password for SIPS Connect's PKCS#12 SSL certificate (sips-connect.pfx) |

## Application Ports

| Service         | Default Port (Host:Container) | Description                |
|-----------------|-------------------------------|----------------------------|
| SIPS Connect    | 9030:8080 (HTTP), 9443:443 (HTTPS) | Main API service         |
| Keycloak (IDP)  | 9031:9031 (HTTPS)             | Identity provider (OIDC)   |
| Grafana         | 9033:3000                     | Monitoring dashboard       |
| Loki            | 3500:3100                     | Log aggregation            |
| Corebank        | 9032:8080                     | Example consumer service   |

## Deployment Steps

1. **Clone the Repository**: Open your terminal and run the following command to clone the SIPS Connect Platform repository:

   ```bash
   git clone https://github.com/SPS-SIPS/Connect.Deployment.git
   ```

2. **Navigate to the Project Directory**: Change into the project directory:
   ```bash
   cd Connect.Deployment
   ```
3. **Create the `.env` File**: Copy the provided `.env.example` file to `.env` in the root directory of the project:

   ```bash
   cp .env.example .env
   ```

   Then edit the `.env` file and update the variables for your environment. The most important variables are explained at the top of this README.
4. **Start the Services**: Use Docker Compose to start the services defined in the `docker-compose.yml` file:
   ```bash
   docker-compose up -d
   ```
5. **Access the Application**: Once the services are up and running, you can access the SIPS Connect Platform at `http://localhost:9080/swagger/index.html` in your web browser.
6. **Access Keycloak**: You can access Keycloak at `http://localhost:9081/auth` to manage your authentication settings.
7. **Access Grafana**: Grafana can be accessed at `http://localhost:9083` for monitoring and visualization.
