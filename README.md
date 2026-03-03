# rpsd

Main orchestration repository for the rpsd platform — a multi-service transit data processing system for Italian transport agencies.

This repo provides Docker Compose orchestration, shared infrastructure configuration, developer scripts, and environment file management. Individual services live in sibling repositories (`rpsd-ingest`, `rpsd-config`, etc.).

## Prerequisites

- Docker and Docker Compose v2.20+
- Git
- Bash (Git Bash or WSL2 on Windows)

## Quick Start

```bash
# 1. Clone all managed repositories
scripts/clone-repos.sh

# 2. Set up environment files
scripts/setup.sh

# 3. Start shared infrastructure (Kafka, Prefect, Keycloak, PostGIS)
scripts/start-shared.sh

# 4. Start application services
scripts/start-services.sh

# 5. Check status
scripts/status.sh
```

## Repository Layout

```
rpsd/
  repos.conf               # Managed repository manifest
  docker-compose.yml        # Main compose entry point
  compose/                  # Compose include files (shared services + app services)
  shared/                   # Shared service configs (Keycloak, Kafka, Postgres, Prefect)
  env/                      # Environment file examples per service and mode
  scripts/                  # Developer workflow scripts
  stacks/                   # Docker Swarm stack files (future)
  charts/                   # Helm charts (future)
  manifests/                # Kubernetes manifests (future)
```

## Scripts

| Script | Purpose |
|--------|---------|
| `clone-repos.sh` | Clone all repos listed in `repos.conf` |
| `setup.sh` | Create `.env` files from examples |
| `start-shared.sh [profiles...]` | Start shared infrastructure |
| `stop-shared.sh [profiles...] [--clean]` | Stop shared infrastructure |
| `start-services.sh [--except svc] [--build]` | Start application services |
| `stop-services.sh` | Stop application services |
| `status.sh` | Show platform status |

## Docker Compose Profiles

| Profile | What it starts |
|---------|---------------|
| `kafka` | Kafka, Kafka UI, Schema Registry |
| `rabbitmq` | RabbitMQ |
| `prefect` | Prefect server, Postgres, Redis |
| `keycloak` | Keycloak, Postgres |
| `config-db` | PostgreSQL + PostGIS (rpsd-config database) |
| `shared` | All shared infrastructure |
| `ingest` | rpsd-ingest |
| `config` | rpsd-config |
| `services` | All application services |
| `all` | Everything |

## Environment Files

The platform uses a layered environment file strategy:

- **`.env.XXX.example`** — committed templates for different scenarios
- **`.env.base`** — gitignored, created by `setup.sh` from the appropriate example
- **`.env`** — gitignored, local overrides

See `DECISIONS.md` for the full architectural rationale.

## Image Management

Image references use variables with public defaults (open mode). Integrators can provide their own image references without forking by overriding variables in `.env` (managed mode).

See `env/.env.compose.images.open.example` and `env/.env.compose.images.managed.example`.
