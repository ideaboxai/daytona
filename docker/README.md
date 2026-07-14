# Docker Compose Setup for Daytona

This folder contains a Docker Compose setup for running Daytona locally.

⚠️ **Important**:

- This setup is still in development and is **not safe to use in production**
- A separate deployment guide will be provided for production scenarios

## Overview

The Docker Compose configuration includes all the necessary services to run Daytona:

- **API**: Main Daytona application server
- **Proxy**: Request proxy service
- **Runner**: Service that hosts the Daytona Runner
- **SSH Gateway**: Service that handles sandbox SSH access
- **Database**: PostgreSQL database for data persistence
- **Redis**: In-memory data store for caching and sessions
- **Dex**: OIDC authentication provider
- **Registry**: Docker image registry with web UI
- **MinIO**: S3-compatible object storage
- **MailDev**: Email testing service
- **Jaeger**: Distributed tracing
- **PgAdmin**: Database administration interface

## Quick Start

1. Create the secrets file `docker/.env` (gitignored). The compose file contains only
   `${VAR}` references, no secret values. Required keys: `ENCRYPTION_KEY`,
   `ENCRYPTION_SALT`, `DB_PASSWORD`, `REGISTRY_ADMIN`, `REGISTRY_PASSWORD`,
   `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`, `PROXY_API_KEY`, `DAYTONA_RUNNER_TOKEN`,
   `SSH_GATEWAY_API_KEY`, `OTEL_COLLECTOR_API_KEY`, `HEALTH_CHECK_API_KEY`,
   `PGADMIN_DEFAULT_PASSWORD`, `SSH_GATEWAY_HOST`, `SSH_GATEWAY_PUBLIC_KEY`,
   `SSH_PRIVATE_KEY`, `SSH_HOST_KEY`.

   ```bash
   # generate values:
   openssl rand -hex 32                                   # random secrets / passwords
   ssh-keygen -t rsa -b 4096 -N '' -f gw                  # gateway auth pair
   ssh-keygen -t rsa -b 4096 -N '' -f host                # host key
   base64 -w0 gw   # SSH_PRIVATE_KEY   | base64 -w0 gw.pub  # SSH_GATEWAY_PUBLIC_KEY
   base64 -w0 host # SSH_HOST_KEY
   ```

   If you set/change `DB_PASSWORD`, also write `docker/pgadmin4/pgpass` (gitignored) as
   `db:5432:*:user:<DB_PASSWORD>` so pgAdmin can auto-connect.

2. Start all services (from the root of the Daytona repo). The `--env-file` flag is
   required because the env file lives in `docker/`, not the working directory:

   ```bash
   docker compose --env-file docker/.env -f docker/docker-compose.yaml up -d
   ```

3. Access the services:
   - Daytona Dashboard: http://localhost:3000
     - Access Credentials: dev@daytona.io `password`
     - Make sure that the default snapshot is active at http://localhost:3000/dashboard/snapshots
   - PgAdmin: http://localhost:5050
   - Registry UI: http://localhost:5100
   - MinIO Console: http://localhost:9001 (credentials = `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` from `.env`)

## Reverse proxy / TLS (self-hosting)

TLS is terminated by an **external** load balancer / reverse proxy; no proxy runs in
this compose stack. The containers speak plain HTTP on their published ports — the
external proxy does HTTPS and forwards. `PROXY_PROTOCOL=https` tells the api/proxy to
advertise `https` in generated URLs and set secure cookies, so the external proxy MUST
forward `X-Forwarded-Proto: https`.

Required routes (all HTTPS → HTTP upstreams):

| Public host / path                                     | Upstream            |
| ------------------------------------------------------ | ------------------- |
| `dev-daytona.ideaboxai.com` (root, `/api`, `/dashboard`) | `api:3002` (host `:3002`)   |
| `dev-daytona.ideaboxai.com/dex`                        | `dex:5556` (host `:5556`)   |
| `proxy.dev-daytona.ideaboxai.com`                      | `proxy:4003` (host `:4003`) |
| `*.proxy.dev-daytona.ideaboxai.com` (wildcard, sandbox previews) | `proxy:4003` (host `:4003`) |
| TCP `:2222` (SSH gateway, no TLS)                      | `ssh-gateway:2222` (host `:2222`) |

The wildcard `*.proxy.dev-daytona.ideaboxai.com` needs DNS + a wildcard TLS cert for
sandbox preview URLs to resolve. Set `SSH_GATEWAY_HOST` in `docker/.env` to the public
address sandboxes SSH into.

## DNS Setup for Proxy URLs

For local development, you need to resolve `*.proxy.localhost` domains to `127.0.0.1`:

```bash
./scripts/setup-proxy-dns.sh
```

This configures dnsmasq with `address=/proxy.localhost/127.0.0.1`.

**Without this setup**, SDK examples and direct proxy access won't work.

## Development Notes

- The setup uses shared networking for simplified service communication
- Database and storage data is persisted in Docker volumes
- The registry is configured to allow image deletion for testing
- Sandbox resource limits are disabled due to inability to partition cgroups in DinD environment where the sock is not mounted

<br><br><br>

# Auth0 Configuration Guide for Daytona

## Step 1: Create Your Auth0 Tenant

Begin by navigating to https://auth0.com/signup and start the signup process. Choose your account type based on your use case - select `Company` for business applications or `Personal` for individual projects.\
On the "Let's get setup" page, you'll need to enter your application name such as `My Daytona` and select `Single Page Application (SPA)` as the application type. For authentication methods, you can start with `Email and Password` since additional social providers like Google, GitHub, or Facebook can be added later. Once you've configured these settings, click `Create Application` in the bottom right corner.

## Step 2: Configure Your Single Page Application

Navigate to `Applications` > `Applications` in the left sidebar and select the application you just created. Click the `Settings` tab and scroll down to find the `Application URIs` section where you'll configure the callback and origin URLs.
In the `Allowed Callback URIs` field, add the following URLs:

```
http://localhost:3000
http://localhost:3000/api/oauth2-redirect.html
http://localhost:4000/callback
http://proxy.localhost:4000/callback
```

For `Allowed Logout URIs`, add:

```
http://localhost:3000
```

And for `Allowed Web Origins`, add:

```
http://localhost:3000
```

Remember to click `Save Changes` at the bottom of the page to apply these configurations.

## Step 3: Create Machine-to-Machine Application

You'll need a Machine-to-Machine application to interact with Auth0's Management API. Go to `Applications` > `Applications` and click `Create Application`. Choose `Machine to Machine Applications` as the type and provide a descriptive name like `My Management API M2M`.
After creating the application, navigate to the `APIs` tab within your new M2M application. Find and authorize the `Auth0 Management API` by clicking the toggle or authorize button.\
Once authorized, click the dropdown arrow next to the Management API to configure permissions. Grant the following permissions to your M2M application:

```
read:users
update:users
read:connections
create:guardian_enrollment_tickets
read:connections_options
```

Click `Save` to apply these permission changes.

## Step 4: Set Up Custom API

Your Daytona application will need a custom API to handle authentication and authorization. Navigate to `Applications` > `APIs` in the left sidebar and click `Create API`. Enter a descriptive name such as `My Daytona API` and provide an identifier like `my-daytona-api`. The identifier should be a unique string that will be used in your application configuration.\
After creating the API, go to the `Permissions` tab to define the scopes your application will use. Add each of the following permissions with their corresponding descriptions:

| Permission | Description |
|------------|-------------|
| `read:node` | Get workspace node info |
| `create:node` | Create new workspace node record |
| `create:user` | Create user account |
| `read:users` | Get all user accounts |
| `regenerate-key-pair:users` | Regenerate user SSH key-pair |
| `read:workspaces` | Read workspaces (user scope) |
| `create:registry` | Create a new docker registry auth record |
| `read:registries` | Get all docker registry records |
| `read:registry` | Get docker registry record |
| `write:registry` | Create or update docker registry record |

## Step 5: Configure Environment Variables

Once you've completed all the Auth0 setup steps, you'll need to configure environment variables in your Daytona deployment. These variables connect your application to the Auth0 services you've just configured.

### Finding Your Configuration Values

You can find the necessary values in the Auth0 dashboard. For your SPA application settings, go to `Applications` > `Applications`, select your SPA app, and click the `Settings` tab. For your M2M application, follow the same path but select your Machine-to-Machine app instead. Custom API settings are located under `Applications` > `APIs`, then select your custom API and go to `Settings`.

### API Service Configuration

Configure the following environment variables for your API service:

```bash
OIDC_CLIENT_ID=your_spa_app_client_id
OIDC_ISSUER_BASE_URL=your_spa_app_domain
OIDC_AUDIENCE=your_custom_api_identifier
OIDC_MANAGEMENT_API_ENABLED=true
OIDC_MANAGEMENT_API_CLIENT_ID=your_m2m_app_client_id
OIDC_MANAGEMENT_API_CLIENT_SECRET=your_m2m_app_client_secret
OIDC_MANAGEMENT_API_AUDIENCE=your_auth0_managment_api_identifier
```

### Proxy Service Configuration

For your proxy service, configure these environment variables:

```bash
OIDC_CLIENT_ID=your_spa_app_client_id
OIDC_CLIENT_SECRET=
OIDC_DOMAIN=your_spa_app_domain
OIDC_AUDIENCE=your_custom_api_identifier (with trailing slash)
```

Note that `OIDC_CLIENT_SECRET` should remain empty for your proxy environment.
