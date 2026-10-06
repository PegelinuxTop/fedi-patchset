# fedi-patchset

Build the [fedi.my.id](https://github.com/PegelinuxTop/fedi.my.id) Mastodon fork
on top of a current [glitch-soc](https://github.com/glitch-soc/mastodon) checkout,
from a stack of five patches.

- **Base commit**: `.base-commit` — glitch-soc `main`
  `b3877d5b245c6fa65f1a7639fa5593c6b6ade8fc` (2026-10-05)
- **Result**: 5 patches, 461 files changed, +54400 / −300 against that commit
- **Licence**: AGPL-3.0, like glitch-soc and Mastodon — see [LICENSE](LICENSE)

## Why this exists

The fork is glitch-soc plus three upstream feature branches by
[TheEssem](https://github.com/TheEssem) (emoji reactions, bubble timeline, GIF
picker) plus the operator's own customisations:

```
glitch-soc/mastodon ─┬─ TheEssem/feature/reaction-list ───┐
                     ├─ TheEssem/feature/bubble-timeline ─┼─ fedi.my.id @dev
                     └─ TheEssem/feature/gif-picker-v2 ───┘        │
                                                                   └─ operator customisations
```

Historically those were assembled by merging
[neatchee/mastodon](https://github.com/neatchee/mastodon), which meant new
Mastodon/glitch-soc releases could only be picked up after that re-merge. This
repository keeps the same result as a patch series that applies directly to
glitch-soc main, so upstream updates are a rebase here instead of a wait.

## Requirements

| For | Needs |
|---|---|
| building the tree, comparing it with the fork | bash ≥ 4, git, coreutils |
| `scripts/setup.sh --stg` | [Stacked Git](https://stacked-git.github.io/) 2.x (`stg`) |
| the app's own checks (`format:check`, `typecheck`, `lint`, `test:js`) | Node ≥ 22 and Yarn 4 |
| Ruby-side checks (`bin/rubocop`, i18n-tasks, migrations, specs) | Ruby + the app's gems |

## Quick start

```sh
# 1. build a working tree: clone glitch-soc, check out the base commit, apply the series
scripts/setup.sh --dest ~/src/fedi.my.id          # plain commits (git am)
scripts/setup.sh --dest ~/src/fedi.my.id --stg    # or a Stacked Git stack

# 2. install and configure the app
cd ~/src/fedi.my.id
bundle install && yarn install
cp .env.production.sample .env.production         # then edit it
RAILS_ENV=production bundle exec rails db:setup

# 3. check the build
scripts/compare-with-fork.sh --result ~/src/fedi.my.id   # vs fedi.my.id@dev
BASE_REPO=~/src/mastodon scripts/lint-patches.sh         # patches are internally sound
```

`setup.sh` options: `--dest DIR`, `--branch NAME`, `--remote URL`, `--stg`,
`--force`, `--help`. It is safe to re-run: an existing checkout is reused, the
branch is reset to the base commit and the series is applied again.

## Repository layout

```
.base-commit                     glitch-soc commit the series applies to
series                           patch order, read by the scripts
patches/0001..0005-*.patch       the patch series (git format-patch mail files)
LICENSE                          AGPL-3.0 (glitch-soc / Mastodon)
README.md                        this file
docs/updating.md                 rebasing onto a newer glitch-soc
docs/patch-reference.md          what each patch contains and why
docs/verification.md             how to verify a build, and what was verified
docs/fork-comparison.md          how the result relates to the fork's dev branch
scripts/setup.sh                 build the patched tree
scripts/lint-patches.sh          static checks on the series + apply test
scripts/compare-with-fork.sh     compare the result with fedi.my.id@dev
scripts/check-ruby-syntax.mjs    parse changed Ruby files without Ruby (Prism/WASM)
```

## The patch series

| # | Patch | Files | Contents |
|---|-------|-------|----------|
| 1 | `feature/reaction-list` | 97 | Emoji reactions (TheEssem): status-reaction API, service layer, federation, notifications, reaction list UI, notification/admin settings, 2 migrations |
| 2 | `feature/bubble-timeline` | 59 | Bubble timeline (TheEssem): bubble-domain API + admin UI, `BUBBLE` feed and column, streaming channels, fan-out, settings, 3 migrations |
| 3 | `feature/gif-picker` | 31 | Tenor/Klipy GIF search (TheEssem): GIF API client + picker UI, `gif_search` in the instance serializers, locales |
| 4 | `fedi/branding-themes` | 273 | The operator's own customisations: sign-in banner, footers, custom modern/gekka/sakura/tangerine UI themes and skins, reject-pattern settings, locale additions, 3 migrations |
| 5 | `fedi/compat-overlay` | 6 | Reconciliation with glitch-soc changes: Elk footer link, Docker `qrtool` stage, `ja.yml` blurhash strings, `en.json` reaction notification, `eslint.config.mjs` |

Per-patch sizes are 2391/+92−, 1362/+76−, 891/+21−, 49717/+112− and 41/+1−
(lines added/removed). The split is by feature or customisation, so an upstream
rebase conflicts on the furthest patch that touches a file. Shared configuration
that serves more than one feature (`config/settings.yml`, `db/schema.rb`,
`app/models/form/admin_settings.rb`, `config/locales/en.yml`,
`config/routes/admin.rb`, `db/migrate/*`) is carried by a single patch rather than
repeated. Five files legitimately receive incremental hunks from two patches
(`app/javascript/flavours/glitch/locales/en.json`,
`app/serializers/rest/instance_serializer.rb`, `config/locales-glitch/en.yml`,
`config/routes/api.rb`, `.env.production.sample`: patch 1 then patch 3), and patch
1 alone references `Setting.bubble_live_feed_access`/`bubble_topic_feed_access`,
which patch 2 defines — so the patches are not meant to be cherry-picked
individually. See [docs/patch-reference.md](docs/patch-reference.md).

### Migrations

The eight migrations the fork adds are kept verbatim — original filenames,
timestamps and class names — and no existing migration is modified. None of their
timestamps collide with a migration present at the base commit, which
`scripts/lint-patches.sh` enforces.

```
0001  20221124114030_create_status_reactions.rb
0001  20240411044156_add_reaction_count_to_status_stat.rb
0002  20240114042123_create_bubble_domains.rb
0002  20251018223804_add_bubble_timeline_preview_setting.rb
0002  20251024193240_add_bubble_timeline_topic_preview_setting.rb
0004  20221218015350_fix_foreign_keys_status_reactions.rb
0004  20230215074425_move_emoji_reaction_settings.rb
0004  20250518031405_remove_quote_id_from_statuses.rb
```

## Keeping up with glitch-soc

```sh
git fetch origin main                       # in the built checkout
cd /path/to/fedi-patchset
# StGit stack (recommended — patches stay annotatable and refreshable):
(cd ~/src/fedi.my.id && stg rebase <new glitch-soc commit>)
# or plain commits:
(cd ~/src/fedi.my.id && git rebase --onto <new commit> <old base> fedi-patchset)
```

Then re-export the patches, update `.base-commit` and re-run the checks —
[docs/updating.md](docs/updating.md) has the full procedure, including where
conflicts are likely to land and the checklist to run before pushing.

## Verifying a build

| Script | Answers |
|---|---|
| `scripts/lint-patches.sh` | is the series internally sound and does it apply to `.base-commit`? (`BASE_REPO=<glitch-soc clone>` also applies it in a throwaway worktree) |
| `scripts/compare-with-fork.sh` | does the built tree still contain every fork change, and is every remaining difference explained? |
| `scripts/check-ruby-syntax.mjs` | do the changed `.rb`/`.rake` files parse? (Prism/WASM, self-testing) |
| the app's own scripts | `yarn format:check`, `yarn typecheck`, `yarn lint:css`, `yarn lint:js`, `yarn test:js` |

Exact commands, expected output and the checks that could not be run here are in
[docs/verification.md](docs/verification.md); the fork comparison is explained in
[docs/fork-comparison.md](docs/fork-comparison.md).

## Deviations from the fork's `dev` branch

The tree is generated from a merge of `fedi.my.id@dev` onto the base commit, so it
is the fork's tree plus glitch-soc's evolution since the fork's last glitch-soc
merge. These are the intentional differences from `dev` itself:

1. **`app/services/fan_out_on_write_service.rb`** — same observable behaviour as
   `dev` (public/local/remote/bubble broadcasts, replies not filtered), but the
   unreachable `broadcast_to` lambda, the no-op `@status.reply? && …` statement
   and the duplicate `timeline:public:bubble` publish were removed.
2. **`app/javascript/flavours/glitch/initial_state.ts`** — `dev`'s
   `useSystemEmojiFont = getMeta('system_emoji_font')` export was dropped: the
   meta field no longer exists in glitch-soc, the export is unused, and it fails
   `yarn typecheck`.
3. **`streaming/index.js`** — kept glitch-soc's explanatory comment and
   indentation instead of `dev`'s de-indented variant. No functional difference.
4. **`app/javascript/{flavours/glitch,}/components/autosuggest_textarea.jsx`** —
   dropped a whitespace-only line that `dev` carries.
5. **Formatting** — `dev`'s theme SCSS (`app/javascript/**/theme/*.scss`,
   `modern.scss`, `modern-urusai-fixes.scss`, `tangerineui*`) was normalised with
   the repo's own tooling (`oxfmt`, `stylelint --fix`) so that
   `yarn format:check` and `yarn lint:css` pass; `modern.scss` also gained a
   `stylelint-disable-next-line` comment for the (invalid, browser-ignored)
   `font-display` declaration on `body`. `dev`'s whitespace-only tweak to
   `config/vite/plugin-sw-locales.ts` is gone, because glitch-soc renamed that
   file to `.mts` and the built `.mts` carries glitch-soc's content.
6. **Lint/type fixes**, all pre-existing in `dev`, so the tree passes its own
   checks:
   - `app/javascript/flavours/glitch/features/gif_modal/index.tsx` — dropped an
     inline `eslint-disable-next-line jsx-a11y/no-autofocus` that the fork's own
     `eslint.config.mjs` makes redundant (the rule is off globally), and which
     `--report-unused-disable-directives` reports as an error.
   - `app/javascript/flavours/glitch/features/ui/components/sign_in_banner.jsx` —
     added `type='button'` (`react/button-has-type`; the button is not inside a
     form, so this only makes the default explicit).
   - `eslint.config.mjs` — an override turning `import/no-restricted-paths` off
     for `app/javascript/flavours/glitch/locales/*.js`, which exist to extend the
     vanilla locale JSON files.
   - `eslint.config.mjs` — `**/*.mjs` added to the block that sets
     `ecmaVersion: 2021`. `dev` narrowed that block to `js`/`jsx`/`ts`/`tsx`,
     which left the repository's own `eslint.config.mjs` (which uses
     `import.meta`) to be parsed as ES2018 and fail.
   - `app/javascript/flavours/glitch/components/status/legacy/content.jsx` —
     typed `getStatusContent`'s parameter as
     `import('immutable').Map<string, unknown>` instead of `any`
     (`jsdoc/reject-any-type`).
7. **`app/javascript/mastodon/features/ui/index.jsx`** — kept glitch-soc's newer
   forms where `dev` still has the older ones: the named `{ BundleColumnError }`
   import (glitch-soc changed that module's export), the one-line
   `if (this.dataTransferIsText(e.dataTransfer)) return;` and the trailing
   `return;`. Semantically identical to `dev`'s variants.

## Known issues carried over from `dev`

Left untouched on purpose, because fixing them changes runtime behaviour:

- **Timeline boost/reply settings disagree.** The fork splits
  `show_boosts/replies_in_public_timelines` into `_local_` and `_federated_`
  variants in the API and the admin UI, but the rename was never finished:
  - `app/controllers/api/v1/timelines/public_controller.rb` reads
    `Setting.show_replies_in_local_timelines` / `_federated_` (and the `_reblogs_`
    equivalents); `app/models/form/admin_settings.rb` and
    `config/locales-glitch/en.yml` expose the same new names, while
    `config/settings.yml` still defines defaults for the old
    `show_replies_in_public_timelines` / `show_reblogs_in_public_timelines`.
    `Setting#[]` returns `nil` for unknown keys, so on a fresh install the new
    names behave like the old `false` default until an admin saves them once.
  - `app/services/fan_out_on_write_service.rb` still reads
    `Setting.show_reblogs_in_public_timelines` in `broadcastable?`, so reblogs are
    never fanned out to the public/local/bubble streams no matter what the admin
    toggles. Fixing it means pointing `broadcastable?` (and the
    `config/settings.yml` defaults) at the renamed keys.
- **The whole-repo `yarn lint:js` reports 5 problems**, all in upstream files this
  patch set does not touch (they surface because `dev`'s `eslint.config.mjs`
  widened lint coverage to `**/*.js`/`**/*.jsx`, which glitch-soc's own config
  skips): `react/button-has-type` in
  `app/javascript/flavours/glitch/features/local_settings/navigation/item/index.jsx`
  and `.../features/notifications/components/pill_bar_button.jsx`, plus
  `jsdoc/reject-any-type` in
  `app/javascript/flavours/glitch/components/scrollable_list/index.jsx`,
  `app/javascript/mastodon/components/scrollable_list/index.jsx` and
  `app/javascript/mastodon/components/status/legacy/content.jsx`. They are
  pre-existing in `dev`; fixing them would mean touching files the fork does not
  otherwise change, so `yarn lint:js` fails with `--max-warnings 0` until they are
  addressed in the fork.

## Provenance

How this revision was produced (it is reproducible from `dev` and the base
commit):

1. `git merge` of `fedi.my.id@dev` onto `b3877d5b245c6fa65f1a7639fa5593c6b6ade8fc`
   (merge-base `64e05b4b2eece29fafeff43c867bb0985c28bc52`, the fork's last
   glitch-soc merge);
2. the 8 conflicts resolved by keeping glitch-soc's newer code and re-applying the
   fork's intent (`flavours/glitch` and `mastodon`
   `components/status/legacy/action_bar/index.jsx`, `flavours/glitch`
   `features/status/components/action_bar.jsx`, `flavours/glitch` and `mastodon`
   `features/ui/index.jsx`, `flavours/glitch` and `mastodon`
   `features/ui/components/link_footer.tsx`, `flavours/glitch`
   `features/firehose/index.jsx`);
3. the resulting difference folded into the five patch boundaries;
4. the repo's own formatter and linters applied to the files the patch set
   touches, plus the lint fixes listed under Deviations;
5. the patches exported with `git format-patch`, and the checks in
   [docs/verification.md](docs/verification.md) run.

Of the fork's 464 changed files, all 464 survive; 352 of the 421 files glitch-soc
did not touch are byte-identical to `dev`, and the other 69 are the deviations
above. [docs/fork-comparison.md](docs/fork-comparison.md) has the full breakdown.
