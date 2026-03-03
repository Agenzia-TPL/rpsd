# rpsd Platform

## Preface

This document summarises the architectural decisions taken for the `rpsd` platform — a multi-service transit data processing system designed for Italian transport agencies. The platform processes NeTEx and SIRI transit feeds through validation, transformation, and notification workflows.

The system is composed of several independent Python services, each living in its own repository (`rpsd-ingest`, `rpsd-config`, etc.), plus a main orchestration repository simply called `rpsd`. Services communicate over HTTP and a message broker (Kafka or RabbitMQ). Shared infrastructure includes Keycloak for IAM, PostgreSQL for storage, and Prefect for orchestration. Data fiels are saved to shared File System or to S3 compatible service.

The decisions recorded here emerged from a design conversation focused on making `rpsd` the right home for orchestration, deployment, and developer tooling — without letting it become a source of unnecessary complexity. The guiding principle throughout was: **prefer simple, maintainable solutions over engineered ones**, and introduce complexity only when there is a concrete, demonstrated need.

This document is intended as a reference and starting point for implementing the `rpsd` repository. Each section states the decision clearly and explains the reasoning behind it, so that future contributors understand not just *what* was decided, but *why*.

# Architecture Decisions

## 1. Repository Naming

**Decision:** The main orchestration repository is named `rpsd`.

**Rationale:**
- It is the natural root of the `rpsd-*` namespace
- `rpsd-deploy` would be misleading since the repo covers development too
- Mirrors the common convention where the platform repo is the short name and services are `platform-*`

---

## 2. Repository Structure

**Decision:** All service repositories and the main repository are **siblings**, never nested.

```
<parent directory>/
  rpsd/           ← main orchestration repo
  rpsd-ingest/    ← service repo
  rpsd-config/    ← service repo
  ...
```

**Decision:** Each service repo's devcontainer mounts the parent directory as `/workspaces`, so sibling repos are mutually visible from inside any devcontainer. `rpsd` has no devcontainer — it accesses sibling repos directly via the host machine filesystem, where the same sibling layout applies. The parent directory path on the host is wherever the developer clones the repositories.

---

## 3. No Devcontainer for `rpsd`

**Decision:** `rpsd` does **not** use a devcontainer.

**Rationale:**
- There is no Python code to run or debug inside `rpsd`
- Content is bash scripts and configuration files, editable in any editor
- All Docker/Kubernetes CLI operations run on the host
- A devcontainer can always be added later if a genuine need arises (e.g. Python utility scripts with dependencies)

---

## 4. CLI Tools — Where They Live

**Decision:**

| Tool | Where |
|---|---|
| Docker CLI | Host machine only |
| kubectl | CI runner only |
| helm | CI runner only |

**Rationale:**
- Kubernetes deployments are handled exclusively by the CI pipeline — no developer touches the cluster directly
- Docker is well supported natively on Linux, macOS, and Windows
- Keeping the host lean avoids Docker-outside-of-Docker complexity in devcontainers
- `kubectl` and `helm` in CI runners are either pre-installed or added in a pipeline step

---

## 5. Cross-Platform Script Strategy

**Decision:** Scripts are written in **bash only**. No PowerShell equivalents.

**Rationale:**
- Windows developers with Docker Desktop already have Git Bash (bundled with Git for Windows) or WSL2
- The number of scripts is small (~5-6), making dual maintenance not worth the effort
- README documents the requirement: "Windows requires Git Bash or WSL2"

---

## 6. Scripts in `rpsd`

**Decision:** The following scripts will exist in `rpsd`:

1. `clone-repos.sh` — git clone all sibling repos into their sibling directories
2. `start-shared.sh` — start shared services (Kafka/RabbitMQ, Prefect, Keycloak, PostgreSQL)
3. `stop-shared.sh`
4. `start-services.sh --except <service>` — start all rpsd-* services except specified ones
5. `stop-services.sh`
6. `status.sh` — show running containers and clone status of managed repos

---

## 7. Starting Services Selectively

**Decision:** Use Docker Compose **profiles** to selectively start/stop services, with a bash wrapper handling `--profile` flags.

This allows a developer to start all services except the one they are actively developing in their own devcontainer.

---

## 8. Shared Services Configuration

**Decision:** Shared service configurations (Keycloak, Kafka/RabbitMQ, PostgreSQL, Prefect) live **inside `rpsd`**, not in separate repositories.

**Rationale:**
- No code is being written, only configuration
- No separate team ownership or release cycle
- A separate repo would just be a folder of config files

**Exception:** If Keycloak configuration grows substantially (custom themes, Java extensions), it may earn its own repo. Start in `rpsd` and extract only if genuinely needed.

```
rpsd/
  shared/
    keycloak/
      realm-import/        # realm JSON files imported by Keycloak on startup
      .env.example
    kafka/
      .env.example
    rabbitmq/
      .env.example
    prefect/
      .env.example
    postgis/               # PostGIS, not plain Postgres
      init.sql
      .env.example
```

The `.env.example` files under `shared/` document only the variables that developers commonly override (ports, credentials). Everything else is hardcoded in the corresponding compose file with `${VAR:-default}` fallbacks.

---

## 9. Environment File Strategy

### Pattern (established across all service repos)

- `.env.XXX.example` — committed to repo, documents variables for a specific deployment scenario
- `.env.base` — **gitignored**, created at setup time by copying the appropriate `.env.XXX.example`
- `.env` — **gitignored**, actual local overrides on top of `.env.base`

Pydantic Settings reads `.env.base` and `.env` directly. Docker Compose does **not** inject them via `env_file:` or `environment:` for Python services (this would override Pydantic's precedence chain).

### Volume Mounting (not Compose injection)

Env files are **volume-mounted** into containers:

```yaml
volumes:
  - ./.env.base:/app/.env.base:ro
  - ./.env:/app/.env:ro
```

This allows values to be changed and picked up with a service restart, without rebuilding images.

### Exception: Nginx (needs env vars for template substitution)

```yaml
env_file:
  - path: ./.env.base
    required: false
  - path: ./.env
    required: false
```

### Env Files Are a Developer Workstation Concern Only

`.env` files **never leave developer workstations**. Every other context uses its own native secret mechanism:

| Context | Mechanism |
|---|---|
| Local dev | `.env.base` + `.env` volume-mounted |
| CI/CD | Runner secrets/variables injected as env vars |
| Docker Swarm staging | Docker Secrets or env files on Swarm node |
| Kubernetes | ConfigMaps + Kubernetes Secrets (optionally Vault) |

---

## 10. `rpsd`-Level Env Files

**Decision:** `rpsd` maintains its own `.env.*.example` files per service, covering the "services running together" scenario, which differs from standalone devcontainer scenarios (e.g. `DATABASE_HOST=postgres` vs `DATABASE_HOST=localhost`).

```
rpsd/
  env/
    rpsd-ingest/
      .env.local-all-in-one.example
      .env.local-external-db.example
      .env.staging.example
    rpsd-config/
      .env.local-all-in-one.example
      .env.staging.example
```

The actual `.env` files are gitignored. A `setup.sh` script in `rpsd` assists developers in copying the right examples.

---

## 11. Image Management — Open vs Managed Mode

**Decision:** `rpsd` is **opinionated about what to deploy, unopinionated about where images come from**.

All image references use variables, never hardcoded names. A canonical `.env.compose.images` file defines all image references:

```
rpsd/
  env/
    .env.compose.images.open.example
    .env.compose.images.managed.example   ← documents what an integrator needs to provide
    rpsd-ingest/
      .env.local-all-in-one.example
      .env.staging.example
    rpsd-config/
      .env.local-all-in-one.example
      .env.staging.example
```

**Open mode** (default): public images, public registry, works out of the box.  
**Managed mode**: integrators provide their own `images.managed.env` externally, without forking `rpsd`.

This keeps `rpsd` forkless for integrators — they extend through configuration, not by copying and modifying.

The mirror pipeline (pulling, scanning, re-tagging official images for a private registry) is **not** an `rpsd` concern — it belongs to the integrating organisation's own infrastructure team.

---

## 12. Test Strategy

**Decision:** Tests must be **environment-agnostic**.

- **Unit tests** — mock all external dependencies, no real DB or broker, no env values needed
- **Integration tests** — spin up dependencies via `docker-compose.test.yml` with fixed well-known credentials defined in test setup, not from `.env` files

Docker image versions in test compose files must be **pinned to match production** to avoid infrastructure-level parity issues. Defining canonical image versions is an `rpsd` concern.

---

## 13. CI/CD Structure

**Decision:** CI/CD follows a two-level structure:

- **Per-service repos** handle: run tests, build image, push to registry
- **`rpsd`** handles: deploy all or specific services to Swarm/Kubernetes, manage shared infrastructure definitions

Kubernetes deployments go exclusively through the CI pipeline. No developer runs `kubectl` or `helm` locally.

---

## 14. `rpsd` Directory Layout (Summary)

```
rpsd/
  repos.conf           # managed repository manifest (see § 15)
  docker-compose.yml   # main compose entry point — includes compose/*
  shared/              # shared service configs (Keycloak, Kafka, PostGIS, Prefect)
  compose/             # Docker Compose include files, one per shared service group
  env/                 # rpsd-level .env.XXX.example files per service + image refs
  scripts/             # clone-repos.sh, start-shared.sh, start-services.sh, etc.
  stacks/              # Docker Swarm stack files (future)
  charts/              # Helm charts for Kubernetes (future)
  manifests/           # raw k8s manifests if not using Helm (future)
  .github/workflows/   # CI/CD pipelines (future)
```

---

## 15. Managed Repository Manifest

**Decision:** `rpsd` maintains an explicit list of managed repositories in `repos.conf`, rather than scanning the parent directory for `rpsd-*` siblings.

```
# NAME            TYPE
rpsd-commons      library
rpsd-ingest       service
rpsd-config       service
```

Each line contains a repository name and a type:

- **`service`** — a runnable application; gets a Docker Compose profile and is started by `start-services.sh`
- **`library`** — a build dependency only; cloned by `clone-repos.sh` but has no compose profile

**Rationale:**
- The parent directory may contain unrelated `rpsd-*` repos (forks, experiments, archived services) that should not be touched
- An explicit list makes the set of managed repos auditable and version-controlled
- The type column keeps `start-services.sh` from trying to start libraries as services

---

## 16. Git Clone URL Inference

**Decision:** `clone-repos.sh` derives sibling repository URLs automatically from `rpsd`'s own remote `origin`, rather than storing URLs in `repos.conf`.

**Mechanism:** `git remote get-url origin` on the `rpsd` repo returns a URL such as `git@github.com:Rapsodia/rpsd.git`. The script strips the trailing repo name to obtain the organisation prefix (`git@github.com:Rapsodia`), then appends each name from `repos.conf` to form the full clone URL. This works identically for SSH and HTTPS remotes.

**Fallback:** When `rpsd` has no remote configured (e.g. before it is pushed for the first time), the script exits with a clear error and instructions. A `--base-url` flag accepts the organisation prefix explicitly:

```bash
./scripts/clone-repos.sh --base-url git@github.com:Rapsodia
./scripts/clone-repos.sh --base-url https://github.com/Rapsodia
```

**Rationale:**
- URLs are never duplicated between `repos.conf` and git config
- Works for any hosting provider (GitHub, GitLab, self-hosted) without changing the manifest
- When the organisation or hosting changes, only `rpsd`'s own remote needs to be updated

---

## 17. Docker Compose File Structure

**Decision:** `docker-compose.yml` at the repo root is the single entry point for all `docker compose` commands. It uses `include:` to delegate to smaller files in `compose/`:

```
compose/
  shared-kafka.yml        # Kafka + Kafka UI + Schema Registry
  shared-rabbitmq.yml     # RabbitMQ
  shared-prefect.yml      # Prefect server + its Postgres + Redis
  shared-keycloak.yml     # Keycloak + its Postgres
  shared-postgis.yml      # PostGIS (application database)
  services.yml            # rpsd-ingest, rpsd-config, ...
```

**Rationale:**
- A single entry point means `docker compose` is always run from the repo root — no `-f` flag juggling
- Splitting by service group keeps each file focused and easy to read
- Adding a new shared service means adding one new file and one `include:` line

**Path resolution note:** Paths inside included files (build contexts, volume mounts) resolve relative to the **included file's own directory**. Files in `compose/` therefore use `../../rpsd-ingest` to reach a sibling repo and `../shared/` to reach the `shared/` directory.

---

## 18. Shared Docker Network

**Decision:** All shared services and application services join a single Docker network named `rpsd-network`. Containers reach each other by service name (e.g. `kafka:9092`, `postgis:5432`, `prefect:4200`).

**Consequence for Kafka:** The existing `host-scripts` configuration advertised Kafka as `host.docker.internal:9092`, which was necessary when consumers lived in devcontainers connecting via the host. In `rpsd`, consumers are co-located on the same Docker network, so `KAFKA_ADVERTISED_LISTENERS` is set to `PLAINTEXT://kafka:9092` instead.

**Rationale:**
- A single network is the natural topology for the "all services together" scenario
- Per-service networks (as used in the original host-scripts) would require each application container to join multiple networks, adding fragile configuration
- Standalone devcontainer setups are unaffected — they retain their own compose files and networks

---

## 19. Consolidation of Shared Service Configs

**Decision:** `rpsd` is the sole long-term home for shared service configurations. Equivalent configs that currently exist in sibling repos are temporary and will be removed once `rpsd` is working end-to-end.

| Current location | Moves to `rpsd` |
|---|---|
| `rpsd-commons/host-scripts/kafka/` | `compose/shared-kafka.yml` + `shared/kafka/` |
| `rpsd-commons/host-scripts/rabbitmq/` | `compose/shared-rabbitmq.yml` + `shared/rabbitmq/` |
| `rpsd-commons/host-scripts/prefect/` | `compose/shared-prefect.yml` + `shared/prefect/` |
| `rpsd-config/.devcontainer/docker-compose-keycloak.yml` | `compose/shared-keycloak.yml` + `shared/keycloak/` |
| `rpsd-config/.devcontainer/docker-compose-database.yml` | `compose/shared-postgis.yml` + `shared/postgis/` |

**Rationale:**
- Having two authoritative sources for the same service configuration will eventually diverge
- The sibling-repo configs were the right starting point for understanding what needed to be migrated; keeping them during bringup reduces risk
- Once verified, removal from sibling repos is straightforward and makes the platform easier to reason about
