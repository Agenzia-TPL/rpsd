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
    config-db/             # PostgreSQL + PostGIS for rpsd-config
      Dockerfile
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
  shared/              # shared service configs (Keycloak, Kafka, config-db, Prefect)
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
# NAME            TYPE      DEPS
rpsd-commons      library
rpsd-ingest       service   rpsd-commons
rpsd-config       service
```

Each line contains a repository name, a type, and an optional comma-separated list of library dependencies:

- **`service`** — a runnable application; gets a Docker Compose profile and is started by `start-services.sh`
- **`library`** — a build dependency only; cloned by `clone-repos.sh` but has no compose profile
- **`DEPS`** — library repos whose changes should trigger a rebuild of the service image (see § 29)

**Rationale:**
- The parent directory may contain unrelated `rpsd-*` repos (forks, experiments, archived services) that should not be touched
- An explicit list makes the set of managed repos auditable and version-controlled
- The type column keeps `start-services.sh` from trying to start libraries as services
- The deps column enables smart rebuild detection without parsing compose files in shell

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
  shared-config-db.yml    # PostgreSQL + PostGIS (rpsd-config database)
  services.yml            # rpsd-ingest, rpsd-config, ...
```

**Rationale:**
- A single entry point means `docker compose` is always run from the repo root — no `-f` flag juggling
- Splitting by service group keeps each file focused and easy to read
- Adding a new shared service means adding one new file and one `include:` line

**Path resolution note:** Paths inside included files (build contexts, volume mounts) resolve relative to the **included file's own directory**. Files in `compose/` therefore use `../../rpsd-ingest` to reach a sibling repo and `../shared/` to reach the `shared/` directory.

---

## 18. Shared Docker Network

**Decision:** All shared services and application services join a single Docker network named `rpsd-network`. Containers reach each other by service name (e.g. `kafka:9092`, `config-db:5432`, `prefect:4200`).

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
| `rpsd-config/.devcontainer/docker-compose-database.yml` | `compose/shared-config-db.yml` + `shared/config-db/` |

**Rationale:**
- Having two authoritative sources for the same service configuration will eventually diverge
- The sibling-repo configs were the right starting point for understanding what needed to be migrated; keeping them during bringup reduces risk
- Once verified, removal from sibling repos is straightforward and makes the platform easier to reason about

---

## 20. Host Port Allocation Schema

**Decision:** All host port mappings follow a structured numbering schema using two dedicated thousand-ranges:

- **`19xxx`** — shared infrastructure services
- **`20xxx`** — rpsd application services (including their dedicated databases)

This avoids conflicts with well-known ports commonly running on developer machines (PostgreSQL 5432, Kafka 9092, Redis 6379, etc.) and with OS ephemeral port ranges (Linux 32768+, macOS 49152+).

### Block Structure

Each service group occupies a **100-port block** identified by the hundreds digit (e.g. `190xx`, `191xx`). Within each block, only ports `xx00–xx49` are used initially; `xx50–xx99` are **reserved** for future service insertion within the same block.

### Sub-Offset Convention

| Offset | Purpose |
|---|---|
| `xx00` | Primary protocol/API |
| `xx01` | Secondary protocol |
| `xx10` | Web UI / management |
| `xx20` | Ancillary API |
| `xx40` | Dedicated database |
| `xx50–xx99` | Reserved for future expansion |

### Current Assignments

```
SHARED (19xxx)                         APPLICATION (20xxx)
190xx Kafka   19000 broker             200xx Ingest  20000 API
              19001 KRaft              201xx Config  20100 API
              19010 UI                               20140 config-db
              19020 schema-registry    202xx Flow    20200 API (future)
191xx Rabbit  19100 AMQP
              19110 management
192xx Prefect 19200 API+UI
193xx Keycl.  19300 admin
```

### Growth Rules

- **Insert between existing groups:** use the reserved `xx50–xx99` range within an adjacent block
- **Exceed 10 groups:** extend to adjacent thousands — shared overflows into `18xxx`, application overflows into `21xxx`
- **Service needs a dedicated database:** use offset `xx40` within its block (e.g. config-db at `20140` within rpsd-config's `201xx` block)

### Rationale

- **Two ranges** make shared infrastructure (19xxx) visually distinct from application services (20xxx)
- **100-port blocks with reserved upper half** balance readability with growth capacity (10 groups now, expandable to 20, then further via overflow)
- **Co-locating a service with its database** in the same block (e.g. rpsd-config at `20100` and config-db at `20140`) makes their relationship immediately obvious
- **All ports are overridable** via `RPSD_*_PORT` environment variables, so developers who prefer standard ports can set them locally
- Container-to-container communication is unaffected — services still use internal hostnames and standard container ports (e.g. `kafka:9092`, `config-db:5432`)

---

## 21. CI/CD Platform (Open Mode)

**Decision:** GitHub Actions is the open-mode CI/CD platform for the `rpsd` platform.

**Structure (per §13):**

- **Per-service repos** (`rpsd-ingest`, `rpsd-config`, `rpsd-commons`): run tests, build image, push to registry
- **`rpsd`**: builds shared images (e.g. `config-db`) and holds deployment definitions

**Rationale:**

- All repositories are on GitHub; GitHub Actions requires no additional infrastructure
- Integrators on other CI platforms (GitLab CI, Jenkins, etc.) can replicate the workflows — they perform standard steps (checkout, buildx, push) with no GitHub-specific magic
- `GITHUB_TOKEN` (auto-provided) covers image pushes to ghcr.io without extra credentials; the only additional secret needed is `GH_REPO_TOKEN` for cross-repo checkout (rpsd-ingest → rpsd-commons)

---

## 22. Image Registry (Open Mode)

**Decision:** `ghcr.io` (GitHub Container Registry) is the open-mode container registry.

Images are published under `ghcr.io/rapsodia/rpsd-<service>`.

| Image | Registry path |
|---|---|
| rpsd-ingest | `ghcr.io/rapsodia/rpsd-ingest` |
| rpsd-config | `ghcr.io/rapsodia/rpsd-config` |
| config-db | `ghcr.io/rapsodia/rpsd-config-db` |

**Rationale:**

- ghcr.io is tightly integrated with GitHub Actions; pushing images requires only the auto-provided `GITHUB_TOKEN`
- The existing image variable abstraction (§11) lets integrators substitute their own registry without changing any code — they provide different `RPSD_IMAGE_*` values

---

## 23. Image Tagging Strategy

**Decision:** Every main-branch push produces two tags:

- `latest` — for convenient use in development and staging
- `sha-<7-char-commit>` — for traceability and rollback

Future release tags (e.g. `v1.2.3`) are added at release time via Git tags triggering the same workflow.

**Rationale:**

- SHA tags make it possible to know exactly which code is running and to roll back to a specific commit
- `latest` keeps developer and staging workflows simple — no need to look up commit SHAs

---

## 24. Multi-Architecture Builds

**Decision:** CI produces multi-architecture images (`linux/amd64`, `linux/arm64`) via Docker Buildx.

**Rationale:**

- ARM64 is required: developers use Apple Silicon and the platform targets ARM servers
- AMD64 is included for x86 server compatibility
- Multi-arch manifests are transparent to consumers — Docker automatically pulls the right variant

---

## 25. Docker Swarm Stack Files

**Decision:** Docker Swarm stack files live in `stacks/` and are maintained separately from Docker Compose files in `compose/`.

**Stack files vs Compose files:**

| Feature | Compose (`compose/`) | Swarm (`stacks/`) |
|---|---|---|
| `build:` | Yes — used for local dev | No — images must come from registry |
| `depends_on:` | Yes | No — Swarm ignores it |
| `profiles:` | Yes | No — Swarm ignores it |
| `deploy:` | Ignored | Yes — replicas, update policy, etc. |
| Secrets | Bind-mounted env files | Docker Secrets |
| Network driver | `bridge` | `overlay` |

A single `stacks/rpsd-stack.yml` covers all services. Stack files use the same `RPSD_IMAGE_*` variables as compose files, so the open/managed mode distinction (§11) applies unchanged.

**Sensitive credentials** are managed via Docker Secrets (`external: true`), which must be created before deploying:

```bash
printf 'password' | docker secret create rpsd_config_db_pass -
```

PostgreSQL images natively support `POSTGRES_PASSWORD_FILE`; Keycloak supports `KC_DB_PASSWORD_FILE` and `KEYCLOAK_ADMIN_PASSWORD_FILE`; RabbitMQ supports `RABBITMQ_DEFAULT_PASS_FILE`.

---

## 26. Deployment Approach (Swarm)

**Decision:** Initial deployments to Docker Swarm are manual — via `docker stack deploy` or via Portainer's Git-based stack feature. Automated CD from CI is not implemented in the first iteration.

**Portainer workflow:**

1. Point Portainer at the `rpsd` Git repository, selecting `stacks/rpsd-stack.yml`
2. Set environment variables (image tags, hostnames, Prefect URL) in Portainer's stack env editor
3. Portainer deploys the stack and can redeploy on demand or via webhook

**Rationale:**

- Manual deployment is sufficient for staging and reduces the blast radius of CI errors reaching the cluster
- Portainer's Git integration provides a GitOps-like experience without additional tooling
- Automated CD can be layered on later (a GitHub Actions deployment job that SSH-es into the Swarm manager)

---

## 27. Kubernetes Manifests — Kustomize

**Decision:** Kubernetes deployment manifests use **Kustomize** and live in `manifests/`. Helm is not used.

**Structure:**

```
manifests/
  base/                    # Environment-agnostic resources (all 12 services)
    kustomization.yaml     # Lists all resource subdirectories
    namespace.yaml         # Namespace: rpsd
    secrets.yaml           # Single Secret with 5 keys (dev defaults)
    kafka/                 # One subdirectory per service group
    kafka-ui/
    schema-registry/
    rabbitmq/
    prefect-db/
    prefect-redis/
    prefect/
    keycloak-db/
    keycloak/
    config-db/
    rpsd-ingest/
    rpsd-config/
  overlays/
    local/                 # minikube / Docker Desktop (NodePort patches)
    eks/                   # AWS EKS (StorageClass, Ingress, image tag pins)
```

Each service subdirectory contains a `kustomization.yaml`, `deployment.yaml`, `service.yaml`, and optionally `pvc.yaml` or `configmap.yaml`. Service names match Docker Compose service names (`kafka`, `config-db`, `rpsd-ingest`, etc.) so that inter-service URLs remain identical.

**Rationale:**

- Kustomize is built into `kubectl` — no additional binary, no chart repository, no release state in the cluster
- Produces plain YAML that is easy to read, inspect, and diff in pull requests
- FluxCD (mentioned as the target GitOps tool for integrators) natively supports Kustomization resources, making `manifests/overlays/eks/` directly deployable
- The base + overlays pattern cleanly separates environment-agnostic resources from environment-specific patches (StorageClass, NodePort, image tags)
- Follows the project principle of introducing complexity only when there is a concrete need; Helm can be layered on later if redistributable chart packaging becomes necessary
- The `charts/` directory remains reserved for a potential future Helm chart

**Relationship to Swarm stack:**

The Kustomize manifests are a Kubernetes translation of `stacks/rpsd-stack.yml`. Key mapping:

| Swarm concept | Kubernetes equivalent |
|---|---|
| Docker Secrets (external) | K8s Secret (`rpsd-secrets`) with `stringData` |
| Docker Configs | K8s ConfigMap (`config-db-init`) |
| Named volumes | PersistentVolumeClaims |
| `overlay` network | Namespace-scoped DNS (service names) |
| `deploy.replicas` | `spec.replicas` in Deployment |
| `depends_on` | Init containers (`busybox nc -z`) |
| `RPSD_IMAGE_*` env vars | Kustomize `images:` transformer in overlays |

---

## 28. Service Images Are Self-Contained

**Decision:** Each service's production Dockerfile defines its own default startup command via `CMD`. Deployment configurations (Docker Compose, Docker Swarm, Kubernetes) do **not** specify the startup command unless they intentionally need to override the default (e.g. running a worker variant of the same image).

**Example (rpsd-config Dockerfile):**

```dockerfile
ENTRYPOINT ["./entrypoint.sh"]
CMD ["gunicorn", "rpsd_config.server.asgi:application", "-c", "gunicorn.conf.py"]
```

**Rationale:**
- Eliminates coupling between `rpsd` and service repos: when a service changes how it starts, only its own Dockerfile needs updating — `rpsd` deployment configs remain untouched
- Follows standard Docker convention: `docker run <image>` works without external knowledge
- The `ENTRYPOINT` + `CMD` composition pattern allows the entrypoint script to run pre-flight setup (e.g. creating missing `.env` files) before executing the command
- Since `ENV PATH` includes `.venv/bin`, executables installed by `uv` (like `gunicorn` or `server`) are directly available without the `uv run` prefix
- Devcontainers are unaffected — they use separate Dockerfiles (`.devcontainer/Dockerfile`)

**Multi-service repos (future):** When a repo produces multiple services from one image, the `CMD` serves as the default for the primary service. Secondary services override via `command:` (Compose/Swarm) or `args:` (Kubernetes). The override is intentional and explicit ("this is the worker variant"), not a required piece of internal knowledge.

---

## 29. Smart Rebuild Detection

**Decision:** `start-services.sh` automatically detects which service images are stale and rebuilds only those, without requiring the `--build` flag.

**Mechanism:**

1. Each service Dockerfile includes a label that stores git commit hashes of its source repos:
   ```dockerfile
   ARG RPSD_BUILD_SOURCES="unknown"
   LABEL rpsd.build.sources="${RPSD_BUILD_SOURCES}"
   ```
2. At build time, `start-services.sh` computes a composite label from the service repo's HEAD and its library dependencies' HEADs (declared in `repos.conf`), then passes it as a build arg
3. Before starting, the script reads the label from the existing image and compares it with the current git state
4. Only services with mismatched hashes (or missing images/labels) are rebuilt

**Example label value:** `rpsd-ingest:a1b2c3d4e5f6,rpsd-commons:f6e5d4c3b2a1`

**Edge cases:**
- Image doesn't exist → treated as stale, triggers build
- Image exists but has no label (pre-migration) → treated as stale, one-time rebuild adds the label
- Service repo not cloned → warning printed, skip check, try existing image
- Dirty working tree → ignored (hash tracks committed state only, appropriate for dependency services)
- `--build` flag → force-rebuilds all active services with labels embedded for future detection

**Rationale:**
- Developers no longer need to remember `--build` after pulling changes to service repos
- Only stale services are rebuilt, avoiding unnecessary build time
- The `ARG` + `LABEL` is placed after all `COPY`/`RUN` instructions so that changing the hash does not invalidate Docker's layer cache for dependencies or source code
- Library dependency tracking (via `repos.conf` DEPS column) ensures that changes to shared libraries like `rpsd-commons` correctly trigger rebuilds of dependent services

