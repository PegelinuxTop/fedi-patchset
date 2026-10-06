# fedi-patchset

Build the [fedi.my.id](https://github.com/PegelinuxTop/fedi.my.id) Mastodon fork
on top of a current [glitch-soc](https://github.com/glitch-soc/mastodon) checkout,
from a stack of five patches.

- **Base commit**: `.base-commit` — glitch-soc `main`
  `b3877d5b245c6fa65f1a7639fa5593c6b6ade8fc` (2026-10-05)
- **Result**: 5 patches, 470 files changed, +54573 / −317 against that commit
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

Since 2026-10-06 the fork's `dev` branch *is* this result: commit `43e2b637c8`,
whose second parent is the series (glitch-soc `b3877d5b24` plus patches 1–5) and
whose tree is the verified build tree
`b473d8b76fe2fb8cd5084e3135a62ea923c2d126`. It was pushed as a fast-forward over
the previous `dev` (`b416d280e0`), which is preserved as the branch
`backup-20261006`. Wherever these documents say "`dev`", they mean that pre-sync
branch unless they say otherwise; [docs/fork-comparison.md](docs/fork-comparison.md)
explains what the comparison now checks. The fork's default branch `main` still
points at the pre-sync merge history (`0828922071`), so a fresh clone gets the
fork before this rebase — check out `dev` for the current tree.

## Requirements

| For | Needs |
|---|---|
| building the tree, comparing it with the fork | bash ≥ 4, git, coreutils |
| `scripts/setup.sh --stg` | [Stacked Git](https://stacked-git.github.io/) 2.x (`stg`) |
| the app's own checks (`format:check`, `typecheck`, `lint`, `test:js`) | Node ≥ 22 and Yarn 4 |
| the container image (`scripts/build-image.sh`, the `image` workflow) | Docker with buildx |
| Ruby-side checks (`bin/rubocop`, `haml-lint`, i18n-tasks, migrations, specs) | Ruby 4.0.7 + the app's gems, PostgreSQL, Redis |

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

Since the 2026-10-06 sync `dev` holds exactly the build tree, so the comparison
above is a mirror check; add `--fork-ref backup-20261006` to compare against the
fork as it was before the sync — that is what the numbers in
[docs/fork-comparison.md](docs/fork-comparison.md) describe.

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
docs/fork-comparison.md          how the result relates to the fork (and its dev branch)
docs/image.md                    the container image: how it is built, tagged and run
scripts/setup.sh                 build the patched tree
scripts/lint-patches.sh          static checks on the series + apply test
scripts/compare-with-fork.sh     compare the result with the fork (dev; --fork-ref)
scripts/build-image.sh           build the container image from a patched tree
scripts/check-ruby-syntax.mjs    parse changed Ruby files without Ruby (Prism/WASM)
.github/workflows/image.yml      builds and pushes ghcr.io/pegelinuxtop/fedi.my.id
```

## The patch series

| # | Patch | Files | Contents |
|---|-------|-------|----------|
| 1 | `feature/reaction-list` | 97 | Emoji reactions (TheEssem): status-reaction API, service layer, federation, notifications, reaction list UI, notification/admin settings, 2 migrations + 2 post-migrations |
| 2 | `feature/bubble-timeline` | 60 | Bubble timeline (TheEssem): bubble-domain API + admin UI, `BUBBLE` feed and column, streaming channels, fan-out, settings, 3 migrations — plus the fork's per-timeline boost/reply settings wired through fan-out and their specs |
| 3 | `feature/gif-picker` | 31 | Tenor/Klipy GIF search (TheEssem): GIF API client + picker UI, `gif_search` in the instance serializers, locales |
| 4 | `fedi/branding-themes` | 273 | The operator's own customisations: sign-in banner, local-settings page, qrtool decoder, custom modern/gekka/sakura/tangerine UI themes and skins, reject-pattern settings, locale additions, 3 migrations — plus the runtime, lint and spec fixes of deviations 8–10 |
| 5 | `fedi/compat-overlay` | 14 | Reconciliation with glitch-soc and with the repo's own check suite: Elk footer link, Docker `qrtool` stage, `ja.yml` blurhash strings, `en.json` reaction notification, `eslint.config.mjs`, lint fixes for five files the fork does not otherwise touch, and three upstream specs adjusted for the fork's behaviour and its root-level `domain_blocks.csv` |

Per-patch sizes are 2391/+92−, 1476/+83−, 886/+21−, 49748/+113− and 74/+10−
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

The ten migrations the fork adds — eight under `db/migrate` and two under
`db/post_migrate` — are kept verbatim, with their original filenames, timestamps
and class names, and no existing migration is modified. None of their timestamps
collides with a migration present at the base commit, which
`scripts/lint-patches.sh` enforces for both directories.

```
0001  20221124114030_create_status_reactions.rb
0001  20240411044156_add_reaction_count_to_status_stat.rb
0001  post_migrate/20250305023754_add_reaction_counts_to_status_stat.rb
0001  post_migrate/20260520184138_normalize_status_reaction_variation_selectors.rb
0002  20240114042123_create_bubble_domains.rb
0002  20251018223804_add_bubble_timeline_preview_setting.rb
0002  20251024193240_add_bubble_timeline_topic_preview_setting.rb
0004  20221218015350_fix_foreign_keys_status_reactions.rb
0004  20230215074425_move_emoji_reaction_settings.rb
0004  20250518031405_remove_quote_id_from_statuses.rb
```

## The container image

`ghcr.io/pegelinuxtop/fedi.my.id` is glitch-soc with this series applied, built by
`scripts/build-image.sh` from the tree's own `Dockerfile` (fork stages included).
The [`image` workflow](.github/workflows/image.yml) builds it on demand, weekly on
glitch-soc `main`, and whenever the patches change, tagging `latest`,
`glitch-<sha12>` and `patchset-<rev7>`. The same script builds it locally:

```sh
scripts/build-image.sh                       # pinned .base-commit, loaded locally
scripts/build-image.sh --glitch-ref main --push   # current glitch-soc, pushed
```

[docs/image.md](docs/image.md) covers the triggers and the tag scheme, the
first-time GHCR setup, multi-platform (arm64) builds, and how to run the image.

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
| the Ruby-side checks | `bin/rubocop`, `bin/haml-lint`, `bin/i18n-tasks …`, `bin/rails db:migrate` plus a `db:schema:dump` comparison, `bin/flatware rspec` — needs Ruby 4.0.7, PostgreSQL and Redis, see [docs/verification.md](docs/verification.md) |

Exact commands, expected output and the one check that could not be run here (a
browser session against a real server) are in
[docs/verification.md](docs/verification.md); the fork comparison is explained in
[docs/fork-comparison.md](docs/fork-comparison.md).

## Deviations from the fork

The tree is generated from a merge of the fork's pre-sync `dev`
(`fedi.my.id@dev` at `b416d280e0`, now the branch `backup-20261006`) onto the base
commit, so it is the fork's tree plus glitch-soc's evolution since the fork's last
glitch-soc merge. `dev` itself now holds exactly this tree, so these are the
intentional differences from that pre-sync branch:

1. **The fork's per-timeline boost/reply settings are now wired through fan-out**
   (`config/settings.yml`, `app/services/fan_out_on_write_service.rb`,
   `spec/services/fan_out_on_write_service_spec.rb`). In `dev` the four admin
   toggles (`show_reblogs/replies_in_{local,federated}_timelines`) only affected the
   REST timeline: `broadcastable?` still required the pre-rename
   `show_reblogs_in_public_timelines` (default `false` in `dev`'s `config/settings.yml`
   and exposed nowhere, so a boost reached the public streams only if a `settings`
   row happened to hold `true`), the reply toggle was never consulted (the
   corresponding expression in `broadcast_to_public_streams!` was a no-op), and
   `timeline:public:bubble` was published twice per bubble status. Now
   `config/settings.yml` carries the four split keys (default `false`),
   `broadcast_to_public_streams!` filters every channel with its own pair —
   `timeline:public:local` with `_local_`, and `timeline:public`,
   `timeline:public:remote`, `timeline:public:bubble` plus their `:media` variants
   with `_federated_` — and self-replies keep publishing. What to expect: boosts
   reach the public streams again when a toggle is on, non-self replies stop
   streaming when the reply toggle is off, and the mixed `timeline:public` follows
   the federated pair (so a local non-self reply can appear in the mixed timeline
   but not in the local one). Boosts still never reach hashtag streams or hashtag
   followers, because a local boost is stored as a tagless wrapper
   (`ReblogService` creates it with `text: ''` and no tags), so `@status.tags` is
   empty. The new spec contexts pass (`bin/flatware rspec
   spec/services/fan_out_on_write_service_spec.rb`); the first version of that block
   was missing a `let(:visibility)`, so it never ran — that is fixed.
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
6. **Lint/type fixes** so the repository's own checks pass. `dev` widens ESLint
   coverage by adding `files: ['**/*.js', '**/*.jsx', '**/*.ts', '**/*.tsx']` to
   the block that carries `ecmaVersion: 2021`, the TypeScript parser and the
   browser globals, so that the block applies to `.jsx` files as well. This patch
   set keeps that coverage — dropping `'**/*.jsx'` from the list makes `.jsx` files
   fall back to a lower `ecmaVersion` and they fail to parse (`Parsing error:
   Unexpected token =`, 14 files) — and fixes the findings instead:
   - `app/javascript/flavours/glitch/features/gif_modal/index.tsx` — dropped an
     inline `eslint-disable-next-line jsx-a11y/no-autofocus` that the rule being
     off makes redundant (`--report-unused-disable-directives`).
   - `app/javascript/flavours/glitch/features/ui/components/sign_in_banner.jsx`,
     `app/javascript/flavours/glitch/features/local_settings/navigation/item/index.jsx`
     and `app/javascript/flavours/glitch/features/notifications/components/pill_bar_button.jsx`
     — added `type='button'` (`react/button-has-type`); none of them is inside a
     form, so the default is only made explicit.
   - `app/javascript/{flavours/glitch,mastodon}/components/scrollable_list/index.jsx`
     and `app/javascript/{flavours/glitch,mastodon}/components/status/legacy/content.jsx`
     — replaced `@param {*}` / `@param {any}` with concrete jsdoc types
     (`jsdoc/reject-any-type`).
   - `eslint.config.mjs` — added `**/*.mjs` to that `files` list (without it the
     repository's own config file is parsed at the default `ecmaVersion` and fails
     on `import.meta`), restored glitch-soc's `mjs: 'never'` (`dev` had commented
     it out), and added an override turning `import/no-restricted-paths` off for
     `app/javascript/flavours/glitch/locales/*.js`, which exist to extend the
     vanilla locale JSON files.
7. **`app/javascript/mastodon/features/ui/index.jsx`** — kept glitch-soc's newer
   forms where `dev` still has the older ones: the named `{ BundleColumnError }`
   import (glitch-soc changed that module's export), the one-line
   `if (this.dataTransferIsText(e.dataTransfer)) return;` and the trailing
   `return;`. Semantically identical to `dev`'s variants.
8. **Two runtime fixes for code that glitch-soc has since changed** (both are forks
   of `dev`'s files that break against the current base commit):
   - `app/controllers/api/v1/custom_emojis_controller.rb` — `skip_before_action
     :require_authenticated_user!, unless: :whitelist_mode?` referred to a method
     glitch-soc renamed to `limited_federation_mode?` (`ApplicationController`
     exports the new name; `whitelist_mode?` is gone). Every request to
     `/api/v1/custom_emojis` raised `NoMethodError`; the rename restores the fork's
     intent (custom emojis stay public except in limited-federation mode). Caught
     by `spec/requests/cache_spec.rb`.
   - `lib/paperclip/qr_decoder.rb` — the rescue path called `log(...)`, which
     `Paperclip::Processor` does not define, so when the `qrtool` binary is missing
     the graceful degradation raised `NoMethodError` and killed media
     post-processing (17 media specs). It now uses `Rails.logger.warn`.
9. **Ruby/HAML/locale lint fixes** so `bin/rubocop`, `bin/haml-lint` and
   `bin/i18n-tasks` pass:
   - `lib/paperclip/qr_decoder.rb` — `[a, b].reject(&:blank?)` → `.compact_blank`
     (`Rails/CompactBlank`).
   - `app/views/admin/settings/other/show.html.haml` — the three
     `show_{reblogs,replies}_in_{local,federated}_timelines` inputs were 248
     characters on one line; they use the repo's multi-line `f.input` style now
     (`haml-lint` LineLength, max 240).
   - `config/locales-glitch/en.yml` — removed a duplicated
     `notification_mailer.reaction` block that `dev` carries twice, and
     `config/locales-glitch/simple_form.fr.yml` — sorted one key
     (`bin/i18n-tasks check-normalized`).
10. **Fixes to the fork's own specs**, all pre-existing in `dev`:
   - `spec/requests/api/v1/statuses/reactions_controller_spec.rb` — rewritten as a
     request spec using the real routes (`POST /api/v1/statuses/:status_id/react/:id`
     and `/unreact/:id`); it used to be written as a controller spec (`post :create`)
     under `spec/requests/`, which RSpec types as a request spec, and it called a
     `body_as_json` helper that no longer exists. The unreact examples need
     `:inline_jobs` because `UnreactWorker` removes the reaction asynchronously.
   - `spec/validators/status_reaction_validator_spec.rb`,
     `spec/workers/unreact_worker_spec.rb` — used bare `describe`, which
     `spec_helper`'s `disable_monkey_patching!` removed; the files could not load at
     all. Now `RSpec.describe`.
   - `spec/services/{react,unreact}_service_spec.rb` — the federation examples
     expected an inline delivery without the `:inline_jobs` tag the rest of the
     suite uses.
   - `spec/policies/status_policy_spec.rb` — `Fabricate(:react)` (no such
     fabricator; it is `:status_reaction`) and `react.target_account` (a
     `StatusReaction` has no `target_account`).
   - `spec/validators/status_reaction_validator_spec.rb` — called
     `status.reactions.build` / `.create!`; `Status#reactions` is a method returning
     an Array, the association is `status_reactions`.
   - `spec/models/notification_spec.rb` — added a reaction notification to the
     inputs without adding it to the `contain_exactly` expectation; it now has a
     `reaction_attributes` matcher.
11. **`/api/v1/custom_emojis` stays public when unauthenticated API access is
   disallowed** — that is the fork's behaviour, and it is now asserted instead of
   contradicted: `spec/requests/cache_spec.rb` (patch 5) expects a successful,
   non-publicly-cached response for that endpoint under
   `DISALLOW_UNAUTHENTICATED_API_ACCESS=true`, where upstream expects an error. The
   controller's `skip_before_action … unless: limited_federation_mode?` (deviation 8)
   is what implements it.
12. **Three upstream specs resolve their CSV fixtures explicitly** (patch 5):
   `spec/models/form/import_spec.rb` and
   `spec/controllers/admin/export_domain_blocks_controller_spec.rb` passed bare
   fixture names to `fixture_file_upload`, which prefers a path relative to the
   working directory when one exists — and this repository keeps the operator's
   `domain_blocks.csv` at its root (796 rows) next to the 3-row
   `spec/fixtures/files/domain_blocks.csv`. They now build the path from
   `file_fixture_path`, so the fixture always wins.

## Notes and caveats

Behaviour worth knowing before deploying this tree:

- **The bubble timeline only ever shows remote accounts.** A status is "in the
  bubble" when its author's domain is in `bubble_domains` (`Status#bubble?` →
  `BubbleDomain.in_bubble?` → `rule_for`), and `rule_for` returns `nil` for a
  blank domain, so local accounts can never be in the bubble. Fan-out matches
  that: `broadcast_to_public_streams!` publishes locals to
  `timeline:public:local` and remotes to `timeline:public:remote`,
  `timeline:public` and — only `if @status.bubble?` — `timeline:public:bubble`.
  The column is labelled accordingly ("posts from people … on other servers
  selected by {domain}"). A boost of a bubble-domain post is published by the
  booster's own status, so a local account that boosts a bubble post does not put
  it on the bubble timeline.
- **`show_*_in_{local,federated}_timelines` defaults to `false`, and older
  `settings` rows are ignored.** Upstream Mastodon once used
  `show_reblogs/replies_in_public_timelines`; a database migrated through those
  versions may still hold rows under those keys. They are no longer read. This
  changes nothing for a fresh install or one that kept the defaults (`dev`'s
  `config/settings.yml` also defaulted the old keys to `false`), but an install
  whose `settings` table has the old reblog key set to `true` used to stream boosts
  and will stop until the two new toggles are enabled in **Administration →
  Settings**.
- **Ruby-side checks: run, and green.** Ruby 4.0.7, PostgreSQL 18 and Redis are
  needed (see [docs/verification.md](docs/verification.md) for the exact commands);
  with them, `bin/rails db:migrate` from an empty database, a `db:schema:dump`
  comparison, `bin/rubocop`, `bin/haml-lint`, the `bin/i18n-tasks` set and
  `bin/flatware rspec` all run and pass: `db:schema.rb` is byte-identical to a fresh
  dump, the linters report nothing, and RSpec is 7934 examples with 0 failures
  (4 pending, upstream's own). Two `ActivityPub::ObjectIntegrityProof` ML-DSA
  examples depend on OpenSSL's post-quantum support and failed in one run and
  passed in another, so treat them as environment-dependent.

## Provenance

How this revision was produced (it is reproducible from the pre-sync `dev`, branch
`backup-20261006`, and the base commit):

1. `git merge` of `fedi.my.id@dev` (`b416d280e0`) onto
   `b3877d5b245c6fa65f1a7639fa5593c6b6ade8fc`
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
   touches, plus the lint fixes listed under Deviations, and the fixes to the
   fork's own specs (deviation 10);
5. the patches exported with `git format-patch`, and the checks in
   [docs/verification.md](docs/verification.md) run — including the Ruby-side
   checks, which need Ruby 4.0.7, PostgreSQL and Redis (deviation note above);
6. the series applied to glitch-soc `b3877d5b24` and merged into the fork as
   `dev` (commit `43e2b637c8`, tree `b473d8b76fe2fb8cd5084e3135a62ea923c2d126`,
   first parent the previous dev `b416d280e0`, kept as `backup-20261006`). The push
   was a fast-forward, and the comparison against the new `dev` reports the result
   byte-identical — the numbers in the next paragraph are the ones against the
   pre-sync fork.

Of the fork's 464 changed files, all 464 survive. Of the 421 files that only the
fork touches, 340 are byte-identical to the pre-sync `dev` and the other 81 are
fork-only deviations above (63 theme SCSS plus 18 code and spec files); 9 further
deviations are files neither the fork nor glitch-soc changed, which only the patch
set edits — the five lint/type fixes, the fan-out spec cases (deviation 1) and the
three specs of deviations 11–12. 806 paths in total differ from that pre-sync `dev`:
620 modified, 77 added and 19 removed by glitch-soc since the fork's last merge,
plus those 90 deviations.
The fork's own changes are in patches 1–4; patch 5 is the reconciliation layer on
top.
[docs/fork-comparison.md](docs/fork-comparison.md) has the full breakdown.
