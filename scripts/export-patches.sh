#!/usr/bin/env bash
#
# Re-export patches/ from a built checkout, keeping the file names in series.
#
# Use it after rebasing the series onto a newer glitch-soc commit:
#
#   scripts/export-patches.sh --from ~/src/fedi.my.id --base <new glitch-soc commit>
#
# It refuses to overwrite anything unless the new base commit is an ancestor of
# the checkout's HEAD and the number of commits above it matches the number of
# entries in series. Nothing is pushed; review the diff to patches/ and the new
# .base-commit afterwards, then run scripts/lint-patches.sh.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIES="$REPO_DIR/series"
PATCH_DIR="$REPO_DIR/patches"
FROM=""
BASE=""
DRY_RUN=0

usage() {
  cat <<EOF
Re-export patches/ from a built checkout.

Options:
  --from DIR      Checkout that holds the patched series (its HEAD is the top).
  --base COMMIT   glitch-soc commit the series now applies to.
  --dry-run       Show what would be written, change nothing.
  -h, --help      Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "export-patches.sh: unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$FROM" || -z "$BASE" ]]; then
  echo "export-patches.sh: --from and --base are required" >&2
  usage >&2
  exit 1
fi
if [[ ! -d "$FROM/.git" && ! -f "$FROM/.git" ]]; then
  echo "export-patches.sh: '$FROM' is not a git checkout" >&2
  exit 1
fi
if [[ ! -f "$SERIES" ]]; then
  echo "export-patches.sh: $SERIES is missing" >&2
  exit 1
fi

mapfile -t patches < <(grep -vE '^[[:space:]]*(#|$)' "$SERIES")
if [[ "${#patches[@]}" -eq 0 ]]; then
  echo "export-patches.sh: series lists no patches" >&2
  exit 1
fi

if ! git -C "$FROM" cat-file -e "${BASE}^{commit}" 2>/dev/null; then
  echo "export-patches.sh: $FROM does not contain $BASE" >&2
  exit 1
fi
if ! git -C "$FROM" merge-base --is-ancestor "$BASE" HEAD; then
  echo "export-patches.sh: $BASE is not an ancestor of $FROM's HEAD" >&2
  exit 1
fi

count="$(git -C "$FROM" rev-list --count "$BASE..HEAD")"
if [[ "$count" != "${#patches[@]}" ]]; then
  echo "export-patches.sh: $FROM has $count commits above $BASE but series lists ${#patches[@]} patches" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git -C "$FROM" format-patch "$BASE..HEAD" -o "$tmp" --no-signature >/dev/null
mapfile -t generated < <(find "$tmp" -maxdepth 1 -name '*.patch' | sort)

if [[ "${#generated[@]}" != "${#patches[@]}" ]]; then
  echo "export-patches.sh: expected ${#patches[@]} generated files, found ${#generated[@]}" >&2
  exit 1
fi

echo "==> Exporting from $FROM"
for i in "${!patches[@]}"; do
  destination="$PATCH_DIR/${patches[$i]}"
  subject="$(sed -n 's/^Subject: \[PATCH[^]]*\] //p' "${generated[$i]}" | head -1)"
  printf '  %-34s <- %s\n' "${patches[$i]}" "$subject"
  if [[ "$DRY_RUN" == "0" ]]; then
    cp "${generated[$i]}" "$destination"
  fi
done

echo "==> Base commit"
if [[ "$DRY_RUN" == "0" ]]; then
  printf '%s\n' "$BASE" > "$REPO_DIR/.base-commit"
fi
printf '  .base-commit <- %s\n' "$BASE"

cat <<EOF

Next steps:
  BASE_REPO=$FROM $REPO_DIR/scripts/lint-patches.sh
  $REPO_DIR/scripts/compare-with-fork.sh --result $FROM
  # then refresh the numbers quoted in README.md and docs/fork-comparison.md
EOF
