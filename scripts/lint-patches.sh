#!/usr/bin/env bash
#
# Sanity checks for this patch set. Runs with just git + coreutils; no Ruby
# toolchain required.
#
# Checks performed:
#   1. .base-commit is a full 40-char SHA.
#   2. series and patches/ agree, and the numeric prefixes are ascending.
#   3. no patch contains conflict markers or looks like a raw merge diff.
#   4. every patch parses as a mail patch (From/Subject/--- headers).
#   5. migrations added by the patches have unique timestamps and names, never
#      collide with a migration that already exists at the base commit, and no
#      patch modifies an existing migration file.
#   6. (optional) the whole series applies cleanly: set BASE_REPO to a clone of
#      glitch-soc that contains .base-commit and it will be applied in a
#      throw-away worktree.
#
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_COMMIT="$(tr -d '[:space:]' < "$REPO_DIR/.base-commit" 2>/dev/null || true)"
SERIES="$REPO_DIR/series"
PATCH_DIR="$REPO_DIR/patches"
errors=0
warnings=0

ok()   { printf '  ok    %s\n' "$1"; }
warn() { printf '  warn  %s\n' "$1"; warnings=$((warnings + 1)); }
fail() { printf '  FAIL  %s\n' "$1"; errors=$((errors + 1)); }

echo "==> Base commit"
if [[ "$BASE_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  ok ".base-commit = $BASE_COMMIT"
else
  fail ".base-commit is not a full 40-char SHA: '$BASE_COMMIT'"
fi

echo "==> series vs patches/"
mapfile -t series_patches < <(grep -vE '^[[:space:]]*(#|$)' "$SERIES")
if [[ ${#series_patches[@]} -eq 0 ]]; then
  fail "series lists no patches"
fi

previous_prefix=""
for patch in "${series_patches[@]}"; do
  if [[ ! -f "$PATCH_DIR/$patch" ]]; then
    fail "series lists '$patch' but $PATCH_DIR/$patch does not exist"
    continue
  fi
  prefix="${patch%%-*}"
  if [[ -n "$previous_prefix" && "$prefix" < "$previous_prefix" ]]; then
    fail "series order is not ascending: '$patch' after prefix '$previous_prefix'"
  fi
  previous_prefix="$prefix"
done

while IFS= read -r file; do
  name="$(basename "$file")"
  if ! printf '%s\n' "${series_patches[@]}" | grep -qxF "$name"; then
    fail "$name is not listed in series"
  fi
done < <(find "$PATCH_DIR" -maxdepth 1 -name '*.patch' | sort)

echo "==> Patch contents"
migrations_added=()
migrations_modified=()
for patch in "${series_patches[@]}"; do
  file="$PATCH_DIR/$patch"
  [[ -f "$file" ]] || continue

  if grep -qE '^(<<<<<<< |>>>>>>> )' "$file"; then
    fail "$patch contains conflict markers"
  fi
  if ! grep -q '^From [0-9a-f]\{40\} ' "$file"; then
    fail "$patch does not start with a mail-patch 'From <sha>' header"
  fi
  if ! grep -q '^Subject: ' "$file"; then
    fail "$patch has no Subject header"
  fi

  # Files the patch adds (a `new file mode` immediately after the diff header).
  while IFS= read -r path; do
    migrations_added+=("$path")
  done < <(awk '
    /^diff --git / {
      path=""
      if (match($0, /a\/db\/migrate\/[^ ]+/)) {
        p = substr($0, RSTART + 2, RLENGTH - 2)
        path = p
      }
      next
    }
    /^new file mode / { if (path != "") { print path; path = "" } }
    /^(@@|--- |index |similarity |rename |deleted )/ { if (path != "" && $0 !~ /^new file mode /) path = "" }
  ' "$file")

  # Migrations the patch touches without adding them: modifying a migration
  # that has already shipped is a bug.
  while IFS= read -r path; do
    migrations_modified+=("$path")
  done < <(awk '
    /^diff --git / {
      path=""; isnew=0
      if (match($0, /a\/db\/migrate\/[^ ]+/)) {
        p = substr($0, RSTART + 2, RLENGTH - 2)
        n = substr($0, RSTART, RLENGTH)
        path = p
      }
      next
    }
    /^new file mode / { isnew=1; next }
    /^@@/ { if (path != "" && isnew == 0) { print path; path = "" } }
    /^diff --git / { }
  ' "$file")
done

if [[ ${#migrations_modified[@]} -gt 0 ]]; then
  for m in "${migrations_modified[@]}"; do
    fail "patch modifies an existing migration: $m"
  done
else
  ok "no existing migration file is modified by the patch set"
fi

echo "==> Migrations added by the patch set"
if [[ ${#migrations_added[@]} -eq 0 ]]; then
  warn "no migrations found in the patch set (unexpected for this fork)"
else
  declare -A seen_timestamp=() seen_name=()
  for m in "${migrations_added[@]}"; do
    base="$(basename "$m")"
    if [[ ! "$base" =~ ^([0-9]{14})_(.+)\.rb$ ]]; then
      fail "migration filename is not <timestamp>_<name>.rb: $base"
      continue
    fi
    timestamp="${BASH_REMATCH[1]}"
    name="${BASH_REMATCH[2]}"
    if [[ -n "${seen_timestamp[$timestamp]:-}" ]]; then
      fail "duplicate migration timestamp $timestamp ($base and ${seen_timestamp[$timestamp]})"
    fi
    if [[ -n "${seen_name[$name]:-}" ]]; then
      fail "duplicate migration name '$name' ($base and ${seen_name[$name]})"
    fi
    seen_timestamp[$timestamp]="$base"
    seen_name[$name]="$base"
    printf '  add   %s\n' "$base"
  done

  # Collisions with migrations that already exist at the base commit.
  base_repo="${BASE_REPO:-$REPO_DIR}"
  if [[ "$BASE_COMMIT" =~ ^[0-9a-f]{40}$ ]] && git -C "$base_repo" cat-file -e "${BASE_COMMIT}^{commit}" 2>/dev/null; then
    base_migrations="$(git -C "$base_repo" ls-tree -r --name-only "$BASE_COMMIT" -- db/migrate | xargs -r -n1 basename)"
    for base in $base_migrations; do
      if [[ -n "${seen_timestamp[${base:0:14}]:-}" ]]; then
        fail "migration ${base} already exists at $BASE_COMMIT (timestamp collision)"
      fi
    done
    ok "no migration timestamp collides with the base commit"
  else
    warn "base commit not available locally; skipped the base-migration collision check"
  fi
fi

echo "==> Applying the series to the base commit"
if [[ -n "${BASE_REPO:-}" ]]; then
  if ! git -C "$BASE_REPO" cat-file -e "${BASE_COMMIT}^{commit}" 2>/dev/null; then
    fail "BASE_REPO=$BASE_REPO does not contain $BASE_COMMIT"
  else
    tmp="$(mktemp -d)"
    if git -C "$BASE_REPO" worktree add --detach "$tmp" "$BASE_COMMIT" >/dev/null 2>&1; then
      applied=0
      for patch in "${series_patches[@]}"; do
        if git -C "$tmp" am "$PATCH_DIR/$patch" >/dev/null 2>&1; then
          applied=$((applied + 1))
        else
          git -C "$tmp" am --abort >/dev/null 2>&1
          fail "$patch does not apply cleanly on $BASE_COMMIT"
          break
        fi
      done
      if [[ $applied -eq ${#series_patches[@]} ]]; then
        ok "all ${#series_patches[@]} patches applied cleanly"
      fi
      git -C "$BASE_REPO" worktree remove --force "$tmp" >/dev/null 2>&1 || rm -rf "$tmp"
    else
      warn "could not create a temporary worktree in $BASE_REPO; skipped the apply check"
    fi
  fi
else
  warn "set BASE_REPO to a glitch-soc clone containing .base-commit to verify that the series applies"
fi

echo
if [[ $errors -gt 0 ]]; then
  echo "lint-patches: $errors error(s), $warnings warning(s)"
  exit 1
fi
echo "lint-patches: all checks passed ($warnings warning(s))"
