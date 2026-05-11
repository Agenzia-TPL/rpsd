#!/bin/bash
# SPDX-FileCopyrightText: 2026 AGENZIA TPL BACINO CITTA' METROPOLITANA MILANO, MONZA E BRIANZA, LODI, PAVIA
# SPDX-License-Identifier: EUPL-1.2
set -e
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

echo -e "${GREEN}=== rpsd Platform Status ===${NC}"
echo ""

# -------------------------------------------------------------------------
# Running containers
# -------------------------------------------------------------------------

echo -e "${YELLOW}Running containers:${NC}"
CONTAINER_OUTPUT=$(docker ps --filter "name=rpsd-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true)
if [ -n "$CONTAINER_OUTPUT" ]; then
  echo "$CONTAINER_OUTPUT"
else
  echo "  (no rpsd containers running)"
fi

# -------------------------------------------------------------------------
# Managed repositories
# -------------------------------------------------------------------------

echo ""
echo -e "${YELLOW}Managed repositories:${NC}"

parse_repos_conf
for i in "${!REPO_NAMES[@]}"; do
  name="${REPO_NAMES[$i]}"
  type="${REPO_TYPES[$i]}"
  target="$PARENT_DIR/$name"
  if [ -d "$target" ]; then
    branch=$(git -C "$target" branch --show-current 2>/dev/null || echo "unknown")
    print_success "$name ($type) — branch: $branch"
  else
    print_warn "$name ($type) — NOT CLONED"
  fi
done

# -------------------------------------------------------------------------
# Environment files
# -------------------------------------------------------------------------

echo ""
echo -e "${YELLOW}Environment files:${NC}"
if [ -f "$RPSD_ROOT/.env" ]; then
  print_success "rpsd/.env exists"
else
  print_warn "rpsd/.env missing — run scripts/setup.sh"
fi

get_service_repos
for name in "${SERVICE_NAMES[@]}"; do
  repo_dir="$PARENT_DIR/$name"
  if [ -d "$repo_dir" ]; then
    if [ -f "$repo_dir/.env" ]; then
      print_success "$name/.env exists"
    elif [ -f "$repo_dir/.env.base" ]; then
      print_warn "$name/.env missing (found legacy .env.base) — run scripts/setup.sh"
    else
      print_warn "$name/.env missing — run scripts/setup.sh"
    fi
  fi
done
echo ""
