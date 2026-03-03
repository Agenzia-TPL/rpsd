#!/bin/bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
  echo "Usage: $0 [--base-url <git-base-url>]"
  echo ""
  echo "Clone all managed repositories listed in repos.conf."
  echo "Git URLs are derived from rpsd's own remote origin."
  echo ""
  echo "Options:"
  echo "  --base-url <url>   Override the base Git URL"
  echo "                     (e.g. git@github.com:Rapsodia)"
  echo "  --help             Show this help message"
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)
      RPSD_GIT_BASE_URL="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      print_error "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

# Export so build_clone_url can use it
export RPSD_GIT_BASE_URL

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo -e "${GREEN}=== Cloning rpsd Platform Repositories ===${NC}"
echo ""

# Check for git
if ! command -v git &> /dev/null; then
  print_error "git is not installed"
  exit 1
fi

# Resolve base URL
BASE_URL="${RPSD_GIT_BASE_URL:-$(get_git_base_url)}"
if [[ -z "$BASE_URL" ]]; then
  print_error "Cannot determine Git base URL."
  print_error "The rpsd repo has no remote origin configured."
  echo ""
  echo "  Use --base-url to provide the Git organization URL explicitly:"
  echo "    SSH:   $0 --base-url git@github.com:Rapsodia"
  echo "    HTTPS: $0 --base-url https://github.com/Rapsodia"
  echo ""
  echo "  To get the base URL from an existing clone of any sibling repo, run:"
  echo "    git -C ../rpsd-ingest remote get-url origin"
  echo "  Then strip the repo name from the end."
  echo ""
  echo "  Once rpsd itself has a remote, future runs will detect it automatically."
  exit 1
fi

print_info "Base URL: $BASE_URL"
echo ""

parse_repos_conf

CLONED=0
SKIPPED=0
FAILED=0

for i in "${!REPO_NAMES[@]}"; do
  name="${REPO_NAMES[$i]}"
  type="${REPO_TYPES[$i]}"
  target="$PARENT_DIR/$name"
  url="${BASE_URL}/${name}.git"

  if [ -d "$target" ]; then
    print_warn "$name ($type) already exists — skipping"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  print_info "Cloning $name ($type) from $url ..."
  if git clone "$url" "$target"; then
    print_success "Cloned $name"
    CLONED=$((CLONED + 1))
  else
    print_error "Failed to clone $name"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo -e "${GREEN}=== Clone Summary ===${NC}"
echo -e "  Cloned:  ${GREEN}$CLONED${NC}"
echo -e "  Skipped: ${YELLOW}$SKIPPED${NC}"
echo -e "  Failed:  ${RED}$FAILED${NC}"

[ $FAILED -gt 0 ] && exit 1
exit 0
