#!/bin/bash
# SPDX-FileCopyrightText: 2026 AGENZIA TPL BACINO CITTA' METROPOLITANA MILANO, MONZA E BRIANZA, LODI, PAVIA
# SPDX-License-Identifier: EUPL-1.2
set -e
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

echo -e "${YELLOW}=== Stopping Shared Services ===${NC}"
echo ""

# Parse arguments, extracting --clean flag
CLEAN_FLAG=""
FILTERED_PROFILES=()

for arg in "$@"; do
  if [ "$arg" == "--clean" ]; then
    CLEAN_FLAG="-v"
  else
    FILTERED_PROFILES+=("$arg")
  fi
done

if [ ${#FILTERED_PROFILES[@]} -eq 0 ]; then
  FILTERED_PROFILES=("shared")
fi

PROFILE_FLAGS=""
for p in "${FILTERED_PROFILES[@]}"; do
  PROFILE_FLAGS="$PROFILE_FLAGS --profile $p"
done

if [ -n "$CLEAN_FLAG" ]; then
  print_warn "Clean mode: volumes will be removed (data will be lost)"
fi

cd "$RPSD_ROOT"
docker compose $PROFILE_FLAGS down $CLEAN_FLAG

if [ -n "$CLEAN_FLAG" ]; then
  print_success "Shared services stopped and data volumes removed"
else
  print_success "Shared services stopped (data preserved)"
  print_info "To also remove data volumes: $0 --clean"
fi
