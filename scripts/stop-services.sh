#!/bin/bash
# SPDX-FileCopyrightText: 2026 AGENZIA TPL BACINO CITTA' METROPOLITANA MILANO, MONZA E BRIANZA, LODI, PAVIA
# SPDX-License-Identifier: EUPL-1.2
set -e
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

echo -e "${YELLOW}=== Stopping rpsd Application Services ===${NC}"
echo ""

cd "$RPSD_ROOT"
docker compose --profile services down

print_success "Application services stopped"
