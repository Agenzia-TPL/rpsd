# rpsd — Project Context

## Overview

`rpsd` is the main orchestration repository for the Rapsodia platform — a multi-service transit data processing system for Italian transport agencies. It provides Docker Compose orchestration, shared infrastructure configuration, developer workflow scripts, and environment file management.

This repo contains no application code. Its content is bash scripts, Docker Compose YAML, and configuration files.

## Architectural Decisions

All architectural decisions are recorded in `DECISIONS.md`. That file is the authoritative reference for *what was decided and why*. Read it before making changes that affect the platform structure.

## Technology & Conventions

### Bash Scripts
- All scripts live in `scripts/` and begin with `#!/bin/bash` and `set -e`
- Common functions are in `scripts/_lib.sh` — always source it, never duplicate its helpers
- Use the output helpers: `print_info`, `print_success`, `print_warn`, `print_error`
- Parse `repos.conf` through `parse_repos_conf` or `get_service_repos`, not by hand
- Scripts must work on macOS, Linux, and Windows (Git Bash / WSL2)

### Docker Compose
- `docker-compose.yml` is the single entry point — never require `-f` flags
- Shared services are split into `compose/shared-*.yml` files, included via `include:`
- Every `image:` value uses a variable with a default: `${RPSD_IMAGE_X:-public/image:tag}`
- Profiles control selective start/stop — see `DECISIONS.md` § 7
- All services join `rpsd-network` — see `DECISIONS.md` § 18
- Host port defaults follow the `19xxx`/`20xxx` schema — see `DECISIONS.md` § 20; never use standard ports as defaults

### Environment Files
- Follow the `.env.XXX.example` → `.env.base` → `.env` pattern from `DECISIONS.md` § 9
- Env files are volume-mounted, not injected via `env_file:`
- Shared service overrides go in `shared/<service>/.env.example`
- Per-service "all-in-one" examples go in `env/<service>/`

### Repository Manifest
- `repos.conf` lists managed repos (name + type + optional deps) — see `DECISIONS.md` § 15
- Git URLs are inferred from rpsd's own origin — see `DECISIONS.md` § 16

### Image Management
- All images must support **ARM64** (linux/arm64) — the platform targets Apple Silicon and ARM servers
- PostgreSQL-based services standardize on `postgres:17` as the base version
- Keycloak uses `quay.io/keycloak/keycloak:26.3`
- The official `postgis/postgis` image does not support ARM64; a custom Dockerfile in `shared/config-db/` builds PostGIS from `postgres:17` + Debian packages instead
- Database services use the `-db` naming suffix: `keycloak-db`, `config-db`, `prefect-db`
- Open/managed mode defaults are in `env/.env.compose.images.open.example` and `env/.env.compose.images.managed.example` — see `DECISIONS.md` § 11

## Current Scope

| Repository | Type | Status |
|---|---|---|
| rpsd-commons | library | Managed (build dependency) |
| rpsd-ingest | service | Managed (primary service) |
| rpsd-config | service | Managed (secondary, incomplete) |

## Future Work

<!-- Add next specifications / tasks below this line -->

- Verify end-to-end: start shared services, build and run rpsd-ingest, confirm connectivity
- Export and commit Keycloak realm JSON to `shared/keycloak/realm-import/` (then enable `rpsd_keycloak_realm` config in `stacks/rpsd-stack.yml`)
- Remove `host-scripts/` from rpsd-commons once rpsd is verified
- Remove shared service compose files from rpsd-config/.devcontainer/ once rpsd is verified
- Add rpsd-flow to `repos.conf` and `compose/services.yml` when it has a production Dockerfile
- Verify rpsd-config pytest configuration (`DJANGO_SETTINGS_MODULE` in pyproject.toml is a placeholder)
- Add application service environment variable documentation to `env/rpsd-ingest/` and `env/rpsd-config/` for staging scenarios
- Set up `GH_REPO_TOKEN` secret in rpsd-ingest repository (required for CI cross-repo checkout of rpsd-commons)
- Test Swarm stack deployment end-to-end (single-node Swarm, then Portainer)
- Kubernetes: initial Kustomize manifests created in `manifests/` (base + local/eks overlays) — see `DECISIONS.md` § 27
- Kubernetes: test deployment on minikube or Docker Desktop K8s, verify all 12 services start
- Kubernetes: test deployment on AWS EKS
- Kubernetes: FluxCD-compatible GitOps structure for integrators using GitLab + FluxCD
- Kubernetes: add Ingress resource for EKS overlay
- Kubernetes: integrate ExternalSecrets or SealedSecrets for EKS secret management
