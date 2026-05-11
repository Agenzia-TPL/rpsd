#!/bin/bash
# SPDX-FileCopyrightText: 2026 AGENZIA TPL BACINO CITTA' METROPOLITANA MILANO, MONZA E BRIANZA, LODI, PAVIA
# SPDX-License-Identifier: EUPL-1.2
set -e
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

require_docker

echo -e "${GREEN}=== Starting rpsd Application Services ===${NC}"
echo ""

# -------------------------------------------------------------------------
# Parse arguments
# -------------------------------------------------------------------------

EXCEPT=()
BUILD_FLAG=""

usage() {
  echo "Usage: $0 [--except service1,service2] [--build]"
  echo ""
  echo "Start application services defined in repos.conf."
  echo ""
  echo "Options:"
  echo "  --except <services>  Comma-separated list of services to exclude"
  echo "                       (use profile name: 'ingest' or full name: 'rpsd-ingest')"
  echo "  --build              Force rebuild of Docker images"
  echo "  --help               Show this help message"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --except)
      shift
      IFS=',' read -ra PARTS <<< "$1"
      EXCEPT+=("${PARTS[@]}")
      shift
      ;;
    --build)
      BUILD_FLAG="--build"
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      print_error "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

# -------------------------------------------------------------------------
# Build profile list
# -------------------------------------------------------------------------

get_service_repos

PROFILES=()
for name in "${SERVICE_NAMES[@]}"; do
  # Extract profile name: rpsd-ingest → ingest
  profile="${name#rpsd-}"
  skip=false
  for exc in "${EXCEPT[@]}"; do
    exc_clean="${exc#rpsd-}"  # Allow both "rpsd-ingest" and "ingest"
    if [ "$profile" == "$exc_clean" ]; then
      skip=true
      break
    fi
  done
  if [ "$skip" = false ]; then
    PROFILES+=("$profile")
  else
    print_warn "Excluding: $name"
  fi
done

if [ ${#PROFILES[@]} -eq 0 ]; then
  print_warn "No services to start (all excluded)"
  exit 0
fi

# -------------------------------------------------------------------------
# Build services (smart rebuild or forced)
# -------------------------------------------------------------------------

PROFILE_FLAGS=""
for p in "${PROFILES[@]}"; do
  PROFILE_FLAGS="$PROFILE_FLAGS --profile $p"
done

print_info "Starting profiles: ${PROFILES[*]}"

cd "$RPSD_ROOT"

# Build a lookup from profile name to index in SERVICE_NAMES/SERVICE_DEPS
build_service() {
  local service="$1"
  local deps="$2"
  local label
  label=$(compute_build_sources_label "$service" "$deps") || label="unknown"
  print_info "Building $service ..."
  docker compose $PROFILE_FLAGS build --build-arg "RPSD_BUILD_SOURCES=$label" "$service"
}

for p in "${PROFILES[@]}"; do
  service="rpsd-$p"

  # Find matching index in SERVICE_NAMES to get deps
  deps=""
  for i in "${!SERVICE_NAMES[@]}"; do
    if [[ "${SERVICE_NAMES[$i]}" == "$service" ]]; then
      deps="${SERVICE_DEPS[$i]}"
      break
    fi
  done

  if [[ -n "$BUILD_FLAG" ]]; then
    # --build: force rebuild all active services
    build_service "$service" "$deps"
  else
    # Smart rebuild: check if image is stale
    image=$(resolve_service_image "$p")
    reason=$(check_service_needs_build "$service" "$deps" "$image") && {
      print_warn "$service needs rebuild ($reason)"
      build_service "$service" "$deps"
    } || {
      print_success "$service image is up-to-date"
    }
  fi
done

# -------------------------------------------------------------------------
# Start services
# -------------------------------------------------------------------------

docker compose $PROFILE_FLAGS up -d

echo ""
docker compose $PROFILE_FLAGS ps
echo ""
print_success "Services started"
