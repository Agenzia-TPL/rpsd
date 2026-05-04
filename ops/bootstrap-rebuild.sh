#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 AGENZIA TPL BACINO CITTA' METROPOLITANA MILANO, MONZA E BRIANZA, LODI, PAVIA
# SPDX-License-Identifier: EUPL-1.2
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ops/_common.sh
source "${SCRIPT_DIR}/_common.sh"

SETUP_FORCE=false
ONLY_CONFIG=false

usage() {
  cat <<'EOF'
Uso: bash ops/bootstrap-rebuild.sh [--setup-force] [--only-config]

Ricostruisce e ricrea i servizi applicativi senza fermare i servizi condivisi.

Opzioni:
  --setup-force   Esegue prima scripts/setup.sh --force
  --only-config   Rebuild/recreate solo rpsd-config
  --help, -h      Mostra questo help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --setup-force)
      SETUP_FORCE=true
      shift
      ;;
    --only-config)
      ONLY_CONFIG=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      log_error "Argomento non riconosciuto: $1"
      usage >&2
      exit 1
      ;;
  esac
done

require_workspace
require_docker
enter_rpsd_dir

if [[ "${ONLY_CONFIG}" == "true" ]]; then
  echo "=== Bootstrap rebuild rpsd-config ==="
else
  echo "=== Bootstrap rebuild servizi applicativi RPSD ==="
fi
echo "I servizi condivisi non vengono fermati."

if [[ "${SETUP_FORCE}" == "true" ]]; then
  log_step "0/4" "Rigenero file .env con scripts/setup.sh --force"
  bash scripts/setup.sh --force
fi

log_step "1/4" "Verifica shared services principali"
for svc in rpsd-config-db rpsd-keycloak; do
  if container_running "${svc}"; then
    log_ok "${svc} in esecuzione"
  else
    log_warn "${svc} non risulta in esecuzione"
  fi
done

if [[ "${ONLY_CONFIG}" == "true" ]]; then
  log_step "2/4" "Rebuild + recreate solo rpsd-config"
  docker compose --profile config up -d --build --force-recreate --no-deps rpsd-config
else
  log_step "2/4" "Rebuild + recreate rpsd-config e rpsd-ingest"
  docker compose --profile services up -d --build --force-recreate rpsd-config rpsd-ingest
fi

if [[ "${ONLY_CONFIG}" == "true" ]]; then
  log_step "3/4" "Stato servizio rpsd-config"
  docker compose --profile config ps rpsd-config
else
  log_step "3/4" "Stato servizi applicativi"
  docker compose --profile services ps
fi

log_step "4/4" "Log recenti rpsd-config (tail 40)"
docker logs --tail 40 rpsd-config || true

echo ""
if [[ "${ONLY_CONFIG}" == "true" ]]; then
  echo "Bootstrap rebuild rpsd-config completato."
else
  echo "Bootstrap rebuild completato."
fi
