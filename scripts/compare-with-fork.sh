#!/usr/bin/env bash
#
# Compare the tree produced by this patch set against the fork's own branch
# (fedi.my.id@dev). The result is a patch set on top of *current* glitch-soc, so
# it is not byte-identical to the fork: it carries glitch-soc's evolution since
# the fork's last merge, plus the deviations documented in README.md. This script
# says exactly how the two relate, and fails if a fork customisation is lost.
#
# Requires git + coreutils only. It compares commits, so the checkout it looks at
# may be dirty.
#
# Usage:
#   scripts/compare-with-fork.sh [--result DIR|REV] [--fork PATH] [--fork-ref REF]
#                                [--base COMMIT] [--all] [--keep-ref]
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_COMMIT="$(tr -d '[:space:]' < "$REPO_DIR/.base-commit" 2>/dev/null || true)"
RESULT="${RESULT:-}"
RESULT_REV="HEAD"
FORK="${FORK:-}"
FORK_REF=""
SHOW_ALL=0
KEEP_REF=0
TMP_REF="refs/patchset-compare/fork"

usage() {
  cat <<EOF
Compare the patch-set result with the fork branch.

Options:
  --result DIR|REV   Checkout (or commit) holding the patch-set result.
                     Default: \$REPO_DIR/build when it exists, else the current
                     directory.
  --fork PATH        Clone of fedi.my.id to compare against.
                     Default: \$REPO_DIR/../fedi.my.id
  --fork-ref REF     Ref to compare against. Default: origin/dev, then dev.
  --base COMMIT      glitch-soc base commit. Default: .base-commit
                     ($BASE_COMMIT)
  --all              List every differing file instead of the first 20.
  --keep-ref         Keep the temporary ref used to fetch the fork ref.
  -h, --help         Show this help.

Exit status: 0 when no fork customisation was lost and every remaining
difference is either glitch-soc's own evolution or a documented deviation.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --result) RESULT="$2"; shift 2 ;;
    --fork) FORK="$2"; shift 2 ;;
    --fork-ref) FORK_REF="$2"; shift 2 ;;
    --base) BASE_COMMIT="$2"; shift 2 ;;
    --all) SHOW_ALL=1; shift ;;
    --keep-ref) KEEP_REF=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "compare-with-fork.sh: unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$RESULT" ]]; then
  if [[ -e "$REPO_DIR/build/.git" ]]; then
    RESULT="$REPO_DIR/build"
  else
    RESULT="."
  fi
fi
if [[ -z "$FORK" ]]; then
  if [[ -e "$REPO_DIR/../fedi.my.id/.git" ]]; then
    FORK="$REPO_DIR/../fedi.my.id"
  else
    echo "compare-with-fork.sh: no --fork given and $REPO_DIR/../fedi.my.id does not exist" >&2
    echo "                   pass --fork PATH pointing at a fedi.my.id clone" >&2
    exit 1
  fi
fi
if [[ ! "$BASE_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "compare-with-fork.sh: bad base commit '$BASE_COMMIT'" >&2
  exit 1
fi

# --result is either a checkout directory (whose revision is used) or, when we
# are already inside a repository, a revision name.
if [[ -d "$RESULT" ]]; then
  RESULT_DIR="$RESULT"
  RESULT_LABEL="$RESULT_DIR"
elif git -C . rev-parse --git-dir >/dev/null 2>&1; then
  RESULT_DIR="."
  RESULT_REV="$RESULT"
  RESULT_LABEL="$RESULT (in $(pwd))"
else
  echo "compare-with-fork.sh: '$RESULT' is neither a directory nor, inside a repository, a revision" >&2
  exit 1
fi

if ! git -C "$RESULT_DIR" cat-file -e "${RESULT_REV}^{commit}" 2>/dev/null; then
  echo "compare-with-fork.sh: $RESULT_LABEL has no revision '$RESULT_REV'." >&2
  echo "                   Build the result first, e.g. scripts/setup.sh --dest DIR" >&2
  exit 1
fi
if ! git -C "$RESULT_DIR" cat-file -e "${BASE_COMMIT}^{commit}" 2>/dev/null; then
  echo "compare-with-fork.sh: $RESULT_LABEL does not contain the base commit $BASE_COMMIT;" >&2
  echo "                   point --result at a checkout built from this patch set" >&2
  exit 1
fi
if [[ ! -e "$FORK/.git" ]]; then
  echo "compare-with-fork.sh: '$FORK' is not a git checkout of the fork" >&2
  exit 1
fi

if [[ -z "$FORK_REF" ]]; then
  for candidate in origin/dev dev; do
    if git -C "$FORK" rev-parse --verify --quiet "$candidate^{commit}" >/dev/null; then
      FORK_REF="$candidate"
      break
    fi
  done
  if [[ -z "$FORK_REF" ]]; then
    echo "compare-with-fork.sh: $FORK has neither 'origin/dev' nor 'dev'; pass --fork-ref" >&2
    exit 1
  fi
fi
if ! git -C "$FORK" rev-parse --verify --quiet "$FORK_REF^{commit}" >/dev/null; then
  echo "compare-with-fork.sh: $FORK has no ref '$FORK_REF'" >&2
  exit 1
fi

tmp_upstream="$(mktemp)"; tmp_fork="$(mktemp)"; tmp_fork_only="$(mktemp)"
tmp_mp_diff="$(mktemp)"; tmp_status="$(mktemp)"; tmp_list="$(mktemp)"
cleanup() {
  [[ "$KEEP_REF" == "0" ]] && git -C "$RESULT_DIR" update-ref -d "$TMP_REF" >/dev/null 2>&1
  rm -f "$tmp_upstream" "$tmp_fork" "$tmp_fork_only" "$tmp_mp_diff" "$tmp_status" "$tmp_list"
  return 0
}
trap cleanup EXIT

echo "==> Inputs"
if ! git -C "$RESULT_DIR" fetch --no-tags "$FORK" "$FORK_REF:$TMP_REF" >/dev/null 2>&1; then
  echo "compare-with-fork.sh: could not fetch '$FORK_REF' from $FORK into $RESULT_LABEL" >&2
  exit 1
fi
RESULT_SHA="$(git -C "$RESULT_DIR" rev-parse "${RESULT_REV}^{commit}")"
FORK_SHA="$(git -C "$RESULT_DIR" rev-parse "${TMP_REF}^{commit}")"
MERGE_POINT="$(git -C "$RESULT_DIR" merge-base "$BASE_COMMIT" "$TMP_REF")"

printf '  result     : %s (%s)\n' "$RESULT_LABEL" "$(git -C "$RESULT_DIR" rev-parse --short "$RESULT_SHA")"
printf '  fork       : %s (%s %s)\n' "$FORK" "$FORK_REF" "$(git -C "$FORK" rev-parse --short "$FORK_SHA")"
printf '  base       : %s (glitch-soc)\n' "$(git -C "$RESULT_DIR" rev-parse --short "$BASE_COMMIT")"
printf '  merge point: %s (the fork%ss last glitch-soc merge)\n' \
  "$(git -C "$RESULT_DIR" rev-parse --short "$MERGE_POINT")" "'"

# Path sets. Rename detection stays off so that a rename counts as a deletion
# plus an addition, which keeps the classification unambiguous.
git -C "$RESULT_DIR" diff --no-renames --name-only "$MERGE_POINT" "$BASE_COMMIT" | sort -u > "$tmp_upstream"
git -C "$RESULT_DIR" diff --no-renames --name-only "$MERGE_POINT" "$TMP_REF" | sort -u > "$tmp_fork"
comm -23 "$tmp_fork" "$tmp_upstream" > "$tmp_fork_only"
git -C "$RESULT_DIR" diff --no-renames --name-only "$MERGE_POINT" "$RESULT_SHA" | sort -u > "$tmp_mp_diff"
git -C "$RESULT_DIR" diff --no-renames --name-status "$TMP_REF" "$RESULT_SHA" > "$tmp_status"

declare -A upstream_changed=()
while IFS= read -r path; do
  [[ -n "$path" ]] && upstream_changed["$path"]=1
done < "$tmp_upstream"

failures=0
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }
warn() { printf '  warn  %s\n' "$1"; }
ok()   { printf '  ok    %s\n' "$1"; }

# ---------------------------------------------------------------- preservation
echo
echo "==> Fork changes preserved (fork relative to its merge point)"
fork_changed="$(wc -l < "$tmp_fork")"
# A fork change survives unless the result is identical to the pre-fork
# baseline for that path (a file deleted by glitch-soc still counts as differing).
mapfile -t mp_diff_paths < "$tmp_mp_diff"
declare -A result_differs=()
if [[ "${#mp_diff_paths[@]}" -gt 0 ]]; then
  for path in "${mp_diff_paths[@]}"; do
    [[ -n "$path" ]] && result_differs["$path"]=1
  done
fi
: > "$tmp_list"
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  [[ -n "${result_differs[$path]:-}" ]] || echo "$path" >> "$tmp_list"
done < "$tmp_fork"
lost="$(wc -l < "$tmp_list")"
printf '  files the fork changed since the merge point : %s\n' "$fork_changed"
printf '  still differing in the result                : %s\n' "$((fork_changed - lost))"
if [[ "$lost" -gt 0 ]]; then
  fail "$lost fork change(s) are identical to the pre-fork baseline (customisation lost)"
  if [[ "$SHOW_ALL" == "1" ]]; then
    sed 's/^/        /' "$tmp_list"
  else
    head -20 "$tmp_list" | sed 's/^/        /'
    [[ "$lost" -gt 20 ]] && echo "        … $((lost - 20)) more (use --all)"
  fi
else
  ok "no fork change was silently dropped"
fi

# ------------------------------------------------------- byte-identical subset
echo
echo "==> Fork-only files (glitch-soc did not touch them)"
fork_only="$(wc -l < "$tmp_fork_only")"
mapfile -t fork_only_paths < "$tmp_fork_only"
if [[ "$fork_only" -gt 0 ]]; then
  git -C "$RESULT_DIR" diff --no-renames --name-only "$TMP_REF" "$RESULT_SHA" -- "${fork_only_paths[@]}" | sort -u > "$tmp_list"
else
  : > "$tmp_list"
fi
fork_only_diff="$(wc -l < "$tmp_list")"
printf '  count                      : %s\n' "$fork_only"
printf '  byte-identical to the fork : %s\n' "$((fork_only - fork_only_diff))"
printf '  differing                  : %s\n' "$fork_only_diff"
if [[ "$fork_only_diff" -gt 0 ]]; then
  echo "  (the intentional ones are listed in README.md under \"Deviations\")"
  if [[ "$SHOW_ALL" == "1" ]]; then
    sed 's/^/        /' "$tmp_list"
  else
    head -20 "$tmp_list" | sed 's/^/        /'
    [[ "$fork_only_diff" -gt 20 ]] && echo "        … $((fork_only_diff - 20)) more (use --all)"
  fi
fi

# ------------------------------------------------ result vs fork, classified
echo
echo "==> Result vs fork"
total="$(wc -l < "$tmp_status")"
modified=0; added=0; deleted=0; deviations=0
: > "$tmp_list"
: > "${tmp_list}.unexplained"
: > "${tmp_list}.deleted_fork"
: > "${tmp_list}.deviations"
while IFS=$'\t' read -r status path; do
  [[ -z "$path" ]] && continue
  case "$status" in
    M)
      if [[ -n "${upstream_changed[$path]:-}" ]]; then
        modified=$((modified + 1))
      else
        deviations=$((deviations + 1))
        echo "$path" >> "${tmp_list}.deviations"
      fi
      ;;
    A)
      if [[ -n "${upstream_changed[$path]:-}" ]]; then
        added=$((added + 1))
      else
        echo "added, but glitch-soc did not add it: $path" >> "${tmp_list}.unexplained"
      fi
      ;;
    D)
      if [[ -n "${upstream_changed[$path]:-}" ]]; then
        deleted=$((deleted + 1))
        grep -qxF "$path" "$tmp_fork" && echo "$path" >> "${tmp_list}.deleted_fork"
      else
        echo "removed, but glitch-soc did not remove it: $path" >> "${tmp_list}.unexplained"
      fi
      ;;
    *)
      echo "unexpected diff status '$status': $path" >> "${tmp_list}.unexplained"
      ;;
  esac
done < "$tmp_status"

printf '  differing paths in total              : %s\n' "$total"
printf '  modified by glitch-soc since the merge: %s\n' "$modified"
printf '  added by glitch-soc                   : %s\n' "$added"
printf '  removed by glitch-soc                 : %s\n' "$deleted"
printf '  deviations (not glitch-soc-driven)    : %s\n' "$deviations"

if [[ -s "${tmp_list}.deleted_fork" ]]; then
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    rename_target="$(git -C "$RESULT_DIR" diff -M --name-status "$TMP_REF" "$RESULT_SHA" \
      | awk -v p="$path" '$1 ~ /^R/ && $2 == p { print $3; exit }')"
    if [[ -n "$rename_target" ]]; then
      warn "the fork customised $path, which glitch-soc renamed to $rename_target (see Deviations in README.md)"
    else
      warn "the fork customised $path, which glitch-soc removed; the customisation cannot be carried over"
    fi
  done < "${tmp_list}.deleted_fork"
fi
if [[ -s "${tmp_list}.unexplained" ]]; then
  fail "$(wc -l < "${tmp_list}.unexplained") path(s) differ from the fork for no glitch-soc reason"
  sed 's/^/        /' "${tmp_list}.unexplained"
fi
if [[ "$deviations" -gt "$fork_only_diff" ]]; then
  warn "$((deviations - fork_only_diff)) deviation(s) are in files glitch-soc also changed — check the fork's intent survived the reconciliation"
  comm -23 <(sort -u "${tmp_list}.deviations") <(sort -u "$tmp_fork_only") | sed 's/^/        /'
fi

echo
if [[ "$failures" -gt 0 ]]; then
  echo "compare-with-fork: $failures problem(s) — the result is not a faithful rebase of the fork"
  exit 1
fi
echo "compare-with-fork: OK — no fork change lost; every difference is glitch-soc's evolution or a documented deviation"
