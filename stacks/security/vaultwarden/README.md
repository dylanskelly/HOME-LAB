# Vaultwarden Stack

## Purpose

The Vaultwarden stack provides secure password management and secrets storage for the homelab environment using a self-hosted Bitwarden-compatible server.

The stack is designed to:

* Provide centralized credential management
* Support browser, desktop, and mobile Bitwarden clients
* Integrate with Traefik reverse proxy
* Operate behind Cloudflare Tunnel
* Maintain persistent encrypted vault data
* Support secure backups and disaster recovery

---

## Containers

| Container   | Purpose                               |
| ----------- | ------------------------------------- |
| Vaultwarden | Bitwarden-compatible password manager |

---

## Dependencies

This stack depends on:

* Proxy Stack

  * Traefik
  * Cloudflare Tunnel

Required before deployment:

* Docker Engine
* Docker Compose
* Shared proxy network
* DNS records configured through Cloudflare
* Functional Traefik routing

---

## Networks

| Network | Purpose                                         |
| ------- | ----------------------------------------------- |
| proxy   | Allows Traefik to route requests to Vaultwarden |

The network is created and managed by the proxy stack.

---

## Volumes

| Purpose                                              |
| ---------------------------------------------------- |
| Persistent Vaultwarden database and application data |

All application data is stored outside the container to allow container recreation without data loss.

---

## Environment Variables

Example values only.

```env
VAULTWARDEN_CONTAINER_NAME=vaultwarden
VAULTWARDEN_IMAGE=vaultwarden/server:latest

VAULTWARDEN_HOST=vaultwarden.example.com

TZ=Australia/Sydney

RESTART_POLICY=unless-stopped

PROXY_NETWORK=proxy
```

Do not store secrets directly in environment files.

Use secret files or a dedicated secrets management strategy.

---

## Deployment

Validate configuration:

```bash
docker compose \
  --env-file ../../.env \
  --env-file .env \
  config
```

Start stack:

```bash
docker compose \
  --env-file ../../.env \
  --env-file .env \
  up -d
```

Verify:

```bash
docker ps
docker logs vaultwarden
```

---

## Validation

Check application availability:

```bash
curl -I https://vaultwarden.example.com
```

Check WebAuthn connector:

```bash
curl -I https://vaultwarden.example.com/webauthn-connector.html
```

Expected response:

```text
HTTP/2 200
```

Verify login functionality:

1. Create administrator account
2. Login through web vault
3. Test browser extension
4. Test mobile application
5. Verify vault synchronization

---

## Updating

Pull latest image:

```bash
docker compose pull
```

Recreate container:

```bash
docker compose up -d
```

Verify application health after update.

---

## Future Improvements

Potential future enhancements:

* Cloudflare Access protection
* Automated backup verification
* Health monitoring integration
* Grafana dashboard integration
* Automated update notifications
* Off-site encrypted backup storage

---

## Related Documentation

* ../../README.md
* Proxy Stack Documentation
* Security Stack Documentation
* Backup Policy Documentation
* Vaultwarden Official Documentation
