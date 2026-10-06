# Patch reference

The series in `series` applies bottom-up on `.base-commit`:

```
b3877d5b24 (glitch-soc main)
  └─ 0001-feature-reaction-list.patch        97 files   +2391 /  −92
      └─ 0002-feature-bubble-timeline.patch  60 files   +1476 /  −83
          └─ 0003-feature-gif-picker.patch   31 files    +886 /  −21
              └─ 0004-fedi-branding-themes.patch 273 files +49748 / −113
                  └─ 0005-fedi-compat-overlay.patch 14 files +74 / −10
```

The patches are cumulative: sizes are relative to the previous patch, not to the
base commit. Only the full series produces a usable tree (see Dependencies).

## 0001 — `feature/reaction-list`

TheEssem's emoji reactions, rebased onto the base commit. 32 new files, 65
modified.

- **New**: `app/controllers/api/v1/statuses/reactions_controller.rb`,
  `app/models/status_reaction.rb`, `app/services/react_service.rb` /
  `unreact_service.rb`, `app/workers/unreact_worker.rb`,
  `app/serializers/rest/status_reaction_serializer.rb`,
  `app/serializers/activitypub/{emoji_reaction,undo_emoji_reaction}_serializer.rb`,
  `app/validators/status_reaction_validator.rb`,
  `app/presenters/status_reaction_presenter.rb`, notification-mailer views,
  material icons, glitch UI (`reducers/status_reactions.js`,
  `components/status/legacy/reactions.tsx`, `features/reactions/index.tsx`,
  `features/notifications_v2/components/notification_reaction.tsx`,
  `api_types/reaction.ts`, `models/reaction.ts`, …), and specs.
- **Migrations**: `20221124114030_create_status_reactions`,
  `20240411044156_add_reaction_count_to_status_stat`, and the two post-migrations
  `post_migrate/20250305023754_add_reaction_counts_to_status_stat`,
  `post_migrate/20260520184138_normalize_status_reaction_variation_selectors`.
- **Also touches**: `config/routes/api.rb`, `config/locales-glitch/en.yml`,
  `config/locales-glitch/simple_form.en.yml`, `.env.production.sample`,
  `app/models/notification.rb`, `app/models/status.rb`,
  `app/models/concerns/account/associations.rb`,
  `app/models/concerns/account/interactions.rb`,
  `app/services/delete_account_service.rb`, the instance serializers, the
  notification serializers/models/settings (glitch and vanilla), glitch
  `actions/interactions.js` (the react/unreact actions) and the status/action-bar
  components in both flavours.
- **Carries shared configuration**: no (`config/settings.yml`, `db/schema.rb` and
  `app/models/form/admin_settings.rb` are carried by 0002; see Ownership).

## 0002 — `feature/bubble-timeline`

TheEssem's bubble timeline, plus the fork's per-timeline boost/reply settings. 21 new
files, 39 modified.

- **New**: `app/controllers/admin/bubble_domains_controller.rb`,
  `app/controllers/api/v1/instances/bubble_domains_controller.rb`,
  `app/models/bubble_domain.rb`, `app/policies/bubble_domain_policy.rb`,
  `lib/mastodon/cli/bubble_domains.rb`, admin views for bubble domains, glitch
  `features/bubble_timeline/*`, specs.
- **Migrations**: `20240114042123_create_bubble_domains`,
  `20251018223804_add_bubble_timeline_preview_setting`,
  `20251024193240_add_bubble_timeline_topic_preview_setting`.
- **Also touches**: `streaming/index.js` (bubble channels, bubble feed access and
  the bubble-domain filter), `app/services/fan_out_on_write_service.rb`,
  `app/services/batched_remove_status_service.rb`,
  `app/services/remove_status_service.rb`,
  `app/controllers/api/v1/timelines/{public,topic}_controller.rb`,
  `app/models/account.rb` (the `bubble_only` scope), the feed scopes
  (`app/models/{public,tag,link}_feed.rb`), the glitch
  firehose/about/compose/navigation/hashtag components and the streaming
  actions/reducers, `config/routes/admin.rb`, `config/routes/web_app.rb`,
  `config/navigation.rb`, `config/locales/en.yml`, `lib/mastodon/cli/main.rb`.
- **Carries shared configuration**: `config/settings.yml` (bubble feed access,
  `show_bubble_domains`, `visible_reactions`, `reject_pattern`, `reject_blurhash`,
  and the four `show_{reblogs,replies}_in_{local,federated}_timelines` keys),
  `db/schema.rb` (bubble and reaction tables), `app/models/form/admin_settings.rb`,
  `config/locales/en.yml`, `app/views/admin/settings/discovery/show.html.haml`.
- **Also carries the fork's fan-out wiring** (README deviation 1):
  `broadcast_to_public_stream` applies each channel's own
  `show_{reblogs,replies}_in_{local,federated}_timelines` pair, self-replies keep
  publishing, and `broadcastable?` no longer tests the pre-rename reblog setting.
  `spec/services/fan_out_on_write_service_spec.rb` gains the cases for it (plus the
  `let(:visibility)` the first version of those cases was missing, so they actually
  run). This is the only patch that touches
  `app/services/fan_out_on_write_service.rb`, so a conflict in fan-out lands here.

## 0003 — `feature/gif-picker`

TheEssem's GIF search. 16 new files, 15 modified.

- **New**: `app/lib/gif_service.rb` + `gif_service/{tenor,klipy}.rb`,
  `app/services/search_gifs_service.rb`, `app/models/gif_results.rb`,
  `app/serializers/rest/gif_results_serializer.rb`,
  `app/controllers/api/v1/gifs_controller.rb`, `config/gifs.yml`, the Tenor/Klipy
  SVG marks in `public/` and the glitch `features/gif_modal/*` components,
  `api_types/gif.ts` and `models/gif.ts`. No new specs.
- **Also touches**: `config/routes/api.rb`, `config/application.rb`,
  `config/locales-glitch/en.yml`,
  `app/javascript/flavours/glitch/locales/en.json`,
  `app/serializers/rest/instance_serializer.rb`,
  `app/lib/content_security_policy.rb`,
  `app/javascript/{flavours/glitch,mastodon}/features/ui/components/modal_root.jsx`,
  the glitch compose upload button (`features/compose/components/upload_button.jsx`,
  `containers/upload_button_container.js`, `actions/compose.js`,
  `reducers/compose.js`), `api_types/instance.ts` and
  `app/javascript/flavours/glitch/styles/mastodon/components.scss`.
  In `config/locales-glitch/en.yml` this patch also *is* the one that normalises the
  file: it inserts the `gif:` block where `bin/i18n-tasks check-normalized` wants it
  (before `notification_mailer`, not after `settings`), and it does not re-add the
  `notification_mailer.reaction` block that `dev` carries twice (patch 1 already adds
  it once).
- **Carries shared configuration**: no.

## 0004 — `fedi/branding-themes`

The operator's own customisations. 208 new files, 65 modified — almost all of them
SCSS themes and skins:

- `app/javascript/flavours/glitch/styles/**` and `app/javascript/styles/**`:
  modern, gekka, gekka-modern, holiday, holiday-modern, light-modern, rose-pine,
  rose-pine-modern, sakura, sakura-modern, yozakura, yozakura-modern, birdsite,
  contrast-modern, tangerineui (+ cherry/purple), `custom_common.scss`,
  `modern-glitch-fixes.scss`, `modern-urusai-fixes.scss`, `urusai-fixes.scss`;
- matching skins under `app/javascript/skins/{glitch,vanilla}/**` (`common.scss`,
  `names.yml`);
- the sign-in banner (`features/ui/components/sign_in_banner.jsx`), the
  local-settings page (`features/local_settings/page/**`) and the theme-related
  React glue (both flavours' `icon_button`, `timeline_hint`,
  `autosuggest_textarea`, `compose_form`, `notification_*`, `status/legacy`,
  `compare_history_modal`, …; the fork's other new components are under "Also
  adds"). The About page and the footers are *not* here — glitch-soc changed
  `features/about/index.jsx` (0002) and both `link_footer.tsx` (0005).
- **Migrations**: `20221218015350_fix_foreign_keys_status_reactions`,
  `20230215074425_move_emoji_reaction_settings`,
  `20250518031405_remove_quote_id_from_statuses`.
- **Also touches**: 65 modified files. Three of them are SCSS glitch-soc already
  had and the fork tweaks
  (`app/javascript/flavours/glitch/styles/mastodon/glitch/doodle.scss`,
  `app/javascript/styles/mastodon/admin.scss`,
  `app/javascript/styles/mastodon/rtl.scss`). The rest:
  `Gemfile.lock` (bundler platforms), `stylelint.config.js`, `README.md`,
  `.gitignore`, the two `.github/workflows/` files, the icon PNGs under
  `app/javascript/icons/`, `config/environments/production.rb`,
  `config/initializers/content_security_policy.rb`,
  `config/locales-glitch/simple_form.fr.yml`, `streaming/database.js`,
  `streaming/redis.js`, `app/lib/feed_manager.rb`, `app/models/media_attachment.rb`,
  `lib/exceptions.rb`, `lib/sanitize_ext/sanitize_config.rb`, the admin
  `app/views/admin/{dashboard/index,settings/other/show}.html.haml`, the fork's
  Ruby specs (`spec/**`), and the React glue it rebrands (both flavours'
  `icon_button`, `timeline_hint`, `autosuggest_textarea`, `compose_form`,
  `notification_*` and `status/legacy` components, glitch
  `local_settings/page/**`, `compare_history_modal`, …).
- **Also adds** the 208 new files: the theme SCSS (163 of them, under
  `app/javascript/flavours/glitch/styles/**` and `app/javascript/styles/**`), the
  skins' `names.yml` / `common.scss`, the fork's own code
  (`app/javascript/flavours/glitch/features/ui/components/sign_in_banner.jsx`, the
  glitch locale overlays `app/javascript/flavours/glitch/locales/{de,fr}.js`,
  `app/javascript/flavours/glitch/components/status_reactions.tsx`,
  `features/explore/components/author_link.jsx` in both flavours,
  `features/ui/util/identity_consumer.jsx`, `app/javascript/styles/birdsite.css`,
  `config/initializers/qrtool.rb`, `lib/paperclip/qr_decoder.rb`,
  `app/validators/regexp_syntax_validator.rb`,
  `app/workers/scheduler/admin/dashboard_cache_warmer_scheduler.rb`,
  `.stylelintignore`, `domain_blocks.csv`), its new Ruby specs (`spec/**`) and the
  three migrations below.
- **Also fixes** (README deviations 8–10, all pre-existing in `dev`):
  `app/controllers/api/v1/custom_emojis_controller.rb` (`whitelist_mode?` →
  `limited_federation_mode?`, the name glitch-soc kept), `lib/paperclip/qr_decoder.rb`
  (`log(...)` → `Rails.logger.warn(...)` and `reject(&:blank?)` → `compact_blank`),
  `app/views/admin/settings/other/show.html.haml` (three over-long `f.input` lines
  wrapped), `config/locales-glitch/simple_form.fr.yml` (key order), and the fork's
  specs `spec/requests/api/v1/statuses/reactions_controller_spec.rb`,
  `spec/validators/status_reaction_validator_spec.rb`,
  `spec/workers/unreact_worker_spec.rb` (`RSpec.describe`),
  `spec/services/{react,unreact}_service_spec.rb` (`:inline_jobs`),
  `spec/policies/status_policy_spec.rb` (`Fabricate(:status_reaction)`) and
  `spec/models/notification_spec.rb` (reaction expectation);
  `spec/requests/api/v1/statuses/reactions_controller_spec.rb` is additionally
  rewritten as a request spec on the real routes.
  Note what is *not* here: `Dockerfile` and `eslint.config.mjs` are 0005, and
  `streaming/index.js` and `app/models/account.rb` are 0002 — glitch-soc changed
  those files too (except `streaming/index.js`, which 0002 owns for its bubble
  channels), so their fork hunks live in another patch.

## 0005 — `fedi/compat-overlay`

Where glitch-soc's evolution since the fork's merge point had to be re-applied to a
file the fork also changes, plus the fixes for files the fork does not touch at all.
Fourteen modified files, no new ones:

| File | Change |
|---|---|
| `Dockerfile` | the fork's `qrtool` build stage, re-applied on glitch-soc's newer Dockerfile |
| `app/javascript/{flavours/glitch,}/features/ui/components/link_footer.tsx` | the fork's "Alternative UI (Elk)" list item, kept alongside glitch-soc's now-conditional About item |
| `app/javascript/mastodon/locales/en.json` | `notification.reaction` |
| `config/locales/ja.yml` | `reject_blurhash` / `reject_pattern` strings |
| `eslint.config.mjs` | the fork's lint configuration on glitch-soc's newer config (keeps the widened `files:` coverage, restores `mjs: 'never'`, relaxes `import/no-restricted-paths` for the glitch locale overlays) |
| `app/javascript/flavours/glitch/components/scrollable_list/index.jsx`, `app/javascript/mastodon/components/scrollable_list/index.jsx` | `jsdoc/reject-any-type`: `@param {*} props` → `@param {{ scrollKey: string }} props` |
| `app/javascript/mastodon/components/status/legacy/content.jsx` | `jsdoc/reject-any-type`: `@param {any} status` → `@param {import('immutable').Map<string, unknown>} status` |
| `app/javascript/flavours/glitch/features/local_settings/navigation/item/index.jsx`, `app/javascript/flavours/glitch/features/notifications/components/pill_bar_button.jsx` | `react/button-has-type`: added the explicit `type='button'` |
| `spec/requests/cache_spec.rb` | under `DISALLOW_UNAUTHENTICATED_API_ACCESS`, `/api/v1/custom_emojis` succeeds in this fork instead of erroring (README deviation 11), so the expectation for that endpoint says so |
| `spec/models/form/import_spec.rb`, `spec/controllers/admin/export_domain_blocks_controller_spec.rb` | build CSV fixture paths from `file_fixture_path` so the fork's root-level `domain_blocks.csv` cannot shadow `spec/fixtures/files/domain_blocks.csv` (README deviation 12) |

The remaining three lint fixes are folded into the patch that owns the file:
`features/gif_modal/index.tsx` (0003, dropped the now-unused inline
`jsx-a11y/no-autofocus` disable) and `sign_in_banner.jsx` plus
`flavours/glitch/components/status/legacy/content.jsx` (0004, `type='button'` and a
typed parameter).

## Ownership

When the series was assembled, every file in the merge result was assigned to one
patch, by these rules:

1. the **last patch that already touched the file** keeps it, so a change lands in
   the patch whose content the file's final state comes from;
2. files no patch touched (shared configuration) are assigned by hand: bubble and
   reaction model/config/schema files to 0002, the rest to 0004;
3. five files receive hunks from two patches (0001 then 0003) — they are additive
   and the series applies cleanly;
4. files the fork never touches, edited only to satisfy the repository's own
   linters, go to **0005** (they are among the 6 deviations the fork comparison
   reports separately);
5. later fixes found by running the checks (the runtime renames, lint findings and
   broken specs of README deviations 8–12) stay in the patch that already owns the
   file, even where the file is a fork-only one; if the fork does not touch the file
   at all, the fix goes to **0005**.

Consequences worth knowing when rebasing:

- conflicts in the reaction API/services/UI land in **0001**
  (`app/controllers/api/v1/statuses/reactions_controller.rb`,
  `app/services/{react,unreact}_service.rb`, glitch
  `actions/interactions.js`, `components/status/legacy/reactions.tsx`, the
  notification components);
- conflicts in `config/settings.yml`, `db/schema.rb`,
  `app/models/form/admin_settings.rb`, `config/locales/en.yml`,
  `config/routes/admin.rb`, `db/migrate/*`,
  `app/services/fan_out_on_write_service.rb`,
  `app/controllers/api/v1/timelines/public_controller.rb` and the fan-out specs
  land in **0002**;
- conflicts in the GIF service, `config/gifs.yml`, `config/routes/api.rb` and the
  glitch GIF modal land in **0003**;
- conflicts in theme SCSS, `Gemfile.lock`, `streaming/database.js`,
  `streaming/redis.js`, the glitch locale overlays (`locales/{de,fr}.js`),
  `stylelint.config.js`, the fork's specs and helpers land in **0004**;
- conflicts in `Dockerfile`, the two `link_footer.tsx` files,
  `mastodon/locales/en.json`, `config/locales/ja.yml`, `eslint.config.mjs` and the
  five lint-fix files land in **0005** — `Dockerfile`, `eslint.config.mjs` and
  both `link_footer.tsx` are files glitch-soc also changed, which is why their
  fork hunks cannot live in 0004;
- `app/models/account.rb` and `streaming/index.js` are **0002** as well: `account.rb`
  carries the bubble `bubble_only` scope and glitch-soc changed the file too, and
  `streaming/index.js` holds the bubble channels and the bubble-domain filter,
  which is why 0002 owns those hunks rather than 0004.
