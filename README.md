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
| `setup.sh [--scenario name] [--service name] [--force]` | Generate `.env` in sibling service repos from their `.env.development` + scenario overrides |
| `start-shared.sh [profiles...]` | Start shared infrastructure |
| `stop-shared.sh [profiles...] [--clean]` | Stop shared infrastructure |
| `start-services.sh [--except svc] [--build]` | Start application services |
| `stop-services.sh` | Stop application services |
| `status.sh` | Show platform status |

`setup.sh` supports two scenarios (pass `--help` for the full reference):

| Scenario | When to use |
|---|---|
| `local-all-in-one` (default) | Everything runs in Docker via rpsd |
| `local-devcontainer` | A service runs in its own devcontainer; shared services via rpsd |

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

## Devcontainer Workflow

When actively developing a service in its own devcontainer, run the shared platform on the host and exclude that service from rpsd's application stack:

```bash
# 1. First-time setup: set up all services with the all-in-one env
scripts/setup.sh

# 2. Override only the service you're developing with the devcontainer env
#    (uses host.docker.internal addresses instead of container hostnames)
scripts/setup.sh --service rpsd-config --scenario local-devcontainer --force

# 3. Start shared infrastructure as normal
scripts/start-shared.sh

# 4. Start OTHER application services in Docker (exclude yours)
scripts/start-services.sh --except rpsd-config

# 5. Open the service in its own devcontainer and start it there
```

The `--service` flag in `setup.sh` and the `--except` flag in `start-services.sh` take the same service name. On Linux devcontainers, `host.docker.internal` may require adding `"--add-host=host.docker.internal:host-gateway"` to the devcontainer's `runArgs`.

## Service Ports

All host port mappings follow the `19xxx` / `20xxx` schema to avoid conflicts with services typically running on developer machines. Container-to-container communication is unaffected and uses standard ports.

```
SHARED (19xxx)                         APPLICATION (20xxx)
190xx Kafka   19000 broker             200xx Ingest  20000 API
              19010 UI                 201xx Config  20100 API
              19020 schema-registry                  20140 config-db
191xx Rabbit  19100 AMQP
              19110 management
192xx Prefect 19200 API+UI
193xx Keycl.  19300 admin
```

All ports are overridable via `RPSD_*_PORT` variables in `.env`. See `DECISIONS.md` § 20 for the full schema and growth rules.

## Environment Files

Each service repo owns its configuration via two committed files:

- **`.env.development`** — complete defaults for local dev (localhost addresses, dev-friendly values)
- **`.env.production`** — complete defaults for production (prod-safe values)

`rpsd` maintains only small **coordination override** files in `env/scenarios/` (hostnames, ports). `setup.sh` merges `.env.development` + scenario overrides → `.env`.

See `DECISIONS.md` § 9 for the full architectural rationale.

## Image Management

Image references use variables with public defaults (open mode). Integrators can provide their own image references without forking by overriding variables in `.env` (managed mode).

See `env/.env.compose.images.open.example` and `env/.env.compose.images.managed.example`.
