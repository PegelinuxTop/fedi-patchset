# Runbook: the steps you do yourself

Everything that can be scripted is in `scripts/`, and the rebase procedure is in
[updating.md](updating.md). This file is only the operator side: the steps that need
your keyboard, your credentials or your server, and what to check afterwards. Every
command here has been run at least once on this repository — the numbers they print
are the ones in [fork-comparison.md](fork-comparison.md) and
[verification.md](verification.md).

## What lives where

| Thing | Where | Notes |
|---|---|---|
| the fork's customisations | `PegelinuxTop/fedi-patchset`, `patches/0001..0005` | source of truth; every rebase happens here |
| the tree you deploy | `PegelinuxTop/fedi.my.id`, branch `dev` | updated by fast-forward only; each sync keeps the previous tip as `backup-<date>` |
| the image | `ghcr.io/pegelinuxtop/fedi.my.id:latest`, `glitch-<sha12>`, `patchset-<rev7>` | built by `.github/workflows/image.yml` (Actions → Container image) |
| what is live | `curl -s https://fedi.my.id/api/v2/instance \| jq -r .version` | today that prints `4.8.0-nightly.2026-09-29+glitch.fedimyid` |

Three rules that are easy to get wrong:

- **never `git push --force` `dev`** — the sync is built to fast-forward, and a
  force push is the only way to lose a fork commit;
- **never use GitHub's "Sync fork" button** on `main` or `dev` — it wants to discard
  the branch's own commits;
- **pin production to a tag**, not `latest` (`glitch-<sha12>` or `patchset-<rev7>`),
  otherwise the weekly rebuild moves your deploy target under you.

## When you do nothing

The image rebuilds itself every Monday 04:17 UTC from glitch-soc `main`, and again
on every push that touches `patches/**`, `series`, `.base-commit` or
`scripts/build-image.sh`. That keeps `latest` current, but it does **not** rebase
the patches: if glitch-soc changes something the series touches, the job fails on
the apply step and `latest` keeps pointing at the last good build. You only need the
next section when you want to move the fork (and production) forward.

Watch it, if you like, with:

```sh
gh run list  --repo PegelinuxTop/fedi-patchset --limit 5
gh run watch --repo PegelinuxTop/fedi-patchset <run-id>
```

## 1. Rebase onto a new glitch-soc release

```sh
cd ~/Workspace/mastodon/fedi-patchset
scripts/setup.sh --dest ~/src/fedi-rebase --stg     # stg makes a rebase comfortable

cd ~/src/fedi-rebase
git remote add upstream https://github.com/glitch-soc/mastodon.git   # once
git fetch upstream
NEW_BASE=$(git rev-parse upstream/main)             # or a tag / release commit
git log --oneline -1 "$NEW_BASE"
stg rebase "$NEW_BASE"
```

Resolve conflicts by the rules in [updating.md](updating.md) — keep glitch-soc's
newer code and re-apply the fork's intent on top; never revert glitch-soc to make a
fork hunk apply unchanged. The per-patch conflict surface is at the end of
[patch-reference.md](patch-reference.md).

Then export the series, run the cheap checks, and push:

```sh
cd ~/Workspace/mastodon/fedi-patchset
scripts/export-patches.sh --from ~/src/fedi-rebase --base "$NEW_BASE"
BASE_REPO=~/src/fedi-rebase scripts/lint-patches.sh
scripts/compare-with-fork.sh --result ~/src/fedi-rebase          # vs the fork's dev

git add -A && git commit -m "rebase onto glitch-soc $NEW_BASE" && git push
```

`export-patches.sh` refuses to run when the commit count above the base does not
match `series` — that usually means a patch became empty (drop it from `series`).
`compare-with-fork.sh` must report **no lost fork change**; read the rest of its
output too: every remaining difference has to be glitch-soc's own evolution or a
deviation you recognise from the README.

For a big jump (a rebrand, a new Rails version), also run the app's own checks —
`yarn format:check`, `yarn typecheck`, `yarn lint:css`, ESLint, `yarn test:js` and
the Ruby side (`bin/rubocop`, `bin/haml-lint`, the `bin/i18n-tasks` set,
`bin/rails db:migrate`, `bin/flatware rspec`). [updating.md](updating.md) §4 has the
exact commands and [verification.md](verification.md) explains what each proves and
what the Ruby side needs (Ruby 4.0.7, PostgreSQL, Redis).

The push in step 1 already triggered the image build (the workflow watches
`patches/**`), so by the time you finish step 3 it is usually done.

## 2. Publish the new tree to the fork's `dev`

This is [updating.md](updating.md) §5 in full. It needs the fork clone and the
patches; it never rewrites `dev`.

```sh
cd ~/Workspace/mastodon/fedi.my.id
git fetch origin
git worktree add --detach /tmp/fedi-dev                     # keeps your checkout alone

cd /tmp/fedi-dev
git checkout -b series "$NEW_BASE"                          # the base from step 1
git am ~/Workspace/mastodon/fedi-patchset/patches/*.patch
git checkout -B dev-sync origin/dev
git merge --no-commit --no-ff series                        # conflicts here are expected
git read-tree --reset -u series                             # take the series' tree
git commit                                                  # first parent is the old dev, so the push fast-forwards

OLD_DEV=$(git rev-parse origin/dev)                         # capture before pushing
git push origin dev-sync:refs/heads/dev
git push origin "$OLD_DEV":refs/heads/backup-$(date +%Y%m%d)

cd ~/Workspace/mastodon/fedi.my.id
git worktree remove --force /tmp/fedi-dev
```

Check it immediately — the point of the merge is that the branch is byte-identical
to the build tree:

```sh
cd ~/Workspace/mastodon/fedi-patchset
scripts/compare-with-fork.sh --result ~/src/fedi-rebase
# right after a sync this is the mirror check: 0 differing paths, 470/470 preserved
git -C ~/Workspace/mastodon/fedi.my.id rev-parse origin/dev^{tree}   # = the build tree
```

## 3. Or build and publish the image by hand

Useful when CI is down, when you want a different glitch-soc ref, or when you want
arm64 as well. Either press the button — **Actions → Container image → Run
workflow** — or use the CLI:

```sh
gh workflow run image.yml --repo PegelinuxTop/fedi-patchset \
  -f glitch_ref=main -f platforms=linux/amd64 -f push=true
```

or build locally (same script the workflow runs):

```sh
docker login ghcr.io -u rezhajulio            # a PAT with write:packages
cd ~/Workspace/mastodon/fedi-patchset
scripts/build-image.sh --glitch-ref main --verify --push \
  --image ghcr.io/pegelinuxtop/fedi.my.id --tag latest
```

`--verify` runs `lint-patches.sh` against the checkout first, so a bad base fails
before the build. `--tag` is repeatable; `--platform` too (multi-platform needs
`--push`).

## 4. Deploy to fedi.my.id

Only you can do this part: the deployment configuration is not in this repository,
so treat the two blocks below as the shape of it and adapt the paths and service
names. Whichever you use, **pin a tag** rather than `latest`, and back up the
database before the first deploy that contains new migrations.

Image-based:

```sh
# in your compose directory on the server
docker compose pull web streaming sidekiq      # with the pinned image tag in compose
docker compose run --rm web bin/rails db:migrate
docker compose up -d
```

Checkout-based (this is what fedi.my.id runs today — its version string says
`4.8.0-nightly.2026-09-29+glitch.fedimyid`):

```sh
cd /path/to/fedi.my.id                         # on the server
git fetch origin && git checkout dev && git merge --ff-only origin/dev
bundle install && yarn install --immutable
RAILS_ENV=production bundle exec rails assets:precompile
RAILS_ENV=production bundle exec rails db:migrate
# then restart web, streaming and sidekiq the way your server does it
```

Do the new migrations matter? A rebase usually carries none, but check before you
deploy:

```sh
git -C ~/Workspace/mastodon/fedi.my.id diff --name-only "$OLD_DEV" origin/dev \
  -- db/migrate db/post_migrate
```

Anything listed there has to be run once, and only once, by the process that owns
the database.

## 5. Confirm what is live

```sh
curl -s https://fedi.my.id/api/v2/instance | jq -r .version     # the build metadata
docker inspect <your-running-image> \
  --format '{{index .Config.Labels "org.opencontainers.image.revision"}}'
```

The version metadata is set when the image is built: the workflow images say
`glitch-<sha12>` of the glitch-soc commit they were built from, and an image built
from a checkout reports whatever `MASTODON_VERSION_METADATA` the build passed. If
the string did not change, the deploy did not take effect — check that the asset
precompile and the service restart happened, not just the git pull.

## 6. Rollback

- **image deploy**: put the previous tag (`glitch-<sha12>` / `patchset-<rev7>`)
  back into compose and `docker compose up -d`. No git change, no schema change:
  Mastodon's migrations are additive, so the older image still boots against the
  migrated database.
- **checkout deploy**: `git checkout <previous dev sha>`, re-run the asset
  precompile and restart. The previous trees are on the branch `backup-<date>`.
- **last resort** (only if `dev` itself has to move back): push the backup branch
  over it with a lease, never a bare force:
  `git push --force-with-lease origin backup-<date>:refs/heads/dev`. Then fix the
  series forward instead — the whole point of `backup-*` is to avoid needing this.

## 7. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| CI fails with `<patch> does not apply cleanly`, but it applies locally | `git am` needs a committer identity. `lint-patches.sh` supplies its own; if you write new CI around `git am`, set `user.name`/`user.email` or `GIT_COMMITTER_NAME`/`GIT_COMMITTER_EMAIL` |
| CI fails on the apply step after a glitch-soc change | a patch touches code glitch-soc moved or renamed — rebase (step 1); `latest` still points at the last good build |
| GHCR push fails with 403 | the organisation must allow Actions to create packages (organisation settings → Packages) |
| `docker pull` fails with denied/unauthorised | the package is private: `docker login ghcr.io -u <user>` with a PAT that has `read:packages`, or make the package public |
| `latest` moved and something broke | `latest` follows glitch-soc `main` weekly by design; pin production to a tag |
| `setup.sh --stg` stops immediately | Stacked Git 2.x is not installed (`stg`); it is checked before anything is changed |
| `stg` says `HEAD and stack top are not the same` | the branch was moved outside StGit: `stg repair`, or delete `refs/stacks/<branch>` and re-import `patches/*` in `series` order |
| `export-patches.sh` reports a commit-count mismatch | the rebase dropped or added a commit; align `series` with the actual commits |
| `compare-with-fork.sh` lists lost customisations | the merge dropped the fork's change to those files; re-apply it, re-export, and re-run |
| the fork's `dev` shows as behind glitch-soc | it is a fast-forward of the previous `dev`, not of glitch-soc; what matters is the tree hash and the comparison above |
| missing `qrtool`, media fails | only relevant for the checkout path: the image carries `qrtool`, a server build needs it on the host |

## 8. Housekeeping and open choices

- `main` on the fork still points at the pre-patchset merge history
  (`0828922071`); fast-forwarding it to `dev` is optional and non-destructive — a
  fresh clone just gets `dev` by checking it out explicitly.
- the package `ghcr.io/pegelinuxtop/mastodon` is a leftover nightly test image from
  2024-12-31 built by the old `PegelinuxTop/mastodon` repository; delete it if
  nothing pulls it.
- GHCR creates the package private. Keep it private and log in on the server, or
  make it public (organisation → Packages → the package → Package settings →
  Change visibility) if you want anonymous pulls.
- scratch checkouts (`~/src/fedi-rebase`, `~/src/fedi.my.id`) can be deleted after
  a rebase; each is a full Mastodon tree.
- local Docker build cache grows fast (tens of GB): `docker builder prune` when you
  need the disk back.
