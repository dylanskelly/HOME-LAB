# Troubleshooting Guide

# Proxy Stack (Traefik + Cloudflare Tunnel)

---

# Introduction

## Purpose

This document serves as the operational troubleshooting knowledge base for the Proxy Stack.

The Proxy Stack is responsible for:

* Reverse proxying traffic
* Routing requests to backend services
* Providing a centralized ingress layer
* Integrating with Cloudflare Tunnel
* Supporting secure administrative access

This document captures the real issues encountered during implementation and the troubleshooting methodology used to diagnose and resolve them.

The goal is to preserve operational knowledge for:

* Future rebuilds
* Disaster recovery
* Platform upgrades
* Service migrations
* Homelab maintenance
* Knowledge transfer

---

# Service Overview

## Components

### Traefik

Provides:

* Reverse proxy
* Service discovery
* Request routing
* Middleware management
* Dashboard

### Cloudflare Tunnel

Provides:

* Secure ingress
* Cloudflare integration
* Public hostname publishing

---

## Typical Traffic Flow

User

↓

Cloudflare

↓

Cloudflare Tunnel

↓

Traefik

↓

Backend Container

---

## Dependencies

* Docker Engine
* Docker Compose
* Docker Socket
* Shared Proxy Network
* Cloudflare Tunnel
* DNS Records

---

# Troubleshooting Methodology

The following methodology was used consistently throughout the build.

## 1. Observe Symptoms

Example:

* HTTP 404 responses
* Dashboard unavailable
* SSL errors

---

## 2. Establish Scope

Determine whether the issue exists within:

* Cloudflare
* Cloudflare Tunnel
* Traefik
* Docker
* Backend service

---

## 3. Verify Assumptions

Never assume:

* Labels are loaded
* Containers are healthy
* DNS is correct
* Networks are attached

Always validate.

---

## 4. Collect Evidence

Examples:

```bash
docker ps
docker logs traefik
docker inspect traefik
```

---

## 5. Isolate Variables

Example:

Local testing:

```bash
curl -H "Host: example.domain" http://localhost
```

before testing through Cloudflare.

---

## 6. Test Hypotheses

Examples:

* Router configuration issue
* Middleware issue
* DNS issue
* Docker provider issue

---

## 7. Implement Changes

Apply one change at a time.

---

## 8. Validate Results

Verify:

* Logs
* Routing
* Container status

---

## 9. Document Findings

Document both successful and unsuccessful troubleshooting paths.

---

# Diagnostic Command Reference

## Container Status

```bash
docker ps
```

Purpose:

Verify running containers.

Expected:

Container is Up.

Abnormal:

Exited containers indicate startup failure.

---

## Container Logs

```bash
docker logs traefik
```

Purpose:

Review startup and runtime behaviour.

Expected:

Provider startup messages.

Abnormal:

Errors, crashes, restart loops.

---

## Network Inspection

```bash
docker network inspect proxy
```

Purpose:

Verify containers are attached.

Expected:

Traefik and backend services visible.

---

## Render Final Compose

```bash
docker compose \
  --env-file ../../.env \
  --env-file .env \
  config
```

Purpose:

Validate final rendered configuration.

Expected:

No warnings or missing variables.

---

## Router Testing

```bash
curl -H "Host: example.domain" http://localhost
```

Purpose:

Test routing locally.

Expected:

Application response.

Abnormal:

404 indicates routing failure.

---

## Dashboard Testing

```bash
curl -I -H "Host: dashboard.example.domain" \
http://localhost/dashboard/
```

Purpose:

Verify dashboard router.

---

## Docker API Validation

```bash
docker version
```

Purpose:

Verify Docker API compatibility.

---

# Incident Log

## TR-001

### Title

Traefik returned HTTP 404 for all requests.

### Phase

Initial deployment.

### Symptoms

```text
404 page not found
```

for dashboard and websites.

### Environment

* Traefik
* Docker Provider
* Cloudflare Tunnel

### Impact

No services were reachable.

### Investigation

Reviewed:

```bash
docker logs traefik
curl -H "Host: hostname" http://localhost
docker inspect traefik
```

Verified:

* DNS
* Tunnel connectivity
* Labels
* Networks

### Findings

Cloudflare Tunnel successfully reached Traefik.

Traefik was returning the 404.

### Root Cause

Routers were not loading.

### Resolution

Investigated provider and routing configuration.

### Validation

Router testing performed locally.

### Prevention

Always test locally before troubleshooting Cloudflare.

### Lessons Learned

404 from Traefik often indicates router issues rather than DNS issues.

---

## TR-002

### Title

Missing middleware reference.

### Symptoms

Middleware errors.

### Environment

Traefik File Provider.

### Impact

Router configuration instability.

### Investigation

Reviewed:

* Middleware labels
* Dynamic configuration

### Findings

Referenced middleware did not exist.

### Root Cause

Configuration mismatch between labels and dynamic provider.

### Resolution

Corrected middleware definitions.

### Validation

Traefik accepted configuration.

### Prevention

Validate middleware names before deployment.

### Lessons Learned

Middleware failures can appear as routing failures.

---

## TR-003

### Title

Docker Provider API Version Failure.

### Symptoms

Log entries:

```text
client version 1.24 is too old
minimum supported API version is 1.40
```

### Environment

* Traefik
* Docker Engine

### Impact

No routers loaded.

All requests returned 404.

### Investigation

Reviewed:

```bash
docker version
docker logs traefik
tail -f traefik.log
```

Verified:

* Labels
* Networks
* Hostnames
* Dashboard configuration

### Findings

Docker provider repeatedly failed.

Traefik could not retrieve container metadata.

### Root Cause

Docker provider API compatibility issue.

### Resolution

Identified provider failure through file-based logs.

### Validation

Provider startup logs reviewed after configuration changes.

### Prevention

Validate Docker provider after upgrades.

### Lessons Learned

Docker provider failures often present as routing failures.

---

## TR-004

### Title

Invalid Traefik Configuration Field.

### Symptoms

Traefik failed to start.

Log:

```text
field not found, node: apiVersion
```

### Environment

Traefik configuration.

### Impact

Proxy unavailable.

### Investigation

Reviewed recent configuration changes.

### Findings

Unsupported configuration option added.

### Root Cause

Invalid field in configuration file.

### Resolution

Removed unsupported field.

### Validation

Container started successfully.

### Prevention

Validate configuration against official documentation.

### Lessons Learned

Avoid applying undocumented configuration parameters.

---

## TR-005

### Title

Cloudflare Access Authentication Failure.

### Symptoms

Access code not received.

### Environment

Cloudflare Access.

### Impact

Administrative access unavailable.

### Investigation

Reviewed:

* Access policy
* Authentication settings
* Identity provider configuration

### Findings

Identity provider configuration incomplete.

### Root Cause

Authentication provider selection issue.

### Resolution

Configured explicit authentication method.

### Validation

Access workflow tested.

### Prevention

Verify identity providers before application deployment.

### Lessons Learned

Cloudflare Access depends on correctly configured identity providers.

---

## TR-006

### Title

SSL Protocol Mismatch.

### Symptoms

```text
ERR_SSL_VERSION_OR_CIPHER_MISMATCH
```

### Environment

Cloudflare Access.

### Impact

Administrative service unavailable.

### Investigation

Reviewed:

* Hostname configuration
* Cloudflare certificates
* Access application

### Findings

TLS validation failed before application routing.

### Root Cause

Cloudflare-side certificate or hostname configuration issue.

### Resolution

Validated hostname and certificate configuration.

### Prevention

Verify TLS configuration before application troubleshooting.

### Lessons Learned

Not all access issues originate from Traefik.

---

# Patterns and Recurring Issues

Recurring themes observed:

## Routing Assumptions

Repeated assumptions that DNS was the issue when routing was failing locally.

---

## Provider Failures

Docker provider failures caused symptoms that resembled routing problems.

---

## Middleware Dependencies

Missing middleware caused secondary routing failures.

---

## Cloudflare Complexity

Cloudflare Access, Tunnel, DNS, and TLS can each introduce unique failure points.

---

# Build Evolution

Initial Design

↓

Traefik + Cloudflare Tunnel

↓

Routing failures

↓

Middleware troubleshooting

↓

Docker provider investigation

↓

Cloudflare Access implementation

↓

Dashboard hardening

↓

Current architecture

Major changes were driven by security improvements and troubleshooting findings.

---

# Lessons Learned

## Architecture Lessons

* Single ingress point simplifies management.
* Shared proxy network improves scalability.

## Operational Lessons

* Validate locally before testing externally.
* Review file-based logs.

## Troubleshooting Lessons

* Follow evidence.
* Avoid assumptions.

## Documentation Lessons

* Record failed troubleshooting paths.
* Document root causes.

## Security Lessons

* Administrative services should be protected.
* Access control should be implemented early.

## Automation Lessons

* Validation commands should become part of deployment workflows.

---

# Future Troubleshooting Checklist

Before making changes:

□ Validate compose configuration

□ Verify environment variables

□ Confirm network attachments

□ Check container health

□ Verify provider startup

□ Review Traefik logs

□ Test routing locally

□ Verify DNS

□ Verify Cloudflare Tunnel

□ Verify Cloudflare Access

□ Confirm backups exist

---

# Recovery Procedures

## Configuration Rollback

Restore:

* compose.yml
* .env
* traefik.yml
* dynamic configuration

Redeploy stack.

---

## Container Rebuild

```bash
docker compose down
docker compose up -d
```

---

## Network Recovery

```bash
docker network create proxy
```

Verify attachment.

---

## Service Recovery

Validate:

```bash
docker compose config
```

before redeployment.

---

# Appendix

## Useful Commands

```bash
docker ps
docker logs traefik
docker inspect traefik
docker network inspect proxy
docker version
docker compose config
curl -H "Host: example.domain" http://localhost
```

---

## Useful Logs

Traefik:

```text
logs/traefik
```

Cloudflared:

```text
logs/cloudflared
```

---

## Configuration Locations

Compose:

```text
stacks/proxy/compose.yml
```

Environment:

```text
stacks/proxy/.env
```

Traefik:

```text
data/traefik/traefik.yml
```

Dynamic Configuration:

```text
data/traefik/dynamic/
```

---

## Reference Documentation

* Docker Documentation
* Docker Compose Documentation
* Traefik Documentation
* Cloudflare Tunnel Documentation
* Cloudflare Access Documentation
