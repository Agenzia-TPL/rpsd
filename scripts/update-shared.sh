#!/bin/bash
# SPDX-FileCopyrightText: 2026 AGENZIA TPL BACINO CITTA' METROPOLITANA MILANO, MONZA E BRIANZA, LODI, PAVIA
# SPDX-License-Identifier: EUPL-1.2
set -e
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

require_docker

echo -e "${GREEN}=== Updating Shared Services ===${NC}"
echo ""

# Parse args: positional → profiles; --service <name> (repeatable) → target services.
PROFILES=()
SERVICES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --service)
      shift
      if [ -z "$1" ]; then
        print_error "--service requires a value"
        exit 1
      fi
      SERVICES+=("$1")
      ;;
    --service=*)
      SERVICES+=("${1#--service=}")
      ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [profile ...] [--service <name>]...

Pull newer images for the shared stack and recreate any container whose
image or config changed. Profiles default to "shared".

Examples:
  $(basename "$0")                          # update everything in "shared"
  $(basename "$0") kafka prefect            # only those profiles
  $(basename "$0") --service rpsd-keycloak  # target one compose service
EOF
      exit 0
      ;;
    *)
      PROFILES+=("$1")
      ;;
  esac
  shift
done

if [ ${#PROFILES[@]} -eq 0 ]; then
  PROFILES=("shared")
fi

PROFILE_FLAGS=""
for p in "${PROFILES[@]}"; do
  PROFILE_FLAGS="$PROFILE_FLAGS --profile $p"
done

print_info "Profiles: ${PROFILES[*]}"
if [ ${#SERVICES[@]} -gt 0 ]; then
  print_info "Services: ${SERVICES[*]}"
fi

cd "$RPSD_ROOT"

print_info "Pulling images..."
docker compose $PROFILE_FLAGS pull "${SERVICES[@]}"

print_info "Recreating containers with new images..."
docker compose $PROFILE_FLAGS up -d "${SERVICES[@]}"

echo ""

# -------------------------------------------------------------------------
# Wait for health checks (same containers as start-shared.sh)
# -------------------------------------------------------------------------

SHARED_CONTAINERS=(
  rpsd-kafka
  rpsd-rabbitmq
  rpsd-prefect
  rpsd-keycloak
  rpsd-config-db
)

print_info "Waiting for services to become healthy..."
for container in "${SHARED_CONTAINERS[@]}"; do
  if docker ps --filter "name=^${container}$" --filter "status=running" --format "{{.Names}}" | grep -q "^${container}$"; then
    local_timeout=90
    if [ "$container" = "rpsd-keycloak" ]; then
      local_timeout=200
    fi
    if wait_healthy "$container" "$local_timeout"; then
      print_success "$container is healthy"
    else
      print_warn "$container did not become healthy within timeout"
    fi
  fi
done

echo ""
echo -e "${GREEN}=== Shared Services Status ===${NC}"
docker compose $PROFILE_FLAGS ps
echo ""
print_info "Bootstrap hooks (Keycloak realm config, Kafka topics) were NOT re-run."
print_info "If you need them, use ./scripts/start-shared.sh instead."
