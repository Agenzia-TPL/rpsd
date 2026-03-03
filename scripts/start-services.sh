#!/bin/bash
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
# Start services
# -------------------------------------------------------------------------

PROFILE_FLAGS=""
for p in "${PROFILES[@]}"; do
  PROFILE_FLAGS="$PROFILE_FLAGS --profile $p"
done

print_info "Starting profiles: ${PROFILES[*]}"

cd "$RPSD_ROOT"
docker compose $PROFILE_FLAGS up -d $BUILD_FLAG

echo ""
docker compose $PROFILE_FLAGS ps
echo ""
print_success "Services started"
