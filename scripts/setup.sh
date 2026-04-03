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
  echo "Generates .env files in sibling service repositories."
  echo ""
  echo "Each service repo provides its own .env.development with standalone defaults."
  echo "This script copies it to .env and applies scenario-specific coordination"
  echo "overrides (hostnames, ports) from env/scenarios/<scenario>/."
  echo ""
  echo "Options:"
  echo "  --scenario <name>    Which coordination overrides to apply (default: local-all-in-one)"
  echo "                         local-all-in-one   all services run in Docker via rpsd"
  echo "                         local-devcontainer service runs in devcontainer, shared via rpsd"
  echo "  --service <name>     Only set up this service (e.g. rpsd-config or config)"
  echo "  --force              Overwrite existing .env in the service repo"
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
# Step 2: Generate .env in sibling service repos
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
  echo -e "${YELLOW}NOTE: The devcontainer overrides assume rpsd manages all shared services."
  echo -e "      They will not work if the service repo spins up its own infrastructure${NC}"
  echo -e "${YELLOW}      (e.g. its own docker-compose for postgres, kafka, etc.).${NC}"
  echo ""
fi

for name in "${SERVICE_NAMES[@]}"; do
  repo_dir="$PARENT_DIR/$name"
  dev_env="$repo_dir/.env.development"
  override="$RPSD_ROOT/env/scenarios/$SCENARIO/$name.env"
  target="$repo_dir/.env"

  # Check service repo exists
  if [ ! -d "$repo_dir" ]; then
    print_warn "$name: repo not found at $repo_dir — run clone-repos.sh first"
    continue
  fi

  # Check .env.development exists in service repo
  if [ ! -f "$dev_env" ]; then
    print_warn "$name: no .env.development found — pull latest or create it"
    continue
  fi

  # Handle existing .env
  if [ -f "$target" ]; then
    if [ "$FORCE" = true ]; then
      print_info "$name: overwriting .env with $SCENARIO configuration"
    else
      # Generate what the .env would be, diff against existing
      tmpfile=$(mktemp)
      cp "$dev_env" "$tmpfile"
      if [ -f "$override" ]; then
        merge_env_overrides "$tmpfile" "$override"
      fi

      if diff -q "$target" "$tmpfile" > /dev/null 2>&1; then
        print_success "$name: .env already up to date"
      else
        print_warn "$name: .env already exists and differs from what setup would generate"
        echo "       Run with --force to overwrite, or diff manually:"
        echo "         diff $target <(scripts/setup.sh --service $name --force --dry-run)"
        diff --color=auto "$target" "$tmpfile" 2>/dev/null || true
      fi
      rm -f "$tmpfile"
      continue
    fi
  fi

  # Generate .env: copy .env.development, then apply scenario overrides
  cp "$dev_env" "$target"
  if [ -f "$override" ]; then
    merge_env_overrides "$target" "$override"
    print_success "$name: .env created ($SCENARIO overrides applied)"
  else
    print_success "$name: .env created (no scenario overrides for $SCENARIO)"
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
  echo "  1. Review .env in the service repo — adjust if needed"
  echo "  2. scripts/start-shared.sh                        (start shared infrastructure)"
  echo "  3. scripts/start-services.sh --except <service>   (start OTHER services in Docker)"
  echo "  4. Open the service in its devcontainer and start it there"
else
  echo "  1. Review and adjust service .env files if needed"
  echo "  2. scripts/start-shared.sh    (start shared infrastructure)"
  echo "  3. scripts/start-services.sh  (start application services)"
fi
