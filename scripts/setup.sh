#!/bin/bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

echo -e "${GREEN}=== rpsd Platform Setup ===${NC}"
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

  # Copy .env.local-all-in-one.example as .env.base in the service repo
  local_example="$example_dir/.env.local-all-in-one.example"
  if [ -f "$local_example" ] && [ ! -f "$repo_dir/.env.base" ]; then
    cp "$local_example" "$repo_dir/.env.base"
    print_success "Created $name/.env.base from all-in-one example"
  elif [ -f "$repo_dir/.env.base" ]; then
    print_warn "$name/.env.base already exists — skipping"
  elif [ ! -f "$local_example" ]; then
    print_warn "No env example found for $name — skipping"
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
