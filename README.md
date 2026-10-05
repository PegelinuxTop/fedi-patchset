# fedi-patchset

Stacked Git / `git am` patch set that rebuilds the **fedi.my.id** fork
(`PegelinuxTop/fedi.my.id`, branch `dev`) on top of a clean
[glitch-soc/mastodon](https://github.com/glitch-soc/mastodon) checkout.

It exists so the fork can be moved onto the latest glitch-soc **without waiting
for [neatchee/mastodon](https://github.com/neatchee/mastodon) to re-merge
TheEssem's feature branches**: the three feature branches are applied directly
on current glitch-soc, followed by the fork's own customisations.

- Base commit: `.base-commit` (`b3877d5b245c6fa65f1a7639fa5593c6b6ade8fc`, glitch-soc `main`, 2026-10-05)
- Result: 5 patches, 461 files changed, +54392 / -299 vs the base commit
- Each patch applies on top of the previous one; together they reproduce the
  fork's tree (see [Verification](#verification)).

## Layout

```
.base-commit                  glitch-soc commit the series applies to
series                        patch order (read by scripts/setup.sh)
patches/                      git format-patch mail files
scripts/setup.sh              build a patched tree (git am, or --stg for StGit)
scripts/lint-patches.sh       static checks: series order, migration safety, apply test
```

## Build

```sh
# clone glitch-soc, check out the base commit, apply the series
scripts/setup.sh --dest ~/src/fedi.my.id

# or build a Stacked Git stack instead of plain commits
scripts/setup.sh --dest ~/src/fedi.my.id --stg

# or apply the series yourself
cd ~/src/mastodon && git checkout -B fedi-patchset b3877d5b245c6fa65f1a7639fa5593c6b6ade8fc
git am /path/to/fedi-patchset/patches/*.patch
```

Afterwards install the app dependencies (`bundle install`, `yarn install`) and
configure `.env.production` as usual.

`scripts/lint-patches.sh` runs without Ruby. Set `BASE_REPO` to a glitch-soc
clone that contains `.base-commit` to also verify that the whole series applies
cleanly:

```sh
BASE_REPO=~/src/mastodon scripts/lint-patches.sh
```

## Patch series

| # | Patch | Files | Contents |
|---|-------|-------|----------|
| 1 | `feature/reaction-list` | 97 | Emoji reactions (TheEssem): status reactions API, services, notifications, reaction list UI, admin/notification settings, 2 migrations |
| 2 | `feature/bubble-timeline` | 59 | Bubble timeline (TheEssem): bubble domains API + admin UI, `BUBBLE` column/feed, streaming channels, fan-out, settings, 3 migrations |
| 3 | `feature/gif-picker` | 31 | Tenor/Klipy GIF search (TheEssem): gif API + picker UI, instance serializer `gif_search`, locales |
| 4 | `fedi/branding-themes` | 273 | fedi.my.id's own customisations: sign-in banner, footers, custom modern/gekka/sakura/tangerine UI themes and skins, reject-pattern settings, locale additions, remaining migrations |
| 5 | `fedi/compat-overlay` | 6 | Reconciliation with glitch-soc changes: Elk footer link, Docker qrtool stage, `ja.yml` blurhash strings, `en.json` reaction notification, `eslint.config.mjs` |

The split is by feature/customisation, so an upstream rebase conflicts on the
furthest patch that touches a file. Shared configuration files that serve more
than one feature (`config/settings.yml`, `db/schema.rb`, `app/models/form/admin_settings.rb`,
`config/locales/en.yml`, `config/routes/admin.rb`, `db/migrate/*`) are each
carried by a single patch (2 or 4) instead of being repeated across patches.
Five files do legitimately receive incremental hunks from two patches —
`app/javascript/flavours/glitch/locales/en.json`,
`app/serializers/rest/instance_serializer.rb`, `config/locales-glitch/en.yml`,
`config/routes/api.rb` and `.env.production.sample` (patch 1 then patch 3) — and
the series applies cleanly in order. Note that patch 1 alone references
`Setting.bubble_live_feed_access`/`bubble_topic_feed_access` (defined by patch 2),
so individual patches are not meant to be cherry-picked in isolation.

### Migrations

The 8 migrations added by the fork are kept verbatim: original filenames,
timestamps and class names are unchanged, and no existing migration is
modified. No migration timestamp collides with a migration present at the base
commit. `scripts/lint-patches.sh` enforces all of this.

```
20221124114030_create_status_reactions.rb
20221218015350_fix_foreign_keys_status_reactions.rb
20230215074425_move_emoji_reaction_settings.rb
20240114042123_create_bubble_domains.rb
20240411044156_add_reaction_count_to_status_stat.rb
20250518031405_remove_quote_id_from_statuses.rb
20251018223804_add_bubble_timeline_preview_setting.rb
20251024193240_add_bubble_timeline_topic_preview_setting.rb
```

## Updating to a newer glitch-soc

```sh
# plain commits
git checkout -B fedi-patchset <new glitch-soc commit>
git am patches/*.patch          # resolve conflicts as they come up

# Stacked Git (recommended, lets you refresh individual patches)
stg init
for p in patches/*.patch; do stg import "$p"; done
stg rebase <new glitch-soc commit>
```

## Deviations from the `dev` branch of fedi.my.id

The patch set is generated from a merge of `fedi.my.id@dev` onto the base commit,
so the tree is the fork's tree plus glitch-soc's evolution since the fork's last
merge. These are the intentional differences from `dev` itself (everything else
in the tree comes from `dev` or from glitch-soc):

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
   `modern.scss`, `modern-urusai-fixes.scss`, `tangerineui*`) were normalised
   with the repo's own tooling (`oxfmt`, `stylelint --fix`) so that
   `yarn format:check` and `yarn lint:css` pass; `modern.scss` also gained a
   `stylelint-disable-next-line` comment for the (invalid, browser-ignored)
   `font-display` declaration on `body`. `dev`'s whitespace-only tweak to
   `config/vite/plugin-sw-locales.ts` (two lines containing a single space) is
   gone: glitch-soc renamed that file to `.mts`, and the built `.mts` carries
   glitch-soc's content.
6. **Lint/type fixes** so that the tree passes its own checks (all five are
   pre-existing in `dev`):
   - `app/javascript/flavours/glitch/features/gif_modal/index.tsx` — dropped an
     inline `eslint-disable-next-line jsx-a11y/no-autofocus`, which the fork's
     own `eslint.config.mjs` makes redundant (the rule is off globally), and
     which `--report-unused-disable-directives` reports as an error.
   - `app/javascript/flavours/glitch/features/ui/components/sign_in_banner.jsx` —
     added `type='button'` (`react/button-has-type`; the button is not inside a
     form, so this only makes the default explicit).
   - `eslint.config.mjs` — added an override turning `import/no-restricted-paths`
     off for `app/javascript/flavours/glitch/locales/*.js`; those overlay files
     exist to extend the vanilla locale JSON files.
   - `eslint.config.mjs` — added `**/*.mjs` to the block that sets
     `ecmaVersion: 2021`. `dev` narrowed that block to `js`/`jsx`/`ts`/`tsx`,
     which left the repo's own `eslint.config.mjs` (which uses `import.meta`) to
     be parsed with `ecmaVersion: 2018` and fail with a parse error.
   - `app/javascript/flavours/glitch/components/status/legacy/content.jsx` —
     documented `getStatusContent`'s parameter as
     `import('immutable').Map<string, unknown>` instead of `any`
     (`jsdoc/reject-any-type`).
7. **`app/javascript/mastodon/features/ui/index.jsx`** — kept glitch-soc's newer
   forms where `dev` still has the older ones: the named `{ BundleColumnError }`
   import (glitch-soc changed that module's export), the one-line
   `if (this.dataTransferIsText(e.dataTransfer)) return;` and the trailing
   `return;`. Semantically identical to `dev`'s variants.

## Known issues carried over from `dev`

These are inherited from the fork and left untouched, because fixing them
changes runtime behaviour:

- **Timeline boost/reply settings disagree.** `dev` (and therefore this patch
  set) splits `show_boosts/replies_in_public_timelines` into `_local_` and
  `_federated_` variants in the API and the admin UI, but never finished the
  rename:
  - `app/controllers/api/v1/timelines/public_controller.rb` reads
    `Setting.show_replies_in_local_timelines` / `_federated_` (and the `_reblogs_`
    equivalents); `app/models/form/admin_settings.rb` and
    `config/locales-glitch/en.yml` expose the same new names, and
    `config/settings.yml` only defines defaults for the old
    `show_replies_in_public_timelines` / `show_reblogs_in_public_timelines`.
    `Setting#[]` returns `nil` for unknown keys, so on a fresh install the new
    names behave like the old `false` default until an admin saves them once.
  - `app/services/fan_out_on_write_service.rb` still reads
    `Setting.show_reblogs_in_public_timelines` in `broadcastable?`, so reblogs
    are never fanned out to the public/local/bubble streams no matter what the
    admin toggles. Fixing it means pointing `broadcastable?` (and the
    `config/settings.yml` defaults) at the renamed keys.
- **The whole-repo `yarn lint:js` still reports 5 problems**, all in upstream
  files this patch set does not touch (they surface because `dev`'s
  `eslint.config.mjs` widened lint coverage to `**/*.js`/`**/*.jsx`, which
  glitch-soc's own config skips): `react/button-has-type` in
  `app/javascript/flavours/glitch/features/local_settings/navigation/item/index.jsx`
  and `.../features/notifications/components/pill_bar_button.jsx`, and
  `jsdoc/reject-any-type` in
  `app/javascript/flavours/glitch/components/scrollable_list/index.jsx`,
  `app/javascript/mastodon/components/scrollable_list/index.jsx` and
  `app/javascript/mastodon/components/status/legacy/content.jsx`. They are
  pre-existing in `dev`; they are not fixed here so that the patch set keeps
  touching only the files the fork already changes. `yarn lint:js` fails with
  `--max-warnings 0` until those five are addressed in the fork.

## Verification

Performed against the tree produced by the series (`scripts/setup.sh`, both the
`git am` and the `--stg` paths, on a fresh clone):

- `scripts/lint-patches.sh` — series/patches agree, every patch parses as a mail
  patch, no conflict markers, no existing migration modified, migration
  timestamps unique and free of collisions with the base commit, and all five
  patches apply cleanly to the base commit in a throwaway worktree.
- Nothing outside the fork's own changes was touched: every file that differs
  from the base commit is a file the fork modifies, and for all 464 files that
  differ between the fork's last merge point and `dev`, the patched tree still
  differs from that pre-fork baseline (no customisation dropped).
- JavaScript: `yarn format:check` (oxfmt, 2140 files), `yarn typecheck`
  (`tsc --noEmit`), `yarn lint:css` (stylelint, whole repo) and `yarn test:js`
  (vitest, 48 test files / 8089 tests) all pass. ESLint with
  `--report-unused-disable-directives --max-warnings 0` over every
  JavaScript/TypeScript file the patch set changes (105 files, including the
  root `eslint.config.mjs`) reports 0 problems; the root config ignores
  `streaming/**/*`, so those files are skipped there as they are in CI. A
  whole-repo ESLint run still reports the 5 pre-existing problems listed under
  "Known issues".
- Ruby: all 124 changed `.rb`/`.rake` files parse cleanly with Prism
  (`@ruby/prism`). The checker was validated against deliberately broken files,
  so a pass is a real pass.
- Data files: all 34 changed `.json`/`.yml` files parse cleanly.

Not verified here, because the environment has no Ruby toolchain: `bin/rubocop`,
the `bin/i18n-tasks` checks, `bundle exec rails db:migrate` with a schema
comparison, and the RSpec suite. `db/schema.rb` in the tree is the merge of the
fork's schema with glitch-soc's current schema (including the fork's
`bubble_domains` and `status_reactions` tables and `status_stats.reactions_count`).
Since it cannot be regenerated without Ruby, run `bin/rails db:migrate` once in a
real environment and commit the result if it differs.
