#!/bin/bash
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
  while IFS= read -r line; do
    # Skip comments and blank lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue
    read -r name type <<< "$line"
    REPO_NAMES+=("$name")
    REPO_TYPES+=("$type")
  done < "$REPOS_CONF"
}

# Get only service-type repo names into SERVICE_NAMES[@].
get_service_repos() {
  parse_repos_conf
  SERVICE_NAMES=()
  for i in "${!REPO_NAMES[@]}"; do
    if [[ "${REPO_TYPES[$i]}" == "service" ]]; then
      SERVICE_NAMES+=("${REPO_NAMES[$i]}")
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
