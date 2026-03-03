#!/bin/bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

echo -e "${GREEN}=== rpsd Platform Setup ===${NC}"
echo ""

# -------------------------------------------------------------------------
# Parse flags
# -------------------------------------------------------------------------

SCENARIO="local-all-in-one"
SERVICE=""
FORCE=false

usage() {
  echo "Usage: $0 [--scenario <name>] [--service <name>] [--force]"
  echo ""
  echo "Copies env example files from rpsd into sibling service repositories."
  echo ""
  echo "Options:"
  echo "  --scenario <name>    Which env template to use (default: local-all-in-one)"
  echo "                         local-all-in-one   all services run in Docker via rpsd"
  echo "                         local-devcontainer service runs in devcontainer, shared via rpsd"
  echo "  --service <name>     Only set up this service (e.g. rpsd-config or config)"
  echo "  --force              Overwrite existing .env.base in the service repo"
  echo "  --help               Show this help"
  echo ""
  echo "Typical workflows:"
  echo ""
  echo "  All services run in Docker via rpsd:"
  echo "    $0                                             # first-time setup"
  echo "    scripts/start-shared.sh                        # start shared infra"
  echo "    scripts/start-services.sh                      # start all app services"
  echo ""
  echo "  Developing rpsd-config in its own devcontainer:"
  echo "    $0                                             # set up all services (all-in-one)"
  echo "    $0 --service rpsd-config \\"
  echo "         --scenario local-devcontainer --force     # override only rpsd-config's env"
  echo "    scripts/start-shared.sh                        # start shared infra"
  echo "    scripts/start-services.sh --except rpsd-config # start OTHER services in Docker"
  echo "    # → open rpsd-config in its devcontainer and start it there"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)
      SCENARIO="$2"
      shift 2
      ;;
    --service)
      SERVICE="$2"
      shift 2
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      print_error "Unknown argument: $1"
      echo ""
      usage
      exit 1
      ;;
  esac
done

# -------------------------------------------------------------------------
# Step 1: Create rpsd root .env from open-mode image defaults
# -------------------------------------------------------------------------

if [ ! -f "$RPSD_ROOT/.env" ]; then
  print_info "Creating .env from open-mode image defaults..."
  cp "$RPSD_ROOT/env/.env.compose.images.open.example" "$RPSD_ROOT/.env"
  print_success "Created $RPSD_ROOT/.env"
else
  print_warn ".env already exists — skipping"
fi

# -------------------------------------------------------------------------
# Step 2: Copy env examples to sibling service repos
# -------------------------------------------------------------------------

get_service_repos

echo ""

# Filter to a single service if --service was given
if [ -n "$SERVICE" ]; then
  # Accept both "rpsd-config" and "config"
  SERVICE_NORMALIZED="${SERVICE#rpsd-}"
  MATCHED_NAMES=()
  for name in "${SERVICE_NAMES[@]}"; do
    if [ "$name" = "$SERVICE" ] || [ "${name#rpsd-}" = "$SERVICE_NORMALIZED" ]; then
      MATCHED_NAMES+=("$name")
    fi
  done
  if [ ${#MATCHED_NAMES[@]} -eq 0 ]; then
    print_error "Service '$SERVICE' not found in repos.conf"
    exit 1
  fi
  SERVICE_NAMES=("${MATCHED_NAMES[@]}")
fi

# Warn about the compatibility assumption when using devcontainer scenario
if [ "$SCENARIO" = "local-devcontainer" ]; then
  echo -e "${YELLOW}NOTE: The devcontainer env files assume rpsd manages all shared services."
  echo -e "      They will not work if the service repo spins up its own infrastructure${NC}"
  echo -e "${YELLOW}      (e.g. its own docker-compose for postgres, kafka, etc.).${NC}"
  echo ""
fi

for name in "${SERVICE_NAMES[@]}"; do
  repo_dir="$PARENT_DIR/$name"
  example_dir="$RPSD_ROOT/env/$name"
  local_example="$example_dir/.env.${SCENARIO}.example"
  target="$repo_dir/.env.base"

  if [ ! -d "$repo_dir" ]; then
    print_warn "$name: repo not found at $repo_dir — run clone-repos.sh first"
    continue
  fi

  if [ ! -f "$local_example" ]; then
    print_warn "$name: no $SCENARIO template found at $local_example — skipping"
    continue
  fi

  if [ -f "$target" ]; then
    if [ "$FORCE" = true ]; then
      print_info "$name: overwriting $target with $SCENARIO template"
      cp "$local_example" "$target"
      print_success "$name: .env.base updated"
    else
      print_warn "$name: .env.base already exists — skipping (use --force to overwrite)"
    fi
  else
    print_info "$name: copying $SCENARIO template → $target"
    cp "$local_example" "$target"
    print_success "$name: .env.base created"
  fi

  # Create empty .env in service repo if not present
  if [ ! -f "$repo_dir/.env" ]; then
    touch "$repo_dir/.env"
    print_success "$name: created empty .env"
  fi
done

echo ""
print_success "Setup complete."
echo ""
print_info "Next steps:"
if [ "$SCENARIO" = "local-devcontainer" ]; then
  echo "  If this is your first setup, also run without --service to set up other services:"
  echo "    scripts/setup.sh                        (sets all-in-one env for remaining services)"
  echo ""
  echo "  Then:"
  echo "  1. Review .env.base in the service repo — adjust CSRF/allowed-hosts to match"
  echo "     your devcontainer's forwarded port if needed"
  echo "  2. scripts/start-shared.sh                        (start shared infrastructure)"
  echo "  3. scripts/start-services.sh --except <service>   (start OTHER services in Docker)"
  echo "  4. Open the service in its devcontainer and start it there"
else
  echo "  1. Review and adjust service .env.base files if needed"
  echo "  2. scripts/start-shared.sh    (start shared infrastructure)"
  echo "  3. scripts/start-services.sh  (start application services)"
fi
