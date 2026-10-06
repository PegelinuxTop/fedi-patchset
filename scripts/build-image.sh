#!/usr/bin/env bash
#
# Build the fedi.my.id container image: a glitch-soc checkout with this patch
# series applied, built with the tree's own Dockerfile.
#
# The same script is what .github/workflows/image.yml runs, so a local run and a
# CI run take exactly the same path.
#
# Usage:
#   scripts/build-image.sh [--dest DIR] [--glitch-ref REF] [--glitch-remote URL]
#                          [--image NAME] [--tag TAG]... [--platform P]...
#                          [--push] [--verify] [--skip-apply] [--no-cache] [-h]
#
# Defaults: --dest ./build-tree, --glitch-ref = .base-commit (the pinned
# glitch-soc commit; pass --glitch-ref main to build on glitch-soc's current main),
# --image ghcr.io/pegelinuxtop/fedi.my.id, --tag latest, --platform linux/amd64.
# Without --push the image is loaded into the local Docker daemon.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIES="$REPO_DIR/series"
PATCH_DIR="$REPO_DIR/patches"
BASE_COMMIT="$(tr -d '[:space:]' < "$REPO_DIR/.base-commit")"

DEST="${DEST:-$PWD/build-tree}"
GLITCH_REF="${GLITCH_REF:-}"
GLITCH_REMOTE="${GLITCH_REMOTE:-https://github.com/glitch-soc/mastodon.git}"
IMAGE="${IMAGE:-ghcr.io/pegelinuxtop/fedi.my.id}"
TAGS=()
PLATFORMS=()
PUSH=0
VERIFY=0
SKIP_APPLY=0
NO_CACHE=0
KEEP=0

usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) DEST="$2"; shift 2 ;;
    --glitch-ref) GLITCH_REF="$2"; shift 2 ;;
    --glitch-remote) GLITCH_REMOTE="$2"; shift 2 ;;
    --image) IMAGE="$2"; shift 2 ;;
    --tag) TAGS+=("$2"); shift 2 ;;
    --platform) PLATFORMS+=("$2"); shift 2 ;;
    --push) PUSH=1; shift ;;
    --verify) VERIFY=1; shift ;;
    --skip-apply) SKIP_APPLY=1; shift ;;
    --no-cache) NO_CACHE=1; shift ;;
    --keep) KEEP=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "build-image.sh: unknown option: $1" >&2; usage 1 ;;
  esac
done

: "${GLITCH_REF:=$BASE_COMMIT}"
[[ ${#TAGS[@]} -gt 0 ]] || TAGS=(latest)
[[ ${#PLATFORMS[@]} -gt 0 ]] || PLATFORMS=(linux/amd64)

for tool in git docker; do
  command -v "$tool" >/dev/null 2>&1 || { echo "build-image.sh: '$tool' is required" >&2; exit 1; }
done
docker buildx version >/dev/null 2>&1 || { echo "build-image.sh: docker buildx is required" >&2; exit 1; }

# ---------------------------------------------------------------- the build tree
# Resolve a branch, tag or commit to a SHA. The ref is tried as an exact ref name
# first: a bare pattern would also match other branches whose name ends in it
# (glitch-soc has refs/heads/glitch-soc/main next to refs/heads/main).
resolve_ref() {
  local ref="$1" candidate sha
  if [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then printf '%s\n' "$ref"; return 0; fi
  for candidate in "refs/heads/$ref" "refs/tags/$ref^{}" "refs/tags/$ref" "$ref"; do
    sha="$(git ls-remote "$GLITCH_REMOTE" "$candidate" 2>/dev/null | awk 'NR==1 {print $1}')"
    if [[ -n "$sha" ]]; then printf '%s\n' "$sha"; return 0; fi
  done
  return 1
}

echo "==> Resolving $GLITCH_REF from $GLITCH_REMOTE"
GLITCH_SHA="$(resolve_ref "$GLITCH_REF")" || { echo "build-image.sh: cannot resolve '$GLITCH_REF' on $GLITCH_REMOTE" >&2; exit 1; }
GLITCH_SHORT="${GLITCH_SHA:0:12}"
echo "    glitch-soc $GLITCH_REF -> $GLITCH_SHA"

if [[ "$SKIP_APPLY" == "1" ]]; then
  [[ -d "$DEST" ]] || { echo "build-image.sh: --skip-apply needs an existing --dest ($DEST)" >&2; exit 1; }
  echo "==> Reusing the tree in $DEST"
else
  echo "==> Checking out glitch-soc $GLITCH_SHORT into $DEST"
  rm -rf "$DEST"
  git init --quiet "$DEST"
  git -C "$DEST" remote add origin "$GLITCH_REMOTE"
  git -C "$DEST" fetch --quiet --depth 1 origin "$GLITCH_SHA"
  git -C "$DEST" checkout --quiet --detach FETCH_HEAD

  if [[ "$VERIFY" == "1" ]]; then
    echo "==> Verifying the series against this checkout"
    BASE_REPO="$DEST" "$REPO_DIR/scripts/lint-patches.sh" | tail -3
  fi

  echo "==> Applying the patch series"
  export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-fedi-patchset}"
  export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-noreply@localhost}"
  applied=0
  while read -r patch; do
    [[ -z "$patch" || "$patch" == \#* ]] && continue
    if git -C "$DEST" am --quiet "$PATCH_DIR/$patch"; then
      applied=$((applied + 1))
      printf '    applied %s\n' "$patch"
    else
      git -C "$DEST" am --abort >/dev/null 2>&1 || true
      cat >&2 <<EOF
build-image.sh: '$patch' does not apply on glitch-soc $GLITCH_SHORT.

Upstream has moved since .base-commit. Rebase the series and re-export it
(docs/updating.md), or build on the pinned commit with
  scripts/build-image.sh --glitch-ref $BASE_COMMIT
EOF
      exit 1
    fi
  done < "$SERIES"
  echo "    $applied patches applied, tree ready"
fi

PATCHSET_REV="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"

# ---------------------------------------------------------------------- the image
IMAGE_ARGS=()
for tag in "${TAGS[@]}"; do IMAGE_ARGS+=(--tag "$IMAGE:$tag"); done
if [[ "$PUSH" == "0" && "${#PLATFORMS[@]}" -gt 1 ]]; then
  echo "build-image.sh: --load cannot take multiple platforms; pass --push or one --platform" >&2
  exit 1
fi
PLATFORM_LIST="$(IFS=,; echo "${PLATFORMS[*]}")"
OUTPUT_ARGS=(--load)
[[ "$PUSH" == "1" ]] && OUTPUT_ARGS=(--push)
[[ "$NO_CACHE" == "1" ]] && OUTPUT_ARGS+=(--no-cache)

echo "==> Building $IMAGE (${TAGS[*]}) for $PLATFORM_LIST"
echo "    source commit    : $GLITCH_SHA"
echo "    patchset revision: $PATCHSET_REV"
docker buildx build \
  --platform "$PLATFORM_LIST" \
  "${OUTPUT_ARGS[@]}" \
  "${IMAGE_ARGS[@]}" \
  --build-arg "SOURCE_COMMIT=$GLITCH_SHA" \
  --build-arg "MASTODON_VERSION_METADATA=glitch-$GLITCH_SHORT" \
  --label "org.opencontainers.image.source=https://github.com/pegelinuxtop/fedi-patchset" \
  --label "org.opencontainers.image.revision=$GLITCH_SHA" \
  --label "org.opencontainers.image.version=glitch-$GLITCH_SHORT" \
  "$DEST"

echo
echo "==> Done"
for tag in "${TAGS[@]}"; do echo "    $IMAGE:$tag"; done
if [[ "$PUSH" == "0" ]]; then
  echo "    (loaded locally; run it with:  docker run --rm -it $IMAGE:${TAGS[0]} bin/rails runner 'puts Mastodon::Version.to_s')"
fi
[[ "$KEEP" == "0" && "$SKIP_APPLY" == "0" ]] && echo "    tree kept at $DEST (remove it with: rm -rf '$DEST')"
echo "    source-commit=$GLITCH_SHA patchset-revision=$PATCHSET_REV"
