# TROUBLESHOOTING.md

# Vaultwarden Stack Troubleshooting Guide

## Introduction

This document serves as the operational troubleshooting knowledge base for the Vaultwarden stack.

Its purpose is to capture real-world issues encountered during deployment, configuration, testing, operation, and maintenance of the Vaultwarden password management service within a Docker-based homelab environment.

Documenting failures, diagnostics, root causes, and resolutions provides several benefits:

* Faster incident resolution
* Improved disaster recovery capability
* Reduced troubleshooting time during rebuilds
* Better knowledge transfer
* Improved operational maturity
* Reduced dependency on memory

This document should be updated whenever new issues are encountered or operational improvements are implemented.

---

# Service Overview

Vaultwarden is a lightweight, self-hosted password manager compatible with Bitwarden clients.

## Primary Functions

* Credential storage
* Secure note storage
* Multi-factor authentication support
* Web vault access
* Mobile and desktop client synchronization

## Dependencies

* Docker Engine
* Docker Compose
* Reverse Proxy
* DNS resolution
* HTTPS termination
* Persistent storage volumes

## Related Services

* Reverse proxy
* DNS provider
* Authentication services
* Backup services

## Typical Traffic Flow

```text
User
  ↓
DNS
  ↓
Reverse Proxy
  ↓
Vaultwarden Container
  ↓
Persistent Storage
```

---

# Troubleshooting Methodology

The following troubleshooting process was used throughout the Vaultwarden deployment.

## 1. Observe Symptoms

Identify the exact user-visible failure.

Examples:

* Validation errors
* Missing headers
* Failed diagnostics
* Access issues

## 2. Establish Scope

Determine whether the issue exists:

* Inside the container
* At the reverse proxy
* At the edge service
* In the browser

## 3. Verify Assumptions

Avoid making configuration changes without evidence.

Validate:

* Labels
* Middleware
* Routing
* Headers
* Service connectivity

## 4. Collect Evidence

Gather:

* Container inspection data
* Header responses
* Logs
* Configuration files

## 5. Isolate Variables

Test each layer independently.

Example:

```text
Vaultwarden
↓
Traefik
↓
Cloudflare
↓
Browser
```

## 6. Test Hypotheses

Validate assumptions using direct commands rather than relying solely on UI diagnostics.

## 7. Implement Changes

Apply the smallest change necessary.

## 8. Validate Results

Confirm:

* Service functionality
* Diagnostic success
* Expected headers
* Client connectivity

## 9. Document Findings

Record:

* Cause
* Resolution
* Prevention

---

# Diagnostic Command Reference

## Container Status

### Check Running Container

```bash
docker ps
```

Purpose:

Verify Vaultwarden is running.

Expected:

```text
Up (healthy)
```

Abnormal:

```text
Exited
Restarting
Unhealthy
```

---

## View Logs

```bash
docker logs vaultwarden
```

Purpose:

Review application startup and runtime errors.

Use when:

* Deployment fails
* Application unavailable
* Unexpected behavior observed

---

## Inspect Container Labels

```bash
docker inspect vaultwarden \
  --format '{{json .Config.Labels}}' | jq
```

Purpose:

Verify Traefik labels.

Useful for:

* Routing issues
* Middleware issues
* Incorrect configuration rendering

---

## Validate Rendered Compose Configuration

```bash
docker compose config
```

Purpose:

Validate the final configuration after variable substitution.

Detects:

* Missing variables
* Syntax errors
* Invalid labels

---

## Local Header Inspection

```bash
curl -I http://localhost/path \
  -H "Host: example.domain"
```

Purpose:

Inspect responses before traffic leaves the local environment.

Useful for:

* Header validation
* Reverse proxy troubleshooting

---

## External Header Inspection

```bash
curl -I https://example.domain/path
```

Purpose:

Inspect responses after DNS, reverse proxy, and edge services.

Useful for:

* Security header validation
* CDN troubleshooting
* Cache verification

---

## Restart Service

```bash
docker restart vaultwarden
```

Purpose:

Reload service configuration.

---

## Restart Reverse Proxy

```bash
docker restart reverse-proxy
```

Purpose:

Reload middleware and routing configuration.

---

# Incident Log

## VW-001

### Title

Vaultwarden Header Validation Failure

### Date/Phase

Initial deployment and post-deployment hardening

### Symptoms

Vaultwarden diagnostics reported:

```text
Header: 'referrer-policy' does not contain 'same-origin'

Header: 'x-xss-protection' does not contain '0'

Header: 'x-frame-options' is present while it should not
```

Additional failures appeared during:

```text
2FA Connector calls
```

### Environment

Affected Components:

* Vaultwarden
* Reverse Proxy
* Middleware Configuration

### Impact

Vaultwarden diagnostics failed.

The application remained functional, but security validation reported errors.

### Investigation

Reviewed:

* Vaultwarden labels
* Reverse proxy middleware configuration
* Dynamic middleware configuration
* Header responses

Commands used:

```bash
docker inspect vaultwarden \
  --format '{{json .Config.Labels}}' | jq
```

```bash
curl -I http://localhost/webauthn-connector.html \
  -H "Host: example.domain"
```

```bash
curl -I https://example.domain/webauthn-connector.html
```

Middleware configuration reviewed.

### Findings

A shared security middleware contained:

```yaml
customFrameOptionsValue: "SAMEORIGIN"
```

This middleware had originally been implemented to support another application.

The middleware conflicted with Vaultwarden's expected behavior.

### Root Cause

A generic security middleware was being considered for use across multiple applications.

Vaultwarden requires application-specific header behavior.

Shared security middleware introduced header conflicts.

### Resolution

Removed security middleware from the Vaultwarden router.

Retained only compression middleware.

Validated headers directly using curl.

### Validation

Local response:

```text
Referrer-Policy: same-origin
X-Xss-Protection: 0
```

External response:

```text
referrer-policy: same-origin
x-xss-protection: 0
```

No unwanted frame header appeared on the WebAuthn connector endpoint.

### Prevention

Do not apply generic security middleware globally.

Use application-specific middleware policies.

Validate headers using direct requests.

### Lessons Learned

Applications may require different security header configurations.

A single security policy should not automatically be assumed suitable for every service.

---

## VW-002

### Title

False Positive Validation Failure Due to Cached Results

### Date/Phase

Post-remediation validation

### Symptoms

Vaultwarden diagnostics continued reporting header failures despite configuration corrections.

### Environment

Affected Components:

* Browser
* Edge caching layer
* Vaultwarden diagnostics

### Impact

Created uncertainty regarding whether remediation had succeeded.

### Investigation

Performed direct header inspection.

Commands used:

```bash
curl -I http://localhost/webauthn-connector.html \
  -H "Host: example.domain"
```

```bash
curl -I https://example.domain/webauthn-connector.html
```

Compared local and external responses.

### Findings

Headers were correct.

Diagnostics continued to display historical results.

### Root Cause

Cached validation results.

Configuration was functioning correctly.

### Resolution

Cleared cached content.

Re-ran diagnostics.

Validation succeeded.

### Validation

Direct header inspection matched expected values.

Diagnostics subsequently passed.

### Prevention

Always validate configuration using direct command-line inspection before making additional changes.

### Lessons Learned

Diagnostic dashboards may report stale information.

Trust direct evidence over assumptions.

---

# Patterns and Recurring Issues

## Shared Middleware Assumptions

Attempting to use a common security middleware across applications introduced conflicts.

Different applications have different header requirements.

---

## Validation Without Direct Testing

Initial troubleshooting relied on application diagnostics.

Direct inspection provided more accurate information.

---

## Cached Results

Cached validation data created confusion after remediation.

Always verify results independently.

---

# Build Evolution

## Initial Implementation

Vaultwarden deployed behind a reverse proxy.

↓

## Security Hardening

Additional middleware introduced for header management.

↓

## Validation Failures

Vaultwarden diagnostics reported header issues.

↓

## Investigation

Middleware configuration reviewed.

Headers validated locally and externally.

↓

## Design Change

Vaultwarden isolated from application-specific security middleware.

↓

## Operational Improvement

Direct header validation became the preferred troubleshooting method.

↓

## Current State

Vaultwarden operates using application-compatible headers and passes validation.

---

# Lessons Learned

## Architecture Lessons

Different services require different security policies.

Avoid one-size-fits-all middleware design.

---

## Operational Lessons

Always validate at each layer:

```text
Application
↓
Reverse Proxy
↓
Edge Layer
↓
Client
```

---

## Troubleshooting Lessons

Use evidence-driven troubleshooting.

Inspect headers directly.

Avoid making configuration changes without verification.

---

## Documentation Lessons

Capture both successful and unsuccessful troubleshooting steps.

Future incidents often follow similar patterns.

---

## Security Lessons

Security hardening can unintentionally reduce application compatibility.

Validate security controls after implementation.

---

## Automation Lessons

Automated diagnostics should supplement—not replace—manual validation.

---

# Future Troubleshooting Checklist

Before making changes:

□ Validate compose configuration

□ Review middleware assignments

□ Confirm routing labels

□ Verify dependency availability

□ Review logs

□ Test local connectivity

□ Test external connectivity

□ Validate headers locally

□ Validate headers externally

□ Confirm cache state

□ Confirm backup availability

□ Document all changes

---

# Recovery Procedures

## Configuration Rollback

Restore previous configuration files.

Restart affected services.

Validate functionality.

---

## Container Rebuild

```bash
docker compose down
docker compose up -d
```

Validate:

* Container status
* Logs
* Routing

---

## Service Redeployment

```bash
docker compose up -d
```

Confirm:

* Labels
* Networks
* Middleware

---

## Volume Recovery

Restore data from backup.

Redeploy service.

Validate client access.

---

## Dependency Recovery

Verify:

* Reverse proxy
* DNS
* Storage

Restart affected services as required.

---

# Appendix

## Useful Commands

```bash
docker ps
```

```bash
docker logs vaultwarden
```

```bash
docker compose config
```

```bash
docker inspect vaultwarden \
  --format '{{json .Config.Labels}}' | jq
```

```bash
curl -I http://localhost/path \
  -H "Host: example.domain"
```

```bash
curl -I https://example.domain/path
```

---

## Useful Logs

Application logs

```text
docker logs vaultwarden
```

Reverse proxy logs

```text
docker logs reverse-proxy
```

---

## Configuration Locations

```text
stacks/security/vaultwarden/
```

```text
data/vaultwarden/
```

```text
data/reverse-proxy/dynamic/
```

---

## Reference Documentation

Vaultwarden Documentation

Docker Compose Documentation

Reverse Proxy Documentation

HTTP Security Headers Documentation

OWASP Secure Headers Guidance

Cloud Provider Caching Documentation

RFC 9110 HTTP Semantics
