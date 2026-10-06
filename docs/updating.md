# Updating to a newer glitch-soc

The series is pinned to the commit in `.base-commit`. Picking up a newer
glitch-soc means replaying the five patches on top of a new commit and
re-exporting them.

## 0. Have a build checkout

```sh
~/Workspace/mastodon/fedi-patchset/scripts/setup.sh --dest ~/src/fedi.my.id --stg
```

`--stg` builds a Stacked Git stack, which is the comfortable way to rebase: you
can push, refresh and reorder individual patches. Without `--stg` you get five
plain commits and rebase them together.

## 1. Fetch glitch-soc and pick the new base

```sh
cd ~/src/fedi.my.id
git remote add upstream https://github.com/glitch-soc/mastodon.git  # once
git fetch upstream
NEW_BASE=$(git rev-parse upstream/main)      # or a tag/release commit
git log --oneline -1 "$NEW_BASE"
```

Read glitch-soc's release notes for that range before starting; a rebrand like
the composer redesign can move whole files (this happened between `64e05b4b2e`
and `b3877d5b24`).

## 2. Replay the series

With Stacked Git:

```sh
stg rebase "$NEW_BASE"
```

StGit replays patch by patch and stops at the first conflict. For each conflict:

```sh
git status                     # conflicted files
$EDITOR <files>                # resolve
git add <files>
stg refresh                    # fold the resolution into the current patch
stg push                       # continue with the next patch
# If a patch becomes empty because glitch-soc adopted it, drop it with:
stg delete <patch>
# If the stack metadata gets out of sync ("HEAD and stack top are not the same"):
stg repair
```

With plain commits:

```sh
OLD_BASE=$(cat ~/Workspace/mastodon/fedi-patchset/.base-commit)
git checkout -B fedi-patchset
git rebase --onto "$NEW_BASE" "$OLD_BASE" fedi-patchset
# resolve with `git add`, then `git rebase --continue`; `--skip` an empty commit
```

### How to resolve

The rule everywhere: **keep glitch-soc's newer code and re-apply the fork's
intent on top** — never revert glitch-soc to make a fork hunk apply unchanged.

- `config/locales*/*.yml`, `*.json` locale files: union — keep glitch-soc's keys
  and add the fork's.
- `db/schema.rb`: do not hand-merge. Regenerate with Ruby
  (`bin/rails db:migrate` against a database built from the base commit, then
  `bin/rails db:schema:dump`) and commit the result.
- migrations: never rename, never re-timestamp and never squash the fork's
  migrations, and never edit a migration that has already shipped. If glitch-soc
  ever lands a migration with the same timestamp as one of the fork's, renumber
  the fork's migration and note it in this file.
- theme SCSS and other fork-only files: the fork's copy is authoritative. That was
  `dev` before the 2026-10-06 sync; `dev` now holds the built tree and the pre-sync
  fork is `backup-20261006`, while the series in the build checkout is the fork's
  current intent. For a file that only exists in the fork there is nothing to
  merge.
- `Dockerfile`, `streaming/*`, `eslint.config.mjs`, the two `link_footer.tsx`:
  these are the files that tend to become the `fedi/compat-overlay` patch.
- `eslint.config.mjs` after a rebase: keep the `files: ['**/*.js', '**/*.jsx',
  '**/*.mjs', '**/*.ts', '**/*.tsx']` list on the block that sets
  `ecmaVersion: 2021` (dropping `**/*.jsx` breaks 14 `.jsx` files with `Parsing
  error: Unexpected token =`; dropping `**/*.mjs` breaks the config file itself),
  keep glitch-soc's `mjs: 'never'`, and keep the override that turns
  `import/no-restricted-paths` off for `app/javascript/flavours/glitch/locales/*.js`.
- `app/services/fan_out_on_write_service.rb`: keep the per-channel
  `broadcast_to_public_stream(channel, timelines)` shape and the
  `show_{reblogs,replies}_in_{local,federated}_timelines` names. Both sides look
  different before the patch set: glitch-soc at the base commit publishes each
  channel directly with one reply guard
  (`return if @status.reply? && … && !Setting.show_replies_in_public_timelines`)
  and uses the pre-rename keys in `broadcastable?`, while `dev` keeps a
  `broadcast_to` lambda, has no reply filter (a no-op expression), tests the
  pre-rename reblog key in `broadcastable?` and publishes
  `timeline:public:bubble` twice. Neither shape is what this tree needs
  (README deviation 1), so re-apply the patch's structure rather than either
  side's.

Per-patch conflict surface is listed at the end of
[patch-reference.md](patch-reference.md).

## 3. Re-export the patches and the base commit

```sh
cd ~/Workspace/mastodon/fedi-patchset
scripts/export-patches.sh --from ~/src/fedi.my.id --base "$NEW_BASE"
```

The script checks that the checkout has exactly as many commits above the new
base as `series` lists, writes `patches/*` in series order and updates
`.base-commit`. Run it with `--dry-run` first if you want to see the mapping. It
refuses to run when the counts do not match, which is the usual sign that a patch
became empty (drop it from `series` and re-run) or that the rebase is incomplete.

## 4. Re-verify

```sh
BASE_REPO=~/src/fedi.my.id scripts/lint-patches.sh
scripts/compare-with-fork.sh --result ~/src/fedi.my.id   # against the fork's dev
# the fork's dev holds the previous result, so this run is the meaningful one after
# a rebase; right after a sync (step 5) it is a mirror check, and
# `--fork-ref backup-<date>` compares against the release before that sync
scripts/check-ruby-syntax.mjs $(git -C ~/src/fedi.my.id diff --name-only "$NEW_BASE" HEAD | grep -E '\.(rb|rake)$')

cd ~/src/fedi.my.id
yarn format:check && yarn typecheck && yarn lint:css
NODE_OPTIONS=--max-old-space-size=5120 node_modules/.bin/eslint --cache --report-unused-disable-directives --max-warnings 0 .
yarn test:js

# Ruby side (needs Ruby 4.0.7, PostgreSQL and Redis — see verification.md)
bin/rubocop && bin/haml-lint
bin/i18n-tasks check-normalized && bin/i18n-tasks unused -l en
bin/i18n-tasks missing -t used -l en && bin/i18n-tasks check-consistent-interpolations
bin/rake repo:check_locales_files
bin/rails db:create db:migrate && bin/rails db:schema:dump && git diff --stat db/schema.rb
bin/flatware fan bin/rails db:test:prepare && bin/flatware rspec
```

See [verification.md](verification.md) for what each of those proves, the expected
values, and the environment the Ruby-side checks need (Ruby 4.0.7, PostgreSQL and
Redis; `bin/rubocop`, `bin/haml-lint`, `bin/i18n-tasks …`, `bin/rails db:migrate`,
`bin/flatware rspec`).

## 5. Rebuild the fork's `dev` branch

`fedi.my.id@dev` is the fork's branch and holds the previous result, so publish the
new one as a merge commit whose tree is the verified build tree. Work in a scratch
clone or a `git worktree` so the fork checkout stays on its own branch; never
`git push --force` this branch.

```sh
cd ~/Workspace/mastodon/fedi.my.id                  # the fork clone
git fetch origin
git worktree add --detach /tmp/fedi-dev             # isolated build, optional

# in the worktree: apply the series to the new base, then merge it into dev
cd /tmp/fedi-dev
git checkout -b series "$NEW_BASE"
git am ~/Workspace/mastodon/fedi-patchset/patches/*.patch
git checkout -B dev-sync origin/dev
git merge --no-commit --no-ff series                # conflicts are expected here
git read-tree --reset -u series                     # take the series' tree, as verified
git commit                                          # first parent = old dev: fast-forward

OLD_DEV=$(git rev-parse origin/dev)                 # capture before pushing
git push origin dev-sync:refs/heads/dev             # fast-forward
git push origin "$OLD_DEV":refs/heads/backup-$(date +%Y%m%d)
```

The push is a fast-forward, so nothing is rewritten; `scripts/compare-with-fork.sh`
against `dev` then reports 0 differing paths (fork-comparison.md, "Mirror check").
Tag or branch the old tip before pushing: `backup-20261006` preserves the
pre-2026-10-06 dev, and the next sync would replace it the same way.

## 6. Before you push

- [ ] `scripts/lint-patches.sh` passes (series, migrations, clean apply)
- [ ] `scripts/compare-with-fork.sh` reports no lost fork change
- [ ] every deviation it lists is either documented in the README or intentional
      and newly documented
- [ ] `.base-commit` and `series` match `patches/`
- [ ] the fork's `dev` rebuilt and pushed as a fast-forward, with the old tip kept
      as a `backup-<date>` branch (step 5)
- [ ] the numbers quoted in `README.md` and `docs/fork-comparison.md` are refreshed
      (patch file counts, `+/-` totals, comparison counts)
- [ ] the app's checks pass: `yarn format:check`, `yarn typecheck`, `yarn lint:css`
      and ESLint over the whole repository (all clean for this revision), plus
      `yarn test:js`
- [ ] the Ruby-side checks pass: `bin/rubocop`, `bin/haml-lint`, the
      `bin/i18n-tasks` set, migrations + a clean `db:schema.rb` dump, and
      `bin/flatware rspec` (14 known failures, all documented in the README's
      caveats — a *new* failure usually means the rebase dropped upstream code)

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `setup.sh: could not fetch <sha>` | the host refuses fetch-by-SHA. Fetch the branch, then `git rev-parse <branch>` for the commit |
| `stg import`/`stg push`: `HEAD and stack top are not the same` | the branch was moved outside StGit. `stg repair`, or delete `refs/stacks/<branch>` and re-import the patches |
| `git am` stops with conflicts | resolve, `git add`, `git am --continue`; `git am --abort` to start over, or use `--3way` |
| `export-patches.sh`: commit count mismatch | the rebase dropped or added a commit; align `series` with the actual commits |
| ESLint dies with `JavaScript heap out of memory` | run it with `NODE_OPTIONS=--max-old-space-size=5120` |
| `yarn: command not found` but the repo pins Yarn 4 | install the pinned CLI: `npm install --prefix /tmp/ytools @yarnpkg/cli-dist@$(node -p "require('./package.json').packageManager.split('@')[1]")` then use `/tmp/ytools/node_modules/.bin/yarn` |
| `yarn format:check` flags JS files that look wrong | expected: `.oxfmtrc.json` ignores `app/javascript/**/*.js` and `*.jsx` on purpose |
| a fork file disappears after a rebase | glitch-soc removed or renamed it (see [fork-comparison.md](fork-comparison.md)); if the fork customised it, decide whether to keep a copy under a new name or drop the change |
