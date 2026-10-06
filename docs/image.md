# The container image

`ghcr.io/pegelinuxtop/fedi.my.id` is this patch series applied to glitch-soc and
built with the tree's own `Dockerfile` — the same production image Mastodon and
glitch-soc ship, plus the fork's own stages (the `qrtool` builder in patch 5) and
code.

## How it is built

`.github/workflows/image.yml` runs `scripts/build-image.sh`, which is also the
script you run locally, so a CI build and a local build take the same path:

1. fetch glitch-soc at the requested ref (`git ls-remote` + a shallow fetch, so the
   build tracks upstream without a huge clone);
2. apply `patches/*` in `series` order with `git am` (with `--verify` it runs
   `scripts/lint-patches.sh` against the checkout first);
3. `docker buildx build` that tree, tagging the image and, with `--push`, pushing
   it to GHCR.

Triggers:

| Trigger | What it does |
|---|---|
| **manual** (`workflow_dispatch`) | build any glitch-soc ref: `main` by default, or a branch, tag or commit SHA; choose platforms and whether to push |
| **weekly** (Mondays 04:17 UTC) | rebuild on glitch-soc `main`, so a new upstream commit gets an image within a week |
| **push to `main`** here | rebuild when `patches/**`, `series`, `.base-commit` or the build script change |

Tags:

| Tag | Meaning |
|---|---|
| `latest` | the last successful build on glitch-soc `main` |
| `glitch-<sha12>` | the exact glitch-soc commit the tree was built from |
| `patchset-<rev7>` | the patch-set revision (a commit in this repository) |

Every image also carries `org.opencontainers.image.source`, `…revision` (the
glitch-soc commit) and `…version` labels, and the Dockerfile build arguments
`SOURCE_COMMIT` / `MASTODON_VERSION_METADATA` are set so
`Mastodon::Version.source_commit` and the version string identify the build.

If upstream moves in a way that breaks the series, the job fails on the `git am`
step and says so; rebase with [updating.md](updating.md), export the patches and
push — the push trigger rebuilds. Until then the previous image is untouched, and
`latest` keeps pointing at the last good build.

### Platforms

`linux/amd64` by default. For `linux/arm64` as well, pass `platforms:
linux/amd64 linux/arm64` to a manual run (multi-platform builds need `push` —
Docker cannot `--load` more than one platform). arm64 is emulated with QEMU, so it
is noticeably slower; glitch-soc's own workflow uses native `ubuntu-24.04-arm`
runners if you would rather add a matrix.

### First-time registry setup

To get the first image, run the workflow once by hand: **Actions → Container image
→ Run workflow** (leave `glitch_ref` at `main`, `push` on). It takes roughly 25–40
minutes on a GitHub runner; the job summary lists the tags it pushed. After that the
weekly schedule and every patch change keep it up to date.

- the image name is lowercased (`ghcr.io/pegelinuxtop/fedi.my.id`) because GHCR
  rejects uppercase;
- the workflow needs `packages: write`, which it declares for itself and satisfies
  with the automatic `GITHUB_TOKEN` — no personal access token is required to
  *push*; a PAT with `read:packages` is only needed to *pull* a private package;
- the first push creates the package as **private**. To pull it anonymously, make
  it public in the organisation's *Packages* settings (the package → Package
  settings → Change visibility);
- the organisation must allow Actions to create packages (organisation settings →
  Packages). If it does not, the push fails with a 403 and that setting is the fix.

## Building locally

```sh
# the pinned glitch-soc commit in .base-commit, loaded into the local daemon
scripts/build-image.sh

# glitch-soc's current main, verified, then pushed to GHCR
docker login ghcr.io -u <your-github-user>
scripts/build-image.sh --glitch-ref main --verify --push \
  --image ghcr.io/pegelinuxtop/fedi.my.id --tag latest

# a tagged glitch-soc release, arm64 as well as amd64 (needs --push)
scripts/build-image.sh --glitch-ref v4.7.3 \
  --platform linux/amd64 --platform linux/arm64 --push

# reuse a tree that is already built (skips clone and patch application)
scripts/build-image.sh --dest ~/src/fedi-image --skip-apply --tag local
```

Options: `--dest DIR`, `--glitch-ref REF`, `--glitch-remote URL`, `--image NAME`,
`--tag TAG` (repeatable), `--platform P` (repeatable), `--push`, `--verify`,
`--skip-apply`, `--no-cache`, `--keep`, `--help`. Without `--push` the image is
loaded into the local Docker daemon; the tree is left behind at `--dest` so you can
inspect it or build again quickly.

## Running the image

The image is the application only — it needs PostgreSQL, Redis and its environment
variables, exactly like Mastodon's own image:

```sh
docker run --rm -it \
  -e SECRET_KEY_BASE="$(openssl rand -hex 64)" \
  -e LOCAL_DOMAIN=fedi.my.id \
  -e DB_HOST=host.docker.internal -e DB_USER=mastodon -e DB_PASS=… \
  -e REDIS_URL=redis://host.docker.internal:6379/0 \
  -p 3000:3000 \
  ghcr.io/pegelinuxtop/fedi.my.id:latest
```

Then create and migrate the database once (`bin/rails db:setup` or
`db:create db:migrate`), keep `public/system` (uploads) and the database on volumes,
and put a reverse proxy in front of port 3000. `.env.production.sample` in the tree
documents every variable; Mastodon's
[installation docs](https://docs.joinmastodon.org/admin/install/) and
[`tootctl` docs](https://docs.joinmastodon.org/admin/tootctl/) apply unchanged.

Two things that are specific to this fork:

- `qrtool` is inside the image (the fork's `QrDecoder` calls it when a media
  attachment is processed), so the media pipeline works without installing it on
  the host;
- the `Dockerfile` stage that fetches `qrtool` is architecture-aware
  (`x86_64` / `aarch64`), which is why multi-platform builds work at all.

## Checking a published image

```sh
docker pull ghcr.io/pegelinuxtop/fedi.my.id:latest
docker run --rm ghcr.io/pegelinuxtop/fedi.my.id:latest qrtool --version
docker run --rm -e SECRET_KEY_BASE=x ghcr.io/pegelinuxtop/fedi.my.id:latest \
  bin/rails runner 'puts Mastodon::Version.to_s'
docker inspect ghcr.io/pegelinuxtop/fedi.my.id:latest \
  --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}'
```

The runbook that was used to verify this repository goes further: it checks
out the patched tree, runs `bin/rubocop`, `bin/haml-lint`, the `i18n-tasks` set,
`bin/rails db:migrate` with a schema comparison, and `bin/flatware rspec` — see
[verification.md](verification.md).
