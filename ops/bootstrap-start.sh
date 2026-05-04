#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 AGENZIA TPL BACINO CITTA' METROPOLITANA MILANO, MONZA E BRIANZA, LODI, PAVIA
# SPDX-License-Identifier: EUPL-1.2
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ops/_common.sh
source "${SCRIPT_DIR}/_common.sh"

ONLY_CONFIG=false

usage() {
  cat <<'EOF'
Uso: bash ops/bootstrap-start.sh [--only-config]

Avvia la piattaforma locale RPSD e applica il bootstrap operativo.

Opzioni:
  --only-config   Avvia/ricrea solo rpsd-config e la dipendenza config-db
  --help, -h      Mostra questo help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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
  echo "=== Bootstrap start rpsd-config ==="

  log_step "1/5" "Verifica dipendenze rpsd-config"
  ensure_config_db_running

  log_step "2/5" "Sync secret client Keycloak"
  sync_keycloak_client_secrets_to_env

  log_step "3/5" "Ricreo servizio rpsd-config"
  docker compose --profile config up -d --no-deps --force-recreate rpsd-config

  log_step "4/5" "Bootstrap DB e superuser Django"
  bootstrap_django_superuser

  log_step "5/5" "Stato servizio rpsd-config"
  docker compose ps rpsd-config

  echo ""
  echo "Bootstrap rpsd-config completato."
  print_bootstrap_summary
  exit 0
fi

echo "=== Bootstrap start piattaforma RPSD ==="

log_step "1/7" "Setup environment files"
bash scripts/setup.sh

log_step "2/7" "Avvio servizi condivisi"
bash scripts/start-shared.sh

log_step "3/7" "Bootstrap utente admin Keycloak"
bootstrap_keycloak_admin_user

log_step "4/7" "Sync secret client Keycloak"
sync_keycloak_client_secrets_to_env

log_step "5/7" "Avvio servizi applicativi"
bash scripts/start-services.sh

log_step "6/7" "Bootstrap DB e superuser Django"
bootstrap_django_superuser

log_step "7/7" "Stato piattaforma"
bash scripts/status.sh

echo ""
echo "Bootstrap start completato."
print_bootstrap_summary
