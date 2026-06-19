# Dockhand Stack

## Purpose

The Dockhand stack provides a web-based Docker management interface for operational visibility and administration of the homelab environment.

Dockhand enables:

* Container monitoring
* Container lifecycle management
* Log viewing
* Network inspection
* Volume inspection
* Image management
* Basic operational troubleshooting

This service is intended as an administrative platform for managing Docker workloads running throughout the homelab.

---

## Containers

| Container | Purpose                                        |
| --------- | ---------------------------------------------- |
| Dockhand  | Docker management and administration interface |

---

## Dependencies

This stack depends on:

* Docker Engine
* Existing Docker network used by the reverse proxy
* Traefik reverse proxy
* Cloudflare Tunnel
* Cloudflare Access

The stack is designed to be accessible through the existing reverse proxy architecture rather than exposing management ports directly.

---

## Networks

| Network | Purpose                      |
| ------- | ---------------------------- |
| proxy   | Shared reverse proxy network |

---

## Volumes

| Volume Purpose            |
| ------------------------- |
| Dockhand application data |
| Docker socket access      |

---

## Environment Variables

Example variables:

```env
DOCKHAND_CONTAINER_NAME=dockhand
DOCKHAND_IMAGE=fnsys/dockhand:latest

DOCKHAND_INTERNAL_PORT=3000

DOCKER_GID=999

TZ=Australia/Sydney
```

Actual values should be stored in the stack environment file.

---

## Deployment

Navigate to the stack directory:

```bash
cd stacks/dockhand
```

Validate configuration:

```bash
docker compose \
  --env-file ../../.env \
  --env-file .env \
  config
```

Deploy:

```bash
docker compose \
  --env-file ../../.env \
  --env-file .env \
  up -d
```

---

## Validation

Verify container status:

```bash
docker ps
```

View logs:

```bash
docker logs dockhand
```

Confirm application availability through the reverse proxy.

Verify Docker environments appear online within the Dockhand dashboard.

---

## Updating

Pull the latest image:

```bash
docker compose pull
```

Recreate the container:

```bash
docker compose up -d
```

Verify successful startup:

```bash
docker logs dockhand
```

---

## Architecture Evolution

### Original Design

Dockhand was initially deployed as a Docker management interface connected through the existing Traefik and Cloudflare infrastructure.

### Issue Encountered

After deployment the Dockhand interface loaded successfully, however no containers appeared and the configured environment displayed as Offline.

### Final Design

Dockhand was configured to use a Unix socket connection to the local Docker daemon.

The environment was updated to:

```text
Unix Socket
/var/run/docker.sock
```

This immediately restored visibility of all Docker containers and established successful communication with the Docker Engine.

---

## Future Improvements

Potential future enhancements include:

* Integration with operational runbooks
* Container health monitoring workflows
* Dashboard customisation
* Administrative role separation
* Additional management tooling integration

Examples:

* Portainer
* Homepage
* Uptime Kuma
* Dockge

---

## Related Documentation

* ../../README.md
* Traefik Stack Documentation
* Cloudflare Tunnel Documentation
* Homelab Architecture Documentation
