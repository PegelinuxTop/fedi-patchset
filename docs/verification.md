# Verifying a build

Everything here runs against a checkout produced by `scripts/setup.sh`. Nothing
needs Ruby except the last section, which lists the checks this repository cannot
run for you.

## 1. The series is internally sound and applies

```sh
BASE_REPO=~/src/mastodon scripts/lint-patches.sh
# BASE_REPO must be a glitch-soc clone that contains .base-commit; without it the
# script still checks the series but skips the apply test.
```

Checks: `.base-commit` is a full SHA; `series` and `patches/` agree and are
ordered; every patch parses as a mail patch; no conflict markers; no existing
migration is modified; the fork's migrations — both `db/migrate` and
`db/post_migrate` — have unique timestamps and names and none collides with a
migration at the base commit; and the whole series applies to `.base-commit` in a
throwaway worktree.

Expected:

```
lint-patches: all checks passed (0 warning(s))
```

## 2. The build still contains the fork

```sh
scripts/compare-with-fork.sh --result ~/src/fedi.my.id                      # vs dev
scripts/compare-with-fork.sh --result ~/src/fedi.my.id \
  --fork-ref backup-20261006                                                # pre-sync
```

The first form compares the result with `fedi.my.id@dev`, which since 2026-10-06
holds the same tree, so it passes trivially (a mirror check that a rebuild
reproduces the branch). The second compares against the fork as it was before that
sync, which is the comparison the numbers below and in
[fork-comparison.md](fork-comparison.md) come from.

It fetches the fork branch into the built checkout under a temporary ref, finds
the merge base with `.base-commit`, and reports:

- how many of the fork's changed files still differ from the pre-fork baseline
  (**must be all of them** — any file that equals the baseline has lost its
  customisation and the script exits 1);
- how many fork-only files are byte-identical to the fork, and which differ (the
  deviations);
- every path that differs between the result and the fork, classified as
  glitch-soc's own evolution (modified/added/removed) or as a deviation.

Exit status is 0 only when nothing was lost and every difference is accounted for.
The numbers for the current revision are in [fork-comparison.md](fork-comparison.md).

## 3. Ruby syntax of the changed files

No Ruby needed — Prism (the parser Ruby itself uses) compiled to WebAssembly:

```sh
npm install --no-save @ruby/prism      # once, in this repository
cd ~/src/fedi.my.id
node ~/Workspace/mastodon/fedi-patchset/scripts/check-ruby-syntax.mjs \
  $(git diff --name-only "$(cat ~/Workspace/mastodon/fedi-patchset/.base-commit)" HEAD | grep -E '\.(rb|rake)$')
```

The script self-tests the parser first (a broken snippet must be rejected, a valid
one accepted) and exits with status 2 rather than reporting a bogus result if the
Prism build in the environment misbehaves. Expected:

```
checked 125 Ruby file(s): 0 with syntax errors
```

If you load Prism from somewhere other than this repository's `node_modules`, set
`PRISM_PATH` to the *module file*, not the package directory
(`PRISM_PATH=/tmp/ytools/node_modules/@ruby/prism/src/index.js`); the script imports
the path as-is and a directory import fails on Node's ESM resolver.

## 4. The app's own JavaScript checks

In the built checkout, after `yarn install`:

```sh
yarn format:check          # oxfmt — expects "All matched files use the correct format"
yarn typecheck             # tsc --noEmit
yarn lint:css              # stylelint
yarn test:js               # vitest legacy-tests
NODE_OPTIONS=--max-old-space-size=5120 node_modules/.bin/eslint \
  --cache --report-unused-disable-directives --max-warnings 0 .
```

Notes that cost time if you rediscover them:

- `.oxfmtrc.json` deliberately ignores `app/javascript/**/*.js`, `**/*.jsx` and
  `streaming/**/*.js`, so `format:check` does not cover them.
- the root ESLint config ignores `streaming/**/*` altogether (the `streaming`
  workspace has its own config but no `lint:js` script, so CI skips it too);
- ESLint over the whole repository needs more heap than the Node default here
  (`--max-old-space-size=5120`), otherwise it dies with
  `JavaScript heap out of memory`;
- `yarn` may not be installed even though the repository pins Yarn 4 — install the
  pinned CLI with
  `npm install --prefix /tmp/ytools @yarnpkg/cli-dist@$(node -p "require('./package.json').packageManager.split('@')[1]")`
  and use `/tmp/ytools/node_modules/.bin/yarn`;
- run these from a checkout that has its own `node_modules`. In a linked `git
  worktree` Vite resolves the real path of the main checkout, and `test:js` then
  fails with `Cannot find module '/@fs/<main-checkout>/node_modules/fake-indexeddb/auto/index.mjs'`;
- `test:js` already passes `--project=legacy-tests`; add only `run`
  (`yarn test:js run`) for a one-shot non-watch run.

`yarn lint:js` runs exactly the ESLint invocation above. It passes for this
revision — see the results table.

Two things about `eslint.config.mjs` that are easy to undo by accident:

- the block that sets `ecmaVersion: 2021` plus the TypeScript parser and the
  browser globals must keep `'**/*.jsx'` in its `files:` list. Without it, `.jsx`
  files are linted under the default `ecmaVersion` and fail to parse
  (`Parsing error: Unexpected token =` in 14 files), and `'**/*.mjs'` must stay
  there too or the config file itself fails on `import.meta`;
- `mjs: 'never'` (the `import/extensions` setting) is kept as glitch-soc has it;
  `dev` commented it out, and with it commented out the whole-repo run still passes
  here, so this is alignment rather than a fix.

## 5. Data files parse

With `node_modules` present (so `js-yaml` resolves):

```sh
cd ~/src/fedi.my.id
node -e '
const {readFileSync}=require("node:fs"); const yaml=require("js-yaml");
let bad=0; for (const f of process.argv.slice(1)) { const s=readFileSync(f,"utf8");
  try { f.endsWith(".json") ? JSON.parse(s) : yaml.load(s,{json:true}); }
  catch(e){ if(!s.includes("<%")){ bad++; console.log("FAIL", f, String(e.message).split("\n")[0]); } } }
console.log(`checked ${process.argv.length-1} file(s): ${bad} invalid`); process.exit(bad?1:0);' \
  $(git diff --name-only "$(cat ~/Workspace/mastodon/fedi-patchset/.base-commit)" HEAD | grep -E '\.(json|yml|yaml)$')
```

`config/email.yml`-style files containing ERB are skipped.

## What was verified for this revision

`.base-commit` = `b3877d5b245c6fa65f1a7639fa5593c6b6ade8fc`; the results below were
produced on a Linux machine with Node 26, Yarn 4.18.1, Ruby 4.0.7, PostgreSQL 18.6,
Redis 8.10.2 and StGit 2.6.1.

| Check | Result |
|---|---|
| `setup.sh` (git am) from a fresh clone | applies, tree identical to the reference (`b473d8b76f`) |
| `setup.sh --stg` | same tree, stack `0001…0005` |
| `lint-patches.sh` with `BASE_REPO` | all checks passed; all 5 patches apply cleanly |
| `compare-with-fork.sh` (`--fork-ref backup-20261006`) | 464/464 fork changes preserved, 0 lost; 806 differing paths, 90 documented deviations, 0 unexplained |
| `compare-with-fork.sh` (default, vs the rebuilt `dev`) | 470/470 preserved, 470/470 byte-identical, 0 differing paths |
| `check-ruby-syntax.mjs` | 125 changed `.rb`/`.rake` files, 0 syntax errors |
| JSON/YAML parse | 34 changed files, 0 invalid |
| `yarn format:check` | 2140 files, all correctly formatted |
| `yarn typecheck` | 0 errors |
| `yarn lint:css` (whole repo) | exit 0 |
| ESLint, 107 changed JS/TS/MJS files (the 110 minus the three `streaming/*.js` the config ignores), `--max-warnings 0` | 0 problems |
| ESLint, whole repo, `--max-warnings 0` | 0 problems (exit 0) |
| `yarn test:js` | 48 test files, 8089 tests passed |
| `bin/rails db:create db:migrate` on an empty database | exit 0; all migrations run, including the fork's 8 `db/migrate` and 2 `db/post_migrate` files |
| `db:schema:dump` vs the committed `db/schema.rb` | byte-identical |
| `bin/rubocop` | 3369 files inspected, no offenses |
| `bin/haml-lint` | 319 files inspected, 0 lints |
| `bin/i18n-tasks check-normalized` / `unused -l en` / `missing -t used -l en` / `check-consistent-interpolations` | all pass |
| `bin/rake repo:check_locales_files` | exit 0 (prints a note about upstream locale files that are not enabled) |
| `bin/flatware rspec` | 7934 examples, 0 failures, 4 pending |

The JavaScript-side results were produced before the Ruby fixes landed; those fixes
touch no JS/TS/CSS file, so they still describe this revision.

CI equivalents: `format-check.yml`, `lint-js.yml` (ESLint + `tsc`), `lint-css.yml`,
`test-js.yml`, `lint-ruby.yml`, `lint-haml.yml`, `check-i18n.yml`,
`test-migrations.yml` and `test-ruby.yml`.

## The Ruby-side checks

These need a Ruby toolchain plus PostgreSQL and Redis. What worked here (EndeavourOS,
no root):

```sh
# Ruby 4.0.7 (the repo's .ruby-version)
git clone --depth 1 https://github.com/rbenv/rbenv.git ~/.rbenv
git clone --depth 1 https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
~/.rbenv/plugins/ruby-build/bin/ruby-build 4.0.7 ~/.rbenv/versions/4.0.7
export PATH="$HOME/.rbenv/versions/4.0.7/bin:$PATH"

# PostgreSQL and Redis — with Docker, if available (one command each):
docker run -d --name mastodon-pg -e POSTGRES_HOST_AUTH_METHOD=trust \
  -p 5432:5432 postgres:18-alpine
docker run -d --name mastodon-redis -p 6379:6379 redis:8-alpine
# ... or, without root and without Docker, build them from source (that is what was
# done here: postgresql-18.6 tarball -> ~/pg18, redis-8.10.2 -> ~/build/redis-*).

cd ~/src/fedi.my.id            # a tree built by scripts/setup.sh
bundle config set --local build.pg "--with-pg-config=$HOME/pg18/bin/pg_config"   # source build only
bundle install
yarn install && yarn build:production       # the test env serves assets from public/packs

export RAILS_ENV=test DB_HOST=127.0.0.1 DB_PORT=5432 DB_USER=postgres DB_PASS=
bin/rails db:create db:migrate              # then: bin/rails db:schema:dump and diff
bin/flatware fan bin/rails db:test:prepare  # prepares the per-worker test databases
bin/flatware rspec                          # 4 workers by default
bin/rubocop && bin/haml-lint
bin/i18n-tasks check-normalized && bin/i18n-tasks unused -l en
bin/i18n-tasks missing -t used -l en && bin/i18n-tasks check-consistent-interpolations
bin/rake repo:check_locales_files
```

Gotchas:

- `charlock_holmes` fails to build against ICU 78 because mkmf emits `CXX = g++
  -std=gnu++11`; build it with a `make` wrapper that adds `-std=c++17`, or set that
  flag for the gem build;
- the test environment has `auto_build: true` for Vite, so a missing manifest makes
  specs shell out to `yarn` — build the assets first (or make sure `yarn` is on
  `PATH`);
- `bin/flatware rspec` is much faster than plain `bundle exec rspec` and gives each
  worker its own database;
- the environment here also lacked `libheif` and `libopenslide` for libvips; that
  only produces warnings and can affect HEIF/OpenSlide media specs.

### What the run had to fix first

The first full run was 34 failures. They are all fixed in the patch set now, and none
of them was caused by the merge itself: they are `dev`'s own bugs, or upstream
expectations that `dev`'s files contradict. The breakdown, so a future rebase
recognises them (details in the README deviations):

| Failures | Cause and fix |
|---|---|
| 17 | `lib/paperclip/qr_decoder.rb` called `log(...)`, which `Paperclip::Processor` does not define, so media post-processing raised whenever `qrtool` was missing. Fixed with `Rails.logger.warn` (deviation 8). |
| 11 | `spec/requests/api/v1/statuses/reactions_controller_spec.rb` was written as a controller spec but lives under `spec/requests/`, and called a `body_as_json` helper that no longer exists. Rewritten as a request spec on the real routes, with `:inline_jobs` for the asynchronous unreact (deviation 10). |
| 2 | `spec/models/form/import_spec.rb`, `spec/controllers/admin/export_domain_blocks_controller_spec.rb`: bare fixture names resolved against the working directory, where the fork's root `domain_blocks.csv` shadows the fixture (deviation 12). |
| 2 | `spec/services/{react,unreact}_service_spec.rb`: missing the `:inline_jobs` tag the rest of the suite uses (deviation 10). |
| 2 | `spec/requests/cache_spec.rb`: with `DISALLOW_UNAUTHENTICATED_API_ACCESS=true` the fork keeps `/api/v1/custom_emojis` public (deviation 11); the expectation now says so. |
| 3 | Spec files that used bare `describe` under `disable_monkey_patching!`, plus `status_policy_spec`'s `Fabricate(:react)` and the validator spec's `status.reactions.build` (deviation 10). |

Two `ActivityPub::ObjectIntegrityProof` ML-DSA examples depend on OpenSSL's
post-quantum support and failed in one run and passed in the next, so they are
environment-dependent rather than code-dependent.

## Not verified here

Booting the app and exercising the UI in a browser — the JavaScript suite covers
component behaviour, but nothing here rendered the fork's themes, the bubble timeline
or the reaction UI against a real server.

