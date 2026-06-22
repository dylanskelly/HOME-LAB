# Issue: Traefik Returning 502/504 Bad Gateway After Power Outage

## Summary

Following an unexpected power outage and server reboot, all Docker containers appeared to be running and healthy, however all services routed through Traefik returned:

* 502 Bad Gateway
* 504 Gateway Timeout

The issue affected:

* Reverse proxy routing
* Public websites
* Vaultwarden
* Nextcloud
* Other services accessible through Traefik

---

# Symptoms

External access returned:

```text
502 Bad Gateway
```

or

```text
504 Gateway Timeout
```

Containers appeared healthy:

```bash
docker ps
```

Example:

```text
www               Up (healthy)
tafe              Up (healthy)
vaultwarden       Up (healthy)
nextcloud         Up
traefik           Up
cloudflared       Up
```

Traefik routers matched requests correctly:

```bash
curl -I -H "Host: example.com" http://localhost
```

Response:

```text
HTTP/1.1 504 Gateway Timeout
```

---

# Initial Assumptions

The following were investigated but were not the root cause:

* Traefik configuration corruption
* Cloudflare Tunnel failure
* Incorrect startup order
* Missing Docker networks
* DNS resolution issues
* Application container failures
* Volume mount failures

---

# Diagnostic Process

## Verify Traefik Routing

Confirmed Traefik was receiving requests:

```bash
curl -I -H "Host: example.com" http://localhost
```

Result:

```text
HTTP/1.1 504 Gateway Timeout
```

This confirmed:

* Traefik was running
* Router rules were loading
* Requests were reaching Traefik

---

## Verify Backend Service Health

Tested from inside the application container:

```bash
docker exec www wget -S -O- http://localhost:80
```

Result:

```text
HTTP/1.1 200 OK
```

This confirmed:

* Nginx was running
* Website files were accessible
* Container itself was healthy

---

## Verify Container-to-Container Connectivity

Tested from Traefik to the backend service:

```bash
docker exec traefik wget -S -O- http://www:80
```

Result:

```text
Operation timed out
```

Tested direct IP access:

```bash
docker exec traefik wget -S -O- http://<container-ip>:80
```

Result:

```text
Operation timed out
```

This proved:

* DNS was functioning
* Docker network membership was correct
* Network traffic between containers was blocked

---

## Verify Docker Network Membership

Checked network attachments:

```bash
docker network inspect proxy
```

All expected containers were present.

Example:

```text
traefik
cloudflared
www
tafe
vaultwarden
nextcloud
dockhand
```

Therefore network attachment was not the issue.

---

## Inspect Host Firewall Rules

Checked forwarding rules:

```bash
sudo iptables -S FORWARD
```

Result:

```text
-P FORWARD DROP
```

This immediately identified the root cause.

Docker bridge traffic requires packet forwarding.

The FORWARD chain was dropping all forwarded traffic.

As a result:

```text
Traefik -> Backend Container
```

connections were blocked.

---

# Root Cause

Following reboot, the host firewall policy was:

```text
FORWARD DROP
```

Docker bridge networking requires forwarding between containers.

Because forwarding was blocked:

* Traefik could not reach backend containers
* Cloudflared could not reach services through Traefik
* Applications remained healthy but inaccessible

---

# Resolution

Temporarily allow forwarding:

```bash
sudo iptables -P FORWARD ACCEPT
```

Immediately retest:

```bash
docker exec traefik wget -S -O- http://www:80
```

Expected:

```text
HTTP/1.1 200 OK
```

Verify website:

```bash
curl -I -H "Host: example.com" http://localhost
```

Expected:

```text
HTTP/1.1 200 OK
```

Services should become reachable immediately.

---

# Permanent Fix

Check UFW configuration:

```bash
sudo nano /etc/default/ufw
```

Change:

```bash
DEFAULT_FORWARD_POLICY="DROP"
```

to:

```bash
DEFAULT_FORWARD_POLICY="ACCEPT"
```

Reload UFW:

```bash
sudo ufw reload
```

Verify:

```bash
sudo iptables -S FORWARD
```

Expected:

```text
-P FORWARD ACCEPT
```

---

# Lessons Learned

Healthy containers do not guarantee working connectivity.

Always test:

1. Application inside container
2. Container-to-container communication
3. Reverse proxy routing
4. Host firewall forwarding rules

When Traefik returns:

```text
502 Bad Gateway
```

or

```text
504 Gateway Timeout
```

and backend containers are healthy, verify:

```bash
sudo iptables -S FORWARD
```

before rebuilding containers or modifying application configurations.

---

# Prevention

After any:

* Power outage
* Host reboot
* Firewall modification
* UFW configuration change

Validate:

```bash
docker exec traefik wget -S -O- http://service-name:port
```

and:

```bash
sudo iptables -S FORWARD
```

before troubleshooting Docker applications.

This can save significant troubleshooting time and prevent unnecessary container rebuilds.
