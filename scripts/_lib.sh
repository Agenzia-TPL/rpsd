#!/bin/bash
# SPDX-FileCopyrightText: 2026 AGENZIA TPL BACINO CITTA' METROPOLITANA MILANO, MONZA E BRIANZA, LODI, PAVIA
# SPDX-License-Identifier: EUPL-1.2
# _lib.sh — Shared functions for rpsd scripts
# Source this file, do not execute it directly.

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Resolve the rpsd repo root (parent of scripts/)
RPSD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARENT_DIR="$(dirname "$RPSD_ROOT")"
REPOS_CONF="$RPSD_ROOT/repos.conf"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ---------------------------------------------------------------------------
# repos.conf parsing
# ---------------------------------------------------------------------------

# Parse repos.conf into parallel arrays.
# After calling: REPO_NAMES[@], REPO_TYPES[@]
parse_repos_conf() {
  REPO_NAMES=()
  REPO_TYPES=()
  REPO_DEPS=()
  while IFS= read -r line; do
    # Skip comments and blank lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue
    read -r name type deps <<< "$line"
    REPO_NAMES+=("$name")
    REPO_TYPES+=("$type")
    REPO_DEPS+=("$deps")
  done < "$REPOS_CONF"
}

# Get only service-type repo names into SERVICE_NAMES[@] and SERVICE_DEPS[@].
get_service_repos() {
  parse_repos_conf
  SERVICE_NAMES=()
  SERVICE_DEPS=()
  for i in "${!REPO_NAMES[@]}"; do
    if [[ "${REPO_TYPES[$i]}" == "service" ]]; then
      SERVICE_NAMES+=("${REPO_NAMES[$i]}")
      SERVICE_DEPS+=("${REPO_DEPS[$i]}")
    fi
  done
}

# ---------------------------------------------------------------------------
# Git URL derivation
# ---------------------------------------------------------------------------

# Derive the base Git URL from rpsd's own remote origin.
# Example: git@github.com:Rapsodia/rpsd.git → git@github.com:Rapsodia
# Example: https://github.com/Rapsodia/rpsd.git → https://github.com/Rapsodia
# Returns empty string if no origin is configured.
get_git_base_url() {
  local origin
  origin=$(git -C "$RPSD_ROOT" remote get-url origin 2>/dev/null) || return 0

  # Strip trailing .git if present
  origin="${origin%.git}"

  # Strip the last path component (the repo name)
  # Works for both SSH (git@host:org/repo) and HTTPS (https://host/org/repo)
  if [[ "$origin" == *:* && "$origin" != https://* && "$origin" != http://* ]]; then
    # SSH format: git@github.com:Rapsodia/rpsd → git@github.com:Rapsodia
    echo "${origin%/*}"
  else
    # HTTPS format: https://github.com/Rapsodia/rpsd → https://github.com/Rapsodia
    echo "${origin%/*}"
  fi
}

# Build the full clone URL for a given repo name.
# Usage: build_clone_url <repo_name>
build_clone_url() {
  local name="$1"
  local base_url="${RPSD_GIT_BASE_URL:-$(get_git_base_url)}"

  if [[ -z "$base_url" ]]; then
    return 1
  fi

  echo "${base_url}/${name}.git"
}

# ---------------------------------------------------------------------------
# Environment file helpers
# ---------------------------------------------------------------------------

# Portable sed -i wrapper (macOS uses sed -i '', Linux uses sed -i).
sed_inplace() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Merge override env vars into a target .env file.
# For each KEY=VALUE in the override file:
#   - If KEY=... exists uncommented in target: replace the line
#   - If # KEY=... exists commented in target: uncomment and replace
#   - Otherwise: append to the end
# Comments and blank lines in the override file are skipped.
merge_env_overrides() {
  local target="$1"
  local override="$2"

  while IFS= read -r line; do
    # Skip comments and blank lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    local key="${line%%=*}"

    if grep -q "^${key}=" "$target" 2>/dev/null; then
      # Replace existing uncommented line
      local escaped
      escaped=$(printf '%s\n' "$line" | sed 's/[&/\]/\\&/g')
      sed_inplace "s|^${key}=.*|${escaped}|" "$target"
    elif grep -q "^# *${key}=" "$target" 2>/dev/null; then
      # Uncomment and replace
      local escaped
      escaped=$(printf '%s\n' "$line" | sed 's/[&/\]/\\&/g')
      sed_inplace "s|^# *${key}=.*|${escaped}|" "$target"
    else
      # Append
      echo "$line" >> "$target"
    fi
  done < "$override"
}

# ---------------------------------------------------------------------------
# Docker helpers
# ---------------------------------------------------------------------------

# Check Docker is available and running.
require_docker() {
  if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed or not in PATH"
    print_error "Install Docker: https://docs.docker.com/get-docker/"
    exit 1
  fi
  if ! docker info &> /dev/null 2>&1; then
    print_error "Docker is installed but not running. Please start Docker."
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Smart rebuild helpers
# ---------------------------------------------------------------------------

# Compute a build-sources label from git HEAD of the service and its deps.
# Usage: compute_build_sources_label <service_name> [deps]
# deps is a comma-separated list of library repo names.
# Outputs: "service:hash" or "service:hash,dep1:hash,dep2:hash"
# Returns 1 if a required repo directory is missing.
compute_build_sources_label() {
  local service="$1"
  local deps="$2"
  local label=""

  local repo_dir="$PARENT_DIR/$service"
  if [[ ! -d "$repo_dir/.git" ]]; then
    return 1
  fi
  local hash
  hash=$(git -C "$repo_dir" rev-parse --short=12 HEAD)
  label="${service}:${hash}"

  if [[ -n "$deps" ]]; then
    IFS=',' read -ra dep_list <<< "$deps"
    for dep in "${dep_list[@]}"; do
      local dep_dir="$PARENT_DIR/$dep"
      if [[ ! -d "$dep_dir/.git" ]]; then
        return 1
      fi
      local dep_hash
      dep_hash=$(git -C "$dep_dir" rev-parse --short=12 HEAD)
      label="${label},${dep}:${dep_hash}"
    done
  fi

  echo "$label"
}

# Read the rpsd.build.sources label from a Docker image.
# Usage: get_image_build_label <image_name>
# Outputs the label value, or empty string if not found.
get_image_build_label() {
  local image="$1"
  local label
  label=$(docker inspect --format='{{index .Config.Labels "rpsd.build.sources"}}' "$image" 2>/dev/null) || true
  # docker inspect returns "<no value>" when label doesn't exist
  if [[ "$label" == "<no value>" ]]; then
    label=""
  fi
  echo "$label"
}

# Check if a service image needs rebuilding.
# Usage: check_service_needs_build <service_name> <deps> <image_ref>
# Returns 0 if build is needed (with reason on stdout), 1 if up-to-date.
check_service_needs_build() {
  local service="$1"
  local deps="$2"
  local image="$3"

  local current_label
  current_label=$(compute_build_sources_label "$service" "$deps") || {
    echo "repo-missing"
    return 0
  }

  local image_label
  image_label=$(get_image_build_label "$image")

  if [[ -z "$image_label" ]]; then
    echo "no-image-or-label"
    return 0
  fi

  if [[ "$current_label" != "$image_label" ]]; then
    echo "sources-changed"
    return 0
  fi

  return 1
}

# Resolve the Docker image reference for a service profile.
# Usage: resolve_service_image <profile>
# Example: resolve_service_image "config" → value of RPSD_IMAGE_CONFIG or "rpsd-config:local"
resolve_service_image() {
  local profile="$1"
  local upper
  upper=$(echo "$profile" | tr '[:lower:]' '[:upper:]')
  local var_name="RPSD_IMAGE_${upper}"
  local image="${!var_name:-rpsd-${profile}:local}"
  echo "$image"
}

# Wait for a container to become healthy.
# Usage: wait_healthy <container_name> [timeout_seconds]
wait_healthy() {
  local container="$1"
  local timeout="${2:-60}"
  local waited=0
  while [ $waited -lt $timeout ]; do
    local status
    status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unknown")
    if [ "$status" = "healthy" ]; then
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  return 1
}
