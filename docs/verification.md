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
migration is modified; the fork's migrations have unique timestamps and names and
none collides with a migration at the base commit; and the whole series applies to
`.base-commit` in a throwaway worktree.

Expected:

```
lint-patches: all checks passed (0 warning(s))
```

## 2. The build still contains the fork

```sh
scripts/compare-with-fork.sh --result ~/src/fedi.my.id
```

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
checked 124 Ruby file(s): 0 with syntax errors
```

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
  and use `/tmp/ytools/node_modules/.bin/yarn`.

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
produced on a Linux machine with Node 26, Yarn 4.18.1 and StGit 2.6.1.

| Check | Result |
|---|---|
| `setup.sh` (git am) from a fresh clone | applies, tree identical to the reference |
| `setup.sh --stg` | same tree, stack `0001…0005` |
| `lint-patches.sh` with `BASE_REPO` | all checks passed; all 5 patches apply cleanly |
| `compare-with-fork.sh` | 464/464 fork changes preserved, 0 lost; every difference explained |
| `check-ruby-syntax.mjs` | 124 changed `.rb`/`.rake` files, 0 syntax errors |
| JSON/YAML parse | 34 changed files, 0 invalid |
| `yarn format:check` | 2140 files, all correctly formatted |
| `yarn typecheck` | 0 errors |
| `yarn lint:css` (whole repo) | exit 0 |
| ESLint, 105 changed JS/TS/MJS files, `--max-warnings 0` | 0 problems |
| ESLint, whole repo, `--max-warnings 0` | 5 problems, all pre-existing in `dev` and in files this patch set does not touch (see the README's "Known issues") |
| `yarn test:js` | 48 test files, 8089 tests passed |

CI equivalents: `format-check.yml`, `lint-js.yml` (ESLint + `tsc`), `lint-css.yml`,
`test-js.yml` and `lint-ruby.yml`/`test-migrations.yml`/`check-i18n.yml` respectively.

## What could not be verified here

The environment this patch set was assembled in has no Ruby toolchain, so these
are unverified and should be run once in a real environment:

- `bin/rubocop` (and `bin/rubocop --only …` for HAML, run by `lint-haml.yml`);
- `bin/i18n-tasks check-normalized`, `unused -l en`,
  `check-consistent-interpolations` and `bin/rake repo:check_locales_files`;
- `bin/rails db:migrate` with a schema comparison (`test-migrations.yml`) — the
  tree's `db/schema.rb` is the merge of the fork's schema with glitch-soc's current
  schema and has not been regenerated by Rails. If it differs after migrating,
  commit the regenerated file;
- `bundle exec rspec` (`test-ruby.yml`);
- booting the app and exercising the UI in a browser. The JavaScript test suite
  covers component behaviour, but nothing here rendered the fork's themes, the
  bubble timeline or the reaction UI against a real server.

If those pass unchanged, the fork is fully reproduced on the new base. Report any
difference rather than editing the patches around it: a Ruby-side failure usually
means a merge resolution dropped an upstream change.
