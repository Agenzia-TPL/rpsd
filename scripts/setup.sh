#!/bin/bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

echo -e "${GREEN}=== rpsd Platform Setup ===${NC}"
echo ""

# Parse flags
SCENARIO="local-all-in-one"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)
      SCENARIO="$2"
      shift 2
      ;;
    *)
      print_error "Unknown argument: $1"
      echo "Usage: $0 [--scenario <name>]"
      echo "  --scenario local-all-in-one    (default) all services run in Docker via rpsd"
      echo "  --scenario local-devcontainer  service runs in devcontainer, shared services via rpsd"
      exit 1
      ;;
  esac
done

print_info "Scenario: $SCENARIO"
echo ""

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

for name in "${SERVICE_NAMES[@]}"; do
  repo_dir="$PARENT_DIR/$name"
  example_dir="$RPSD_ROOT/env/$name"

  if [ ! -d "$repo_dir" ]; then
    print_warn "$name not found at $repo_dir — run clone-repos.sh first"
    continue
  fi

  # Copy the scenario example as .env.base in the service repo
  local_example="$example_dir/.env.${SCENARIO}.example"
  if [ -f "$local_example" ] && [ ! -f "$repo_dir/.env.base" ]; then
    cp "$local_example" "$repo_dir/.env.base"
    print_success "Created $name/.env.base from $SCENARIO example"
  elif [ -f "$repo_dir/.env.base" ]; then
    print_warn "$name/.env.base already exists — skipping"
  elif [ ! -f "$local_example" ]; then
    print_warn "No $SCENARIO env example found for $name — skipping"
  fi

  # Create empty .env in service repo if not present
  if [ ! -f "$repo_dir/.env" ]; then
    touch "$repo_dir/.env"
    print_success "Created empty $name/.env"
  fi
done

echo ""
print_success "Setup complete."
print_info "Next steps:"
echo "  1. Review and adjust service .env.base files if needed"
echo "  2. Run: scripts/start-shared.sh    (start shared infrastructure)"
echo "  3. Run: scripts/start-services.sh  (start application services)"
