# TROUBLESHOOTING.md

# Troubleshooting Guide

## Introduction

This document serves as the operational troubleshooting knowledge base for the Nextcloud stack.

The purpose of this guide is to capture real-world deployment issues, investigation techniques, corrective actions, and lessons learned during the implementation and operation of the stack.

The information contained within this document is intended to support:

* Service rebuilds
* Disaster recovery
* Platform migrations
* Future upgrades
* Knowledge transfer
* Operational troubleshooting

The focus is not only on successful fixes, but also on documenting failed assumptions, troubleshooting methodology, and architectural evolution.

---

# Service Overview

The Nextcloud stack provides self-hosted cloud storage and collaboration services.

Core components:

| Component      | Purpose                      |
| -------------- | ---------------------------- |
| Nextcloud      | Application platform         |
| PostgreSQL     | Database backend             |
| Redis          | Cache and file locking       |
| Cron Worker    | Scheduled background jobs    |
| Reverse Proxy  | Routing and security headers |
| Tunnel Service | External access              |

## Typical Traffic Flow

```text
User
  ↓
Cloud Edge
  ↓
Tunnel
  ↓
Reverse Proxy
  ↓
Nextcloud
  ↓
Database
```

Redis provides:

* File locking
* Session optimisation
* Performance improvements

---

# Troubleshooting Methodology

The following process was consistently applied throughout deployment and troubleshooting.

## 1. Observe Symptoms

Examples:

* Health check warnings
* Missing HTTP headers
* Proxy errors
* Background job warnings
* SMTP configuration warnings

---

## 2. Establish Scope

Determine:

* Application issue
* Database issue
* Reverse proxy issue
* Container issue
* Configuration issue

---

## 3. Verify Assumptions

Avoid assuming:

* Environment variables are applied
* Container changes persist
* Reverse proxy configuration is correct
* Security headers are active

Several issues were ultimately caused by incorrect assumptions.

---

## 4. Collect Evidence

Examples:

```bash
docker ps

docker logs nextcloud

docker inspect nextcloud

docker network inspect proxy
```

---

## 5. Isolate Variables

Determine whether issues originated from:

* Nextcloud
* PostgreSQL
* Redis
* Reverse Proxy
* Tunnel
* Container runtime

---

## 6. Test Hypotheses

Examples:

* Verify trusted proxy configuration
* Verify middleware headers
* Verify background job configuration
* Verify mounted volumes

---

## 7. Implement Changes

Changes were made incrementally.

Only one major variable was modified at a time.

---

## 8. Validate Results

Validation methods included:

```bash
curl -I https://example.domain

docker exec -u www-data nextcloud php occ status
```

Administration health checks were used as secondary validation.

---

## 9. Document Findings

All recurring issues and successful resolutions were documented.

---

# Diagnostic Command Reference

## Container Status

### Command

```bash
docker ps
```

### Purpose

Verify container state.

### Expected Output

All Nextcloud containers running.

### Abnormal Output

Stopped containers indicate dependency or configuration issues.

---

## Container Logs

### Command

```bash
docker logs nextcloud
```

### Purpose

Review application startup.

### Expected Output

Successful application initialization.

### Abnormal Output

Apache warnings, startup failures, configuration errors.

---

## Database Health

### Command

```bash
docker logs nextcloud-db
```

### Purpose

Verify PostgreSQL availability.

---

## Redis Health

### Command

```bash
docker logs nextcloud-redis
```

### Purpose

Verify Redis startup.

---

## Network Inspection

### Command

```bash
docker network inspect proxy
```

### Purpose

Identify proxy subnet and network membership.

---

## OCC Status

### Command

```bash
docker exec -u www-data nextcloud php occ status
```

### Purpose

Validate application health.

---

## Background Jobs

### Command

```bash
docker exec -u www-data nextcloud php occ background:cron
```

### Purpose

Verify cron execution mode.

---

## Trusted Proxy Verification

### Command

```bash
docker exec -u www-data nextcloud php occ config:system:get trusted_proxies
```

### Purpose

Validate proxy configuration.

---

## HTTP Header Verification

### Command

```bash
curl -I https://example.domain
```

### Purpose

Verify security headers.

---

# Incident Log

---

## NC-001

### Title

Apache ServerName Warning

### Date/Phase

Initial Deployment

### Symptoms

Application logs contained:

```text
Could not reliably determine the server's fully qualified domain name
```

### Environment

* Nextcloud container
* Apache

### Impact

No functional impact.

### Investigation

Reviewed startup logs.

### Findings

Apache ServerName was not explicitly configured.

### Root Cause

Default Apache configuration.

### Resolution

Accepted as non-critical.

Optional ServerName configuration documented.

### Validation

Application remained functional.

### Prevention

Define Apache server name during deployment.

### Lessons Learned

Not all warnings indicate failures.

---

## NC-002

### Title

Trusted Proxy Misconfiguration

### Date/Phase

Post Deployment Validation

### Symptoms

Administration page reported:

```text
Forwarded for headers
trusted_proxies setting is not correctly set
```

### Environment

* Nextcloud
* Reverse Proxy

### Impact

Client IP forwarding may be inaccurate.

### Investigation

Commands used:

```bash
docker exec -u www-data nextcloud php occ config:system:get trusted_proxies

docker network inspect proxy
```

### Findings

Trusted proxy configured using a container name rather than a valid network CIDR.

### Root Cause

Incorrect assumption that container names were valid proxy identifiers.

### Resolution

Configured trusted proxies using network CIDR ranges.

### Validation

Configuration verified through OCC commands.

### Prevention

Always use valid proxy subnets.

### Lessons Learned

Proxy trust should be defined by network boundaries rather than container names.

---

## NC-003

### Title

Docker Command Executed Inside Container

### Date/Phase

Trusted Proxy Troubleshooting

### Symptoms

Command returned:

```text
docker: command not found
```

### Environment

Nextcloud container shell.

### Impact

Configuration changes could not be applied.

### Investigation

Prompt revealed command was being executed inside the container.

### Findings

Docker CLI is available on the host, not inside application containers.

### Root Cause

Context confusion between host shell and container shell.

### Resolution

Exited container and executed command from host.

### Validation

OCC commands executed successfully.

### Prevention

Confirm shell context before running Docker commands.

### Lessons Learned

Always verify whether the current shell is host or container.

---

## NC-004

### Title

Background Jobs Not Configured

### Date/Phase

Health Check Review

### Symptoms

Administration page reported:

```text
Background jobs not configured correctly
```

### Environment

Nextcloud

### Impact

Scheduled maintenance tasks may not run reliably.

### Investigation

Reviewed administration settings.

### Findings

Cron mode not enabled.

### Root Cause

Default background job configuration.

### Resolution

Configured cron execution mode.

### Validation

Administration page reported successful execution.

### Prevention

Deploy dedicated cron container with initial configuration.

### Lessons Learned

Background jobs are critical for healthy operation.

---

## NC-005

### Title

Missing HSTS Header

### Date/Phase

Security Hardening

### Symptoms

Administration page reported:

```text
Strict-Transport-Security header missing
```

### Environment

* Nextcloud
* Reverse Proxy

### Impact

Reduced transport security.

### Investigation

Reviewed reverse proxy middleware.

### Findings

HSTS headers not being injected.

### Root Cause

Incomplete security middleware configuration.

### Resolution

Added HSTS configuration to reverse proxy.

### Validation

Verified using:

```bash
curl -I https://example.domain
```

### Prevention

Use standardised security middleware.

### Lessons Learned

Application security checks often validate proxy behaviour.

---

## NC-006

### Title

Missing X-Frame-Options Header

### Date/Phase

Security Hardening

### Symptoms

Administration page reported:

```text
X-Frame-Options not set to SAMEORIGIN
```

### Environment

* Nextcloud
* Reverse Proxy

### Impact

Potential clickjacking exposure.

### Investigation

Reviewed middleware configuration.

### Findings

Required frame protection header missing.

### Root Cause

Incomplete reverse proxy security headers.

### Resolution

Added SAMEORIGIN frame configuration.

### Validation

Verified using HTTP response headers.

### Prevention

Use a reusable security middleware baseline.

### Lessons Learned

Security headers belong at the proxy layer.

---

## NC-007

### Title

SMTP Configuration Limitation

### Date/Phase

Application Configuration

### Symptoms

Administration warning regarding email configuration.

### Environment

Nextcloud

### Impact

Notifications and password reset emails unavailable.

### Investigation

Reviewed email provider capabilities.

### Findings

Selected mail provider did not support required SMTP functionality under current plan.

### Root Cause

Provider limitations.

### Resolution

Deferred implementation.

Alternative SMTP providers identified.

### Validation

Not applicable.

### Prevention

Review SMTP requirements before selecting mail providers.

### Lessons Learned

Application email requirements should be considered early.

---

# Patterns and Recurring Issues

## Configuration Source of Truth

Several issues were caused by modifying runtime configuration rather than deployment configuration.

Example:

* Configuration changes made through OCC
* Deployment configuration later overwrote changes

Lesson:

Always update source configuration files.

---

## Proxy-Related Issues

Most warnings originated from:

* Trusted proxies
* HTTP headers
* Reverse proxy integration

The application itself was generally functioning correctly.

---

## Assumption Failures

Common incorrect assumptions included:

* Container names can be used as trusted proxies
* Runtime changes persist permanently
* All warnings indicate application failures

---

# Build Evolution

## Initial Deployment

* Nextcloud
* PostgreSQL
* Redis
* Cron worker

↓

## Health Check Review

* Trusted proxy warning
* Background job warning
* SMTP warning

↓

## Security Hardening

* HSTS implementation
* Frame protection implementation

↓

## Operational Improvements

* Cron configuration
* Proxy validation
* Improved diagnostics

↓

## Current State

Production-ready self-hosted cloud platform behind reverse proxy infrastructure.

---

# Lessons Learned

## Architecture Lessons

* Separate application, cache, and database layers.
* Use dedicated internal networks.

### Operational Lessons

* Validate health checks after deployment.
* Use standardised middleware.

### Troubleshooting Lessons

* Verify assumptions early.
* Confirm execution context.

### Documentation Lessons

* Document warnings before they become incidents.

### Security Lessons

* Reverse proxy configuration directly affects application health checks.

### Automation Lessons

* Automate security header deployment.

---

# Future Troubleshooting Checklist

Before making changes:

□ Validate Docker Compose configuration

□ Confirm container health

□ Verify network connectivity

□ Verify proxy configuration

□ Review environment variables

□ Review mounted volumes

□ Check security headers

□ Verify background jobs

□ Review logs

□ Confirm backups exist

□ Validate rollback plan

---

# Recovery Procedures

## Configuration Rollback

Restore previous Compose configuration.

Redeploy stack.

---

## Container Rebuild

```bash
docker compose down
docker compose up -d
```

---

## Volume Recovery

Restore application, database, and user data from backups.

---

## Dependency Recovery

Verify:

* Database
* Redis
* Reverse proxy

before troubleshooting application layer.

---

# Appendix

## Useful Commands

```bash
docker ps

docker logs nextcloud

docker inspect nextcloud

docker network inspect proxy

docker exec -u www-data nextcloud php occ status

docker exec -u www-data nextcloud php occ background:cron

docker exec -u www-data nextcloud php occ config:system:get trusted_proxies

curl -I https://example.domain
```

---

## Useful Logs

Application:

```text
docker logs nextcloud
```

Database:

```text
docker logs nextcloud-db
```

Cache:

```text
docker logs nextcloud-redis
```

---

## Configuration Locations

```text
stacks/nextcloud/compose.yml
stacks/nextcloud/.env
data/nextcloud/
logs/nextcloud/
```

---

## Reference Documentation

* Nextcloud Administration Guide
* Docker Compose Documentation
* PostgreSQL Documentation
* Redis Documentation
* Reverse Proxy Documentation
* Container Security Best Practices
