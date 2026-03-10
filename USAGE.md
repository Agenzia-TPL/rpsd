# rpsd Usage Guide

## Local Development

### Prerequisites

- Docker with Docker Compose v2
- Git
- bash (or zsh on macOS)

### Quick start

```bash
# 1. Clone the rpsd repo and sibling service repos
git clone git@github.com:Rapsodia/rpsd.git
cd rpsd
./scripts/clone-repos.sh

# 2. Set up environment files
./scripts/setup.sh

# 3. Start shared infrastructure
./scripts/start-shared.sh

# 4. Start all application services (or exclude the one you're developing)
./scripts/start-services.sh
./scripts/start-services.sh --except rpsd-config   # developing rpsd-config in a devcontainer

# 5. Check status
./scripts/status.sh
```

### Stopping services

```bash
./scripts/stop-services.sh
./scripts/stop-shared.sh
```

---

## CI/CD Setup (GitHub Actions + ghcr.io)

Each service repo contains a `.github/workflows/ci.yml` that:

1. Runs lint and unit tests on every push and pull request
2. Builds and pushes a multi-arch Docker image to `ghcr.io` on every push to `main`

### Required GitHub secret: `GH_REPO_TOKEN`

`rpsd-ingest` checks out `rpsd-commons` at build time. This requires a fine-grained
Personal Access Token (PAT) with read access to `rpsd-commons`, stored as a
repository secret named `GH_REPO_TOKEN` in the `rpsd-ingest` repo.

**Create the token:**

Fine-grained PATs are personal but can be scoped to an organization's repos.
Since all `rpsd-*` repos are owned by the Rapsodia org:

1. Go to your **personal** GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens
2. Click **Generate new token**
3. Under **Resource owner**, select **Rapsodia** (the org — not your personal account)
4. Under **Repository access**, choose **Only select repositories** → `rpsd-commons`
5. Under **Permissions → Repository permissions → Contents**: `Read-only`
6. Generate and copy the token

> **Org approval:** depending on the Rapsodia org's settings, the token may need approval
> from an org owner before it works. Check under:
> Rapsodia org → Settings → Third-party Access → Personal access tokens.
> If approval is required, an org owner will receive a notification to approve it.

**Store the secret:**

> **GitHub Free plan limitation:** organization secrets cannot be used by private repositories.
> Store the secret directly in each private repo that needs it.

1. Go to `rpsd-ingest` → Settings → Secrets and variables → Actions → **New repository secret**
2. Name: `GH_REPO_TOKEN`, value: `<your token>`

Repeat for any other private service repo that needs cross-repo checkout in the future.

> On a **GitHub Team or Enterprise** plan, you can instead store the secret once at the org level:
> Rapsodia org → Settings → Secrets and variables → Actions → New organization secret,
> then grant access to the specific private repos.

### Long-term alternative: GitHub App

A PAT is tied to a person — if that person leaves the org, the token stops working and
CI breaks. A **GitHub App** solves this: it is an independent identity registered in the
organisation, not owned by any individual, and it issues short-lived tokens (1 hour) that
are automatically rotated on every workflow run.

**Why GitHub Apps are better than PATs for CI:**

| | Fine-grained PAT | GitHub App |
|---|---|---|
| Identity | Tied to a personal account | Org-level, independent |
| Token lifetime | Long-lived (until expiry or revocation) | 1 hour (auto-rotated) |
| Survives staff changes | No — breaks if owner leaves | Yes |
| Auditable | Per-user audit log | Dedicated app audit log |
| Scope | Set once at creation | Requested per workflow run |

**Setup (one-time, done by an org owner):**

1. Go to Rapsodia org → Settings → Developer settings → GitHub Apps → **New GitHub App**
2. Fill in:
   - **App name**: e.g. `rpsd-ci`
   - **Homepage URL**: `https://github.com/Rapsodia/rpsd`
   - **Webhooks**: uncheck *Active* (not needed)
3. Under **Repository permissions → Contents**: `Read-only`
4. Under **Where can this GitHub App be installed**: `Only on this account`
5. Click **Create GitHub App** — note the **App ID** shown on the next page
6. Scroll down → **Private keys** → **Generate a private key** (downloads a `.pem` file)
7. Go to the app page → **Install App** → install it on the Rapsodia org,
   granting access to **Only select repositories** → `rpsd-commons`

**Store credentials as org-level secrets:**

```
Rapsodia org → Settings → Secrets and variables → Actions → New organization secret
```

| Secret name | Value |
|---|---|
| `GH_APP_ID` | The numeric App ID from step 5 |
| `GH_APP_PRIVATE_KEY` | The full contents of the `.pem` file from step 6 |

Grant both secrets to `rpsd-ingest` (and any other repos that need cross-repo access).

> **GitHub Free plan limitation:** same as for PATs — org secrets are not available to private
> repos on the free plan. Store `GH_APP_ID` and `GH_APP_PRIVATE_KEY` as repository-level secrets
> in each private repo, or upgrade to GitHub Team/Enterprise to use org-level secrets.

**Update the workflow** (replace the `GH_REPO_TOKEN` steps with):

```yaml
- name: Generate GitHub App token
  id: app-token
  uses: actions/create-github-app-token@v1
  with:
    app-id: ${{ secrets.GH_APP_ID }}
    private-key: ${{ secrets.GH_APP_PRIVATE_KEY }}
    repositories: rpsd-commons

- name: Check out rpsd-commons
  uses: actions/checkout@v4
  with:
    repository: Rapsodia/rpsd-commons
    token: ${{ steps.app-token.outputs.token }}
    path: rpsd-commons
```

The `actions/create-github-app-token` action exchanges the app credentials for a
short-lived installation token scoped to `rpsd-commons`, which `actions/checkout` uses
exactly like a PAT. No other changes to the workflow are needed.

### Published images

| Service | Image |
|---|---|
| rpsd-ingest | `ghcr.io/agenzia-tpl/rpsd-ingest:latest` |
| rpsd-config | `ghcr.io/agenzia-tpl/rpsd-config:latest` |
| config-db | `ghcr.io/agenzia-tpl/rpsd-config-db:latest` |

Images are also tagged with `sha-<7-char-commit>` for traceability.

### Making images public (optional)

By default, ghcr.io packages are private. To make them public:

1. Go to `https://github.com/orgs/Agenzia-TPL/packages`
2. For each package, go to Package settings → Change visibility → Public

---

## Docker Swarm Deployment

### Prerequisites

- A server (or local machine) running Docker in Swarm mode
- The rpsd repository checked out on the Swarm manager node (or deploy via Portainer)

### 1. Initialise Docker Swarm (if not already done)

```bash
docker swarm init
```

### 2. Create Docker Secrets

Secrets must be created before deploying the stack:

```bash
printf 'your-keycloak-db-password'    | docker secret create rpsd_keycloak_db_pass -
printf 'your-keycloak-admin-password' | docker secret create rpsd_keycloak_admin_pass -
printf 'your-config-db-password'      | docker secret create rpsd_config_db_pass -
printf 'your-prefect-db-password'     | docker secret create rpsd_prefect_db_pass -
printf 'your-rabbitmq-password'       | docker secret create rpsd_rabbitmq_pass -
```

Use strong, random passwords in production. `openssl rand -base64 24` generates a good one.

### 3. Configure environment variables

```bash
cp stacks/.env.example stacks/.env
# Edit stacks/.env with your values:
#   - RPSD_KEYCLOAK_HOSTNAME (external URL of Keycloak, e.g. http://192.168.1.100:19300)
#   - RPSD_PREFECT_DB_URL (full connection URL including prefect-db password)
#   - RPSD_PREFECT_API_URL (external URL of the Prefect API)
#   - Any image overrides for private registry (managed mode)
```

### 4. Deploy the stack

Run from the repo root (paths in the stack file are relative to where you run the command):

```bash
docker stack deploy --env-file stacks/.env -c stacks/rpsd-stack.yml rpsd
```

### 5. Verify

```bash
docker stack services rpsd
docker service logs rpsd_rpsd-ingest
```

### Updating a service

After a new image is pushed to the registry:

```bash
docker service update --image ghcr.io/agenzia-tpl/rpsd-ingest:sha-abc1234 rpsd_rpsd-ingest
# Or update all services to latest:
docker stack deploy --env-file stacks/.env -c stacks/rpsd-stack.yml rpsd
```

### Removing the stack

```bash
docker stack rm rpsd
```

This stops and removes all containers. Volumes (data) are preserved.

---

## Portainer Deployment

[Portainer](https://www.portainer.io/) provides a web UI for managing Docker Swarm stacks.

### Deploy from Git repository

1. In Portainer, go to **Stacks → Add stack**
2. Select **Repository** as the build method
3. Set:
   - Repository URL: `https://github.com/Rapsodia/rpsd`
   - Reference: `refs/heads/main`
   - Compose path: `stacks/rpsd-stack.yml`
4. Add environment variables in the **Environment variables** section
   (same variables as in `stacks/.env.example`)
5. Click **Deploy the stack**

> **Secrets:** Docker Secrets must be created on the Swarm manager node via CLI before deploying,
> as Portainer does not create external secrets automatically.

### Redeploying after an image update

In Portainer, go to the stack → **Editor** → **Update the stack**.
If images are tagged with `latest`, enable **Re-pull image** to force a pull.

---

## Kubernetes — Local (minikube / Docker Desktop)

### Prerequisites

- `kubectl`
- [minikube](https://minikube.sigs.k8s.io/) **or** Docker Desktop with Kubernetes enabled

### 1. Start the cluster

**minikube:**
```bash
minikube start --memory=8192 --cpus=4
```

**Docker Desktop:** go to Settings → Kubernetes → Enable Kubernetes, then Apply & Restart.

### 2. (Optional) Customise secrets

The base manifests ship with dev-friendly default passwords. For local testing these are fine. To use custom passwords, edit `manifests/base/secrets.yaml` before deploying.

### 3. Deploy

Run from the repo root:

```bash
kubectl apply -k manifests/overlays/local/
```

### 4. Verify

```bash
# Watch pods start up (all 12 should reach Running)
kubectl get pods -n rpsd -w

# Verify persistent volumes are bound
kubectl get pvc -n rpsd
```

### 5. Access services

**Option A — port-forward:** creates a temporary tunnel from your local machine to the service,
using the same port numbers as the rpsd schema. The `&` runs each tunnel as a background job
in the same terminal — paste all lines at once and the prompt returns immediately. Tunnels
stop when you close the shell or run `pkill kubectl`.

```bash
kubectl port-forward -n rpsd svc/kafka-ui        19010:8080  &
kubectl port-forward -n rpsd svc/schema-registry 19020:8081  &
kubectl port-forward -n rpsd svc/rabbitmq        19110:15672 &
kubectl port-forward -n rpsd svc/prefect         19200:4200  &
kubectl port-forward -n rpsd svc/keycloak        19300:8080  &
kubectl port-forward -n rpsd svc/config-db       20140:5432  &
kubectl port-forward -n rpsd svc/rpsd-ingest     20000:8000  &
kubectl port-forward -n rpsd svc/rpsd-config     20100:8000  &
```

**Option B — NodePort:** the local overlay permanently exposes the UI/API services on host
ports, so they stay accessible in the browser across terminal sessions. Kubernetes requires
NodePort numbers to be in the 30000–32767 range (a cluster-wide hard constraint), so the
ports differ from the rpsd schema — the overlay uses 30xxx numbers that mirror the original
structure where possible (30010 ↔ 19010, 30200 ↔ 19200, etc.).

> NodePort only works on local clusters where the K8s node is `localhost` (minikube or
> Docker Desktop). On EKS, nodes are private EC2 instances, so NodePort is not reachable
> from outside without a load balancer — use port-forward there instead.

```bash
kubectl get svc -n rpsd          # lists all NodePort assignments
minikube service list            # minikube only — prints clickable URLs
```

### 6. Update a service

```bash
kubectl set image -n rpsd deployment/rpsd-ingest \
  rpsd-ingest=ghcr.io/agenzia-tpl/rpsd-ingest:sha-abc1234
```

### 7. Teardown

```bash
# Remove all resources (keeps PVCs and their data)
kubectl delete -k manifests/overlays/local/

# Also delete persistent data
kubectl delete pvc -n rpsd --all
```

---

## Kubernetes — AWS EKS

### Prerequisites

- `kubectl`
- AWS CLI configured (`aws configure`)
- [`eksctl`](https://eksctl.io/) (for cluster creation — optional, can use AWS Console instead)

### 1. Create an EKS cluster

```bash
eksctl create cluster \
  --name rpsd \
  --region eu-south-1 \
  --node-type t3.xlarge \
  --nodes 2
```

This takes ~15 minutes. `eksctl` automatically updates your kubeconfig.

### 2. Verify kubectl context

```bash
kubectl config current-context   # should show something like: <email>@rpsd.eu-south-1.eksctl.io
kubectl get nodes                # should list your worker nodes
```

### 3. Create secrets

The base manifests include weak development defaults. **Do not use them in production.** Create the secret with real passwords before deploying:

```bash
kubectl create namespace rpsd

kubectl create secret generic rpsd-secrets -n rpsd \
  --from-literal=rpsd-keycloak-db-pass='<strong-password>' \
  --from-literal=rpsd-keycloak-admin-pass='<strong-password>' \
  --from-literal=rpsd-config-db-pass='<strong-password>' \
  --from-literal=rpsd-prefect-db-pass='<strong-password>' \
  --from-literal=rpsd-rabbitmq-pass='<strong-password>'
```

Use `openssl rand -base64 24` to generate each password.

> **Production secret management:** for a more robust setup, use [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/) together with the [External Secrets Operator](https://external-secrets.io/) to inject secrets into the cluster automatically.

### 4. Pin image tags

Edit `manifests/overlays/eks/kustomization.yaml` and uncomment the `images:` block with the specific commit SHA tags to deploy:

```yaml
images:
  - name: ghcr.io/agenzia-tpl/rpsd-ingest
    newTag: sha-abc1234
  - name: ghcr.io/agenzia-tpl/rpsd-config
    newTag: sha-abc1234
  - name: ghcr.io/agenzia-tpl/rpsd-config-db
    newTag: sha-abc1234
```

### 5. Deploy

```bash
kubectl apply -k manifests/overlays/eks/
```

The EKS overlay applies `gp3` StorageClass to all PVCs and inherits all base resources. If you created the namespace and secret in step 3, `kubectl apply` will skip re-creating them.

### 6. Verify

```bash
kubectl get pods -n rpsd -w      # wait for all 12 Running
kubectl get pvc  -n rpsd         # all should be Bound (EBS volumes provisioned)
```

### 7. Access services

No Ingress is configured yet. Use port-forward to access services (all run as background jobs
in a single terminal — paste at once, stop with `pkill kubectl`):

```bash
kubectl port-forward -n rpsd svc/kafka-ui        19010:8080  &
kubectl port-forward -n rpsd svc/schema-registry  19020:8081  &
kubectl port-forward -n rpsd svc/rabbitmq         19110:15672 &
kubectl port-forward -n rpsd svc/prefect          19200:4200  &
kubectl port-forward -n rpsd svc/keycloak         19300:8080  &
kubectl port-forward -n rpsd svc/config-db        20140:5432  &
kubectl port-forward -n rpsd svc/rpsd-ingest      20000:8000  &
kubectl port-forward -n rpsd svc/rpsd-config      20100:8000  &
```

> **Keycloak hostname:** the base manifest sets `KC_HOSTNAME=http://localhost:19300`. This works
> for port-forward access. Once you have an Ingress or load balancer URL, patch `KC_HOSTNAME`
> in the EKS overlay.

### 8. Update a service

Update the tag in `manifests/overlays/eks/kustomization.yaml` and re-apply:

```bash
kubectl apply -k manifests/overlays/eks/
```

Kubernetes performs a rolling update with zero downtime.

### 9. Teardown

```bash
# Remove all K8s resources (EBS volumes are retained by default)
kubectl delete -k manifests/overlays/eks/

# Also delete persistent volumes (and their EBS backing)
kubectl delete pvc -n rpsd --all

# Delete the EKS cluster (terminates EC2 nodes)
eksctl delete cluster --name rpsd --region eu-south-1
```

---

## Keycloak Realm Import

The Keycloak realm JSON must be exported and committed before deploying to Swarm.

### Export realm from a running local instance

```bash
docker exec rpsd-keycloak /opt/keycloak/bin/kc.sh export \
  --realm rpsd \
  --dir /tmp/export \
  --users realm_file

docker cp rpsd-keycloak:/tmp/export/rpsd-realm.json \
  shared/keycloak/realm-import/rpsd-realm.json
```

Once committed, uncomment the `rpsd_keycloak_realm` config block in `stacks/rpsd-stack.yml`.

---

## Managed Mode (Private Registry)

To use a private registry instead of `ghcr.io`, override image variables:

```bash
# In stacks/.env or Portainer env vars:
RPSD_IMAGE_INGEST=registry.example.com/rpsd/rpsd-ingest:latest
RPSD_IMAGE_CONFIG=registry.example.com/rpsd/rpsd-config:latest
RPSD_IMAGE_CONFIG_DB=registry.example.com/rpsd/rpsd-config-db:latest
```

See `env/.env.compose.images.managed.example` for the full list of overridable image variables.
