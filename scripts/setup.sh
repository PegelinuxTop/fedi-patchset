#!/usr/bin/env bash
#
# Build the fedi.my.id fork tree from glitch-soc + this patch set.
#
# The patch set is applied on top of the glitch-soc commit recorded in
# .base-commit. By default the patches are applied as plain commits with
# `git am`; pass --stg to build a Stacked Git (stg) stack instead, which is
# more convenient for rebasing onto a newer glitch-soc.
#
# Usage:
#   scripts/setup.sh [--dest DIR] [--branch NAME] [--remote URL] [--stg] [--force]
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_COMMIT="$(tr -d '[:space:]' < "$REPO_DIR/.base-commit")"
REMOTE_URL="${REMOTE_URL:-https://github.com/glitch-soc/mastodon.git}"
DEST="${DEST:-$REPO_DIR/build}"
BRANCH="${BRANCH:-fedi-patchset}"
USE_STG=0
FORCE=0

usage() {
  cat <<EOF
Build the fedi.my.id fork tree on top of glitch-soc.

Options:
  --dest DIR      Where to clone / which existing checkout to use (default: $DEST)
  --branch NAME   Branch to create for the patched tree (default: $BRANCH)
  --remote URL    Upstream glitch-soc remote (default: $REMOTE_URL)
  --stg           Apply the patches as a Stacked Git stack instead of commits
  --force         Discard local changes in --dest before applying the patches
  -h, --help      Show this help

Environment:
  UPSTREAM_URL, DEST, BRANCH

Base commit: $BASE_COMMIT
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) DEST="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --remote) REMOTE_URL="$2"; shift 2 ;;
    --stg) USE_STG=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "setup.sh: unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ ! -f "$REPO_DIR/.base-commit" ]]; then
  echo "setup.sh: .base-commit is missing" >&2
  exit 1
fi

if [[ "$USE_STG" == "1" ]] && ! command -v stg >/dev/null 2>&1; then
  echo "setup.sh: --stg requested but 'stg' is not installed" >&2
  exit 1
fi

if [[ -e "$DEST/.git" ]]; then
  echo "==> Using existing checkout at $DEST"
  if [[ "$FORCE" == "1" ]]; then
    git -C "$DEST" reset --hard
    git -C "$DEST" clean -fd
  fi
  if [[ -n "$(git -C "$DEST" status --porcelain)" ]]; then
    echo "setup.sh: $DEST has local changes; commit/stash them or pass --force" >&2
    exit 1
  fi
  git -C "$DEST" fetch --prune "$REMOTE_URL" "+refs/heads/*:refs/remotes/upstream/*" >/dev/null 2>&1 || true
elif [[ -e "$DEST" ]]; then
  echo "setup.sh: $DEST exists but is not a git checkout" >&2
  exit 1
else
  echo "==> Cloning $REMOTE_URL into $DEST"
  git clone "$REMOTE_URL" "$DEST"
fi

if ! git -C "$DEST" cat-file -e "${BASE_COMMIT}^{commit}" 2>/dev/null; then
  echo "==> Fetching base commit $BASE_COMMIT"
  if ! git -C "$DEST" fetch "$REMOTE_URL" "$BASE_COMMIT" 2>/dev/null; then
    echo "setup.sh: could not fetch $BASE_COMMIT from $REMOTE_URL." >&2
    echo "           Fetch glitch-soc main manually and retry." >&2
    exit 1
  fi
fi

echo "==> Checking out $BASE_COMMIT as branch $BRANCH"
git -C "$DEST" checkout -B "$BRANCH" "$BASE_COMMIT"

if [[ "$USE_STG" == "1" ]]; then
  echo "==> Initialising Stacked Git stack"
  if git -C "$DEST" rev-parse --verify refs/stacks/"$BRANCH" >/dev/null 2>&1; then
    echo "==> Dropping the existing stack metadata for branch $BRANCH"
    git -C "$DEST" update-ref -d refs/stacks/"$BRANCH"
  fi
  (cd "$DEST" && stg init)
  while read -r patch; do
    [[ -z "$patch" || "$patch" == \#* ]] && continue
    echo "==> stg import $patch"
    (cd "$DEST" && stg import --name "${patch%.patch}" "$REPO_DIR/patches/$patch")
  done < "$REPO_DIR/series"
else
  echo "==> Applying patches with git am"
  # shellcheck disable=SC2046
  git -C "$DEST" am --3way $(while read -r patch; do
    [[ -z "$patch" || "$patch" == \#* ]] && continue
    printf '%q ' "$REPO_DIR/patches/$patch"
  done < "$REPO_DIR/series")
fi

echo
echo "Done. The patched tree is at $DEST (branch $BRANCH)."
echo
echo "Next steps:"
echo "  cd $DEST"
echo "  bundle install && yarn install"
echo "  cp .env.production.sample .env.production   # then edit it"
echo "  RAILS_ENV=production bundle exec rails db:setup"
