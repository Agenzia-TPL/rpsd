#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 AGENZIA TPL BACINO CITTA' METROPOLITANA MILANO, MONZA E BRIANZA, LODI, PAVIA
# SPDX-License-Identifier: EUPL-1.2

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RPSD_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${RPSD_DIR}/.." && pwd)"
RPSD_CONFIG_DIR="${ROOT_DIR}/rpsd-config"

KC_REALM="${RPSD_KEYCLOAK_REALM:-rpsd}"
KC_CMD="${RPSD_KEYCLOAK_CLI:-/opt/keycloak/bin/kcadm.sh}"
KC_SERVER="${RPSD_KEYCLOAK_SERVER:-http://localhost:8080}"
KC_MASTER_REALM="${RPSD_KEYCLOAK_MASTER_REALM:-master}"
KC_ADMIN_USER="${RPSD_KEYCLOAK_ADMIN_USER:-admin}"
KC_ADMIN_PASS="${RPSD_KEYCLOAK_ADMIN_PASS:-admin}"

BOOTSTRAP_KC_USERNAME="${RPSD_BOOTSTRAP_KC_USERNAME:-rpsd-admin}"
BOOTSTRAP_KC_PASSWORD="${RPSD_BOOTSTRAP_KC_PASSWORD:-rpsd-admin}"
BOOTSTRAP_KC_EMAIL="${RPSD_BOOTSTRAP_KC_EMAIL:-davide.nuccio@gmail.com}"
BOOTSTRAP_KC_GROUP_PATH="${RPSD_BOOTSTRAP_KC_GROUP_PATH:-/rpsd/admin}"
BOOTSTRAP_KC_ROLE="${RPSD_BOOTSTRAP_KC_ROLE:-rpsd-admin}"

DJANGO_SERVICE="${RPSD_CONFIG_SERVICE:-rpsd-config}"
DJANGO_PYTHON="${RPSD_CONFIG_PYTHON:-/app/.venv/bin/python}"
DJANGO_ADMIN_USERNAME="${RPSD_DJANGO_ADMIN_USERNAME:-rpsd-config-admin}"
DJANGO_ADMIN_PASSWORD="${RPSD_DJANGO_ADMIN_PASSWORD:-rpsd-config-admin}"
DJANGO_ADMIN_EMAIL="${RPSD_DJANGO_ADMIN_EMAIL:-rpsd-config-admin@rapsodia}"

log_step() {
  printf '\n[%s] %s\n' "$1" "$2"
}

log_info() {
  printf '[INFO] %s\n' "$1"
}

log_ok() {
  printf '[OK] %s\n' "$1"
}

log_warn() {
  printf '[WARN] %s\n' "$1"
}

log_error() {
  printf '[ERROR] %s\n' "$1" >&2
}

require_workspace() {
  if [[ ! -d "${RPSD_DIR}" ]]; then
    log_error "Repository rpsd non trovato in: ${RPSD_DIR}"
    exit 1
  fi
  if [[ ! -d "${RPSD_CONFIG_DIR}" ]]; then
    log_error "Repository rpsd-config non trovato in: ${RPSD_CONFIG_DIR}"
    log_error "Attesa struttura workspace: ROOT_DIR/rpsd e ROOT_DIR/rpsd-config come sibling."
    exit 1
  fi
}

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker non trovato nel PATH."
    exit 1
  fi
  if ! docker compose version >/dev/null 2>&1; then
    log_error "Docker Compose plugin non disponibile: 'docker compose' fallisce."
    exit 1
  fi
}

enter_rpsd_dir() {
  cd "${RPSD_DIR}"
}

container_running() {
  local name="$1"
  docker ps --filter "name=^${name}$" --filter "status=running" --format "{{.Names}}" \
    | grep -q "^${name}$"
}

keycloak_admin_login() {
  docker compose exec -T keycloak sh -lc \
    "${KC_CMD} config credentials --server ${KC_SERVER} --realm ${KC_MASTER_REALM} --user '${KC_ADMIN_USER}' --password '${KC_ADMIN_PASS}' >/dev/null"
}

wait_for_keycloak_realm() {
  local ready=false
  for _ in $(seq 1 30); do
    if docker compose exec -T keycloak sh -lc "${KC_CMD} get realms/${KC_REALM} >/dev/null 2>&1"; then
      ready=true
      break
    fi
    sleep 2
  done
  [[ "${ready}" == "true" ]]
}

bootstrap_keycloak_admin_user() {
  if ! container_running "rpsd-keycloak"; then
    log_warn "Keycloak non in esecuzione: salto bootstrap utente."
    return 0
  fi

  if ! keycloak_admin_login; then
    log_warn "Login admin Keycloak fallito: salto bootstrap utente."
    return 0
  fi

  if ! wait_for_keycloak_realm; then
    log_warn "Realm ${KC_REALM} non disponibile: salto bootstrap utente."
    return 0
  fi

  local user_json user_id
  user_json="$(docker compose exec -T keycloak sh -lc "${KC_CMD} get users -r ${KC_REALM} -q username='${BOOTSTRAP_KC_USERNAME}'" 2>/dev/null || true)"
  user_id="$(printf '%s\n' "${user_json}" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"

  if [[ -z "${user_id}" ]]; then
    log_info "Creo utente Keycloak '${BOOTSTRAP_KC_USERNAME}' nel realm '${KC_REALM}'..."
    docker compose exec -T keycloak sh -lc \
      "${KC_CMD} create users -r ${KC_REALM} -s username='${BOOTSTRAP_KC_USERNAME}' -s enabled=true -s email='${BOOTSTRAP_KC_EMAIL}' -s emailVerified=true >/dev/null"
    docker compose exec -T keycloak sh -lc \
      "${KC_CMD} set-password -r ${KC_REALM} --username '${BOOTSTRAP_KC_USERNAME}' --new-password '${BOOTSTRAP_KC_PASSWORD}' >/dev/null"
    user_json="$(docker compose exec -T keycloak sh -lc "${KC_CMD} get users -r ${KC_REALM} -q username='${BOOTSTRAP_KC_USERNAME}'" 2>/dev/null || true)"
    user_id="$(printf '%s\n' "${user_json}" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    log_ok "Utente '${BOOTSTRAP_KC_USERNAME}' creato."
  else
    log_info "Utente '${BOOTSTRAP_KC_USERNAME}' gia' presente: skip creazione."
  fi

  if [[ -z "${user_id}" ]]; then
    log_warn "Impossibile recuperare ID utente '${BOOTSTRAP_KC_USERNAME}'."
    return 0
  fi

  local groups_json group_id
  groups_json="$(docker compose exec -T keycloak sh -lc "${KC_CMD} get groups -r ${KC_REALM} -q search=admin" 2>/dev/null || true)"
  group_id="$(printf '%s\n' "${groups_json}" | awk '
    /"id"[[:space:]]*:/ { id=$0; gsub(/.*"id"[[:space:]]*:[[:space:]]*"|".*/, "", id); last_id=id }
    /"path"[[:space:]]*:[[:space:]]*"\/rpsd\/admin"/ { print last_id; exit }
  ')"

  if [[ -n "${group_id}" ]]; then
    local user_groups
    user_groups="$(docker compose exec -T keycloak sh -lc "${KC_CMD} get users/${user_id}/groups -r ${KC_REALM}" 2>/dev/null || true)"
    if printf '%s\n' "${user_groups}" | grep -q "\"path\"[[:space:]]*:[[:space:]]*\"${BOOTSTRAP_KC_GROUP_PATH}\""; then
      log_info "Utente '${BOOTSTRAP_KC_USERNAME}' gia' nel gruppo '${BOOTSTRAP_KC_GROUP_PATH}'."
    else
      docker compose exec -T keycloak sh -lc \
        "${KC_CMD} update users/${user_id}/groups/${group_id} -r ${KC_REALM} -n >/dev/null"
      log_ok "Utente '${BOOTSTRAP_KC_USERNAME}' aggiunto al gruppo '${BOOTSTRAP_KC_GROUP_PATH}'."
    fi
  else
    log_warn "Gruppo '${BOOTSTRAP_KC_GROUP_PATH}' non trovato: skip assegnazione gruppo."
  fi

  docker compose exec -T keycloak sh -lc \
    "${KC_CMD} add-roles -r ${KC_REALM} --uusername '${BOOTSTRAP_KC_USERNAME}' --rolename '${BOOTSTRAP_KC_ROLE}' >/dev/null 2>&1 || true"
}

update_env_var() {
  local env_file="$1"
  local key="$2"
  local value="$3"

  if [[ ! -f "${env_file}" ]]; then
    log_warn "File env non trovato: ${env_file}"
    return 1
  fi

  local tmp_file
  tmp_file="$(mktemp)"
  awk -v key="${key}" -v value="${value}" '
    BEGIN { replacement = key "=" value; updated = 0 }
    $0 ~ "^" key "=" {
      if (!updated) {
        print replacement
        updated = 1
      }
      next
    }
    { print }
    END {
      if (!updated) {
        print replacement
      }
    }
  ' "${env_file}" > "${tmp_file}"
  mv "${tmp_file}" "${env_file}"
}

sync_keycloak_client_secrets_to_env() {
  local env_file="${RPSD_CONFIG_DIR}/.env"

  if ! container_running "rpsd-keycloak"; then
    log_warn "Keycloak non in esecuzione: salto sync secret client."
    return 0
  fi

  if ! keycloak_admin_login; then
    log_warn "Login admin Keycloak fallito: salto sync secret client."
    return 0
  fi

  if ! docker compose exec -T keycloak sh -lc "${KC_CMD} get realms/${KC_REALM} >/dev/null 2>&1"; then
    log_warn "Realm ${KC_REALM} non disponibile: salto sync secret client."
    return 0
  fi

  sync_one_client_secret() {
    local client_id="$1"
    local env_key="$2"
    local client_json client_uuid secret_json secret

    client_json="$(docker compose exec -T keycloak sh -lc "${KC_CMD} get clients -r ${KC_REALM} -q clientId='${client_id}'" 2>/dev/null || true)"
    client_uuid="$(printf '%s\n' "${client_json}" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    if [[ -z "${client_uuid}" ]]; then
      log_warn "Client Keycloak '${client_id}' non trovato: ${env_key} non aggiornato."
      return 0
    fi

    docker compose exec -T keycloak sh -lc \
      "${KC_CMD} create clients/${client_uuid}/client-secret -r ${KC_REALM} >/dev/null"
    secret_json="$(docker compose exec -T keycloak sh -lc "${KC_CMD} get clients/${client_uuid}/client-secret -r ${KC_REALM}" 2>/dev/null || true)"
    secret="$(printf '%s\n' "${secret_json}" | sed -n 's/.*"value"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    if [[ -z "${secret}" || "${secret}" == "**********" ]]; then
      log_warn "Secret Keycloak non valido per '${client_id}': ${env_key} non aggiornato."
      return 0
    fi

    update_env_var "${env_file}" "${env_key}" "${secret}"
    log_ok "Secret client '${client_id}' sincronizzato in rpsd-config/.env (${env_key})."
  }

  sync_one_client_secret "rpsd-config" "OIDC_CLIENT_SECRET"
  sync_one_client_secret "rpsd-config-admin-api" "KEYCLOAK_ADMIN_CLIENT_SECRET"
}

bootstrap_django_superuser() {
  if ! container_running "rpsd-config"; then
    log_warn "Container rpsd-config non in esecuzione: salto bootstrap Django."
    return 0
  fi

  if ! docker compose exec -T "${DJANGO_SERVICE}" sh -c "test -x ${DJANGO_PYTHON}"; then
    log_warn "Python virtualenv non trovato (${DJANGO_PYTHON}): salto bootstrap Django."
    return 0
  fi

  log_info "Applico migrazioni Django su rpsd-config..."
  if ! docker compose exec -T "${DJANGO_SERVICE}" sh -c \
    "${DJANGO_PYTHON} src/rpsd_config/manage.py migrate --noinput >/dev/null"; then
    log_warn "Migrazioni Django fallite: salto bootstrap superuser."
    return 0
  fi
  log_ok "Migrazioni Django applicate."

  log_info "Verifico superuser Django '${DJANGO_ADMIN_USERNAME}'..."
  if docker compose exec -T "${DJANGO_SERVICE}" sh -c \
    "${DJANGO_PYTHON} src/rpsd_config/manage.py shell" <<PY >/dev/null; then
from django.contrib.auth import get_user_model

User = get_user_model()
username = "${DJANGO_ADMIN_USERNAME}"
email = "${DJANGO_ADMIN_EMAIL}"
password = "${DJANGO_ADMIN_PASSWORD}"

user, created = User.objects.get_or_create(
    username=username,
    defaults={"email": email, "is_staff": True, "is_superuser": True},
)

changed = False
if user.email != email:
    user.email = email
    changed = True
if not user.is_staff:
    user.is_staff = True
    changed = True
if not user.is_superuser:
    user.is_superuser = True
    changed = True
if not user.check_password(password):
    user.set_password(password)
    changed = True

if created or changed:
    user.save()
PY
    log_ok "Superuser Django pronto."
  else
    log_warn "Impossibile creare/aggiornare il superuser Django."
  fi
}

ensure_config_db_running() {
  if container_running "rpsd-config-db"; then
    log_info "config-db gia' in esecuzione."
    return 0
  fi

  log_info "Avvio dipendenza config-db..."
  docker compose up -d config-db >/dev/null

  local db_status=""
  for _ in $(seq 1 30); do
    db_status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' rpsd-config-db 2>/dev/null || true)"
    if [[ "${db_status}" == "healthy" || "${db_status}" == "running" ]]; then
      log_ok "config-db disponibile (${db_status})."
      return 0
    fi
    sleep 2
  done

  log_warn "config-db non risulta pronto (${db_status:-unknown})."
  return 0
}

print_bootstrap_summary() {
  cat <<EOF

Riepilogo operativo:
  Keycloak:    http://localhost:19300
  rpsd-config: http://localhost:20100
  rpsd-ingest: http://localhost:20000

Utente bootstrap Keycloak:
  username: ${BOOTSTRAP_KC_USERNAME}
  password: ${BOOTSTRAP_KC_PASSWORD}
  email:    ${BOOTSTRAP_KC_EMAIL}

Superuser Django bootstrap:
  username: ${DJANGO_ADMIN_USERNAME}
  password: ${DJANGO_ADMIN_PASSWORD}
  email:    ${DJANGO_ADMIN_EMAIL}
EOF
}
