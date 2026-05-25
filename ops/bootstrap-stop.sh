#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 AGENZIA TPL BACINO CITTA' METROPOLITANA MILANO, MONZA E BRIANZA, LODI, PAVIA
# SPDX-License-Identifier: EUPL-1.2
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ops/_common.sh
source "${SCRIPT_DIR}/_common.sh"

ERASE=false

usage() {
  cat <<'EOF'
Uso: bash ops/bootstrap-stop.sh [erase|--erase|-e]

Ferma la piattaforma locale RPSD preservando i dati per default.

Opzioni:
  erase, --erase, -e   Rimuove anche container, volumi, network e immagini RPSD locali
  --help, -h           Mostra questo help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    erase|--erase|-e)
      ERASE=true
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

echo "=== Bootstrap stop piattaforma RPSD ==="
print_bootstrap_scope

log_step "1/3" "Stop servizi applicativi"
bash scripts/stop-services.sh || true

log_step "2/3" "Stop servizi condivisi"
bash scripts/stop-shared.sh || true

if [[ "${ERASE}" == "true" ]]; then
  log_step "3/3" "Cleanup completo artefatti Docker RPSD"
  log_warn "Erase esplicito richiesto: rimuovo container, volumi, network e immagini locali RPSD."

  docker compose --profile all down -v --remove-orphans || true

  rpsd_container_ids="$(
    docker ps -aq --format '{{.ID}} {{.Names}}' \
      | awk '$2 ~ /^rpsd-/ {print $1}'
  )"
  if [[ -n "${rpsd_container_ids}" ]]; then
    docker rm -f ${rpsd_container_ids} >/dev/null 2>&1 || true
  fi

  rpsd_volumes="$(
    docker volume ls --format '{{.Name}}' \
      | awk '$1 ~ /^rpsd-/ {print $1}'
  )"
  if [[ -n "${rpsd_volumes}" ]]; then
    docker volume rm ${rpsd_volumes} >/dev/null 2>&1 || true
  fi

  docker network rm rpsd-network >/dev/null 2>&1 || true
  docker image rm -f rpsd-config:local rpsd-ingest:local rpsd-config-db:local >/dev/null 2>&1 || true

  echo ""
  echo "Stop + erase completato."
  echo "I file del repository non sono stati cancellati."
else
  log_step "3/3" "Nessun erase richiesto"
  echo ""
  echo "Stop completato: dati Docker preservati."
  echo "Per cleanup completo: bash ops/bootstrap-stop.sh erase"
fi
