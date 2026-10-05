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
`config/locales/en.yml`, `config/routes/admin.rb`, `db/migrate/*`) are carried by
patch 2 or 4 rather than duplicated across patches.

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
   `modern.scss`, `modern-urusai-fixes.scss`, `tangerineui*`) and
   `config/vite/plugin-sw-locales.mts` were normalised with the repo's own
   tooling (`oxfmt`, `stylelint --fix`) so that `yarn format:check` and
   `yarn lint:css` pass; `modern.scss` also gained a `stylelint-disable-next-line`
   comment for the (invalid, browser-ignored) `font-display` declaration on
   `body`. This removes a whitespace-only tweak to `plugin-sw-locales.mts` that
   `dev` has.

## Verification

Run against the tree produced by the series:

- `scripts/lint-patches.sh` — series/patches agree, no conflict markers, no
  modified migrations, unique migration timestamps, all 5 patches apply cleanly
  on the base commit.
- Patches applied with `git am` to a fresh glitch-soc checkout at the base
  commit produce the tree this README describes: the fork's `dev` tree merged
  onto the base commit, with the deviations listed above.
- Every file that differs from the base commit is a file the fork touches: for
  all 464 files changed between the fork's last merge point and `dev`, the
  patched tree differs from that pre-fork baseline (no customisation dropped),
  and no file outside that set was changed.
- JavaScript checks pass on the patched tree:
  `yarn format:check`, `yarn typecheck` (`tsc --noEmit`), `yarn lint:css`
  (`stylelint`) and `eslint` over the changed files (0 errors).

Not verified here, because the environment has no Ruby toolchain:
`bin/rubocop`, `bundle exec rails db:migrate`/schema comparison and the RSpec
suite. `db/schema.rb` in the tree is the merge of the fork's schema with
glitch-soc's current schema (including the fork's `bubble_domains`,
`status_reactions` tables and `status_stats.reactions_count`).
