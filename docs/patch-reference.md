# Patch reference

The series in `series` applies bottom-up on `.base-commit`:

```
b3877d5b24 (glitch-soc main)
  └─ 0001-feature-reaction-list.patch        97 files   +2391 /  −92
      └─ 0002-feature-bubble-timeline.patch  60 files   +1474 /  −83
          └─ 0003-feature-gif-picker.patch   31 files    +891 /  −21
              └─ 0004-fedi-branding-themes.patch 273 files +49717 / −112
                  └─ 0005-fedi-compat-overlay.patch 11 files +45 / −3
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
  material icons, glitch UI (`actions/interactions.js`, `reducers/status_reactions.js`,
  `components/status/legacy/reactions.tsx`, `features/reactions/index.tsx`,
  `features/notifications_v2/components/notification_reaction.tsx`, …), and specs.
- **Migrations**: `20221124114030_create_status_reactions`,
  `20240411044156_add_reaction_count_to_status_stat`.
- **Also touches**: `config/routes/api.rb`, `config/locales-glitch/en.yml`,
  `config/locales-glitch/simple_form.en.yml`, `app/models/notification.rb`,
  `app/models/concerns/account/associations.rb`,
  `app/services/delete_account_service.rb`, the instance serializers, and the
  status/action-bar components in both flavours.
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
  `app/controllers/api/v1/timelines/public_controller.rb`, `app/models/account.rb`
  (the `bubble_only` scope), the glitch firehose/compose/navigation/hashtag
  components, `config/routes/admin.rb`, `config/routes/web_app.rb`,
  `config/navigation.rb`, `config/locales/en.yml`.
- **Carries shared configuration**: `config/settings.yml` (bubble feed access,
  `show_bubble_domains`, `visible_reactions`, `reject_pattern`, `reject_blurhash`,
  and the four `show_{reblogs,replies}_in_{local,federated}_timelines` keys),
  `db/schema.rb` (bubble and reaction tables), `app/models/form/admin_settings.rb`,
  `config/locales/en.yml`, `app/views/admin/settings/discovery/show.html.haml`.
- **Also carries the fork's fan-out wiring** (README deviation 1):
  `broadcast_to_public_stream` applies each channel's own
  `show_{reblogs,replies}_in_{local,federated}_timelines` pair, self-replies keep
  publishing, and `broadcastable?` no longer tests the pre-rename reblog setting.
  `spec/services/fan_out_on_write_service_spec.rb` gains the cases for it. This is
  the only patch that touches `app/services/fan_out_on_write_service.rb`, so a
  conflict in fan-out lands here.

## 0003 — `feature/gif-picker`

TheEssem's GIF search. 16 new files, 15 modified.

- **New**: `app/lib/gif_service.rb` + `gif_service/{tenor,klipy}.rb`,
  `app/services/search_gifs_service.rb`, `app/lib/gif_results.rb` (models),
  `app/serializers/rest/gif_results_serializer.rb`,
  `app/controllers/api/v1/gifs_controller.rb`, `config/gifs.yml`, the Tenor/Klipy
  SVG marks in `public/`, glitch `features/gif_modal/*` and models/types, specs.
- **Also touches**: `config/routes/api.rb`, `config/application.rb`,
  `config/locales-glitch/en.yml`, `app/javascript/flavours/glitch/locales/en.json`,
  `app/serializers/rest/instance_serializer.rb`,
  `app/javascript/flavours/glitch/features/ui/components/modal_root.jsx`.
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
- the sign-in banner (`features/ui/components/sign_in_banner.jsx`), footers, the
  local-settings page, About page, and the theme-related React glue.
- **Migrations**: `20221218015350_fix_foreign_keys_status_reactions`,
  `20230215074425_move_emoji_reaction_settings`,
  `20250518031405_remove_quote_id_from_statuses`.
- **Also touches**: 65 modified files, of which three are theme SCSS
  (`styles/custom_common.scss`, `styles/modern.scss`, …) covered above. The rest:
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
  `app/javascript/flavours/glitch/locales/{de,fr}.js`, the qrtool files
  (`config/initializers/qrtool.rb`, `lib/paperclip/qr_decoder.rb`),
  `.stylelintignore`, `domain_blocks.csv` and the skin `names.yml` files are among
  the 208 *new* files.
  Note what is *not* here: `Dockerfile` and `eslint.config.mjs` are 0005, and
  `streaming/index.js` and `app/models/account.rb` are 0002 — glitch-soc changed
  those files too, so their fork hunks live in the reconciliation patch.

## 0005 — `fedi/compat-overlay`

Where glitch-soc's evolution since the fork's merge point had to be re-applied to a
file the fork also changes, plus the lint/type fixes for files the fork does not
touch at all. Eleven modified files, no new ones:

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
   reports separately).

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
- `streaming/index.js` and `app/models/account.rb` also belong to **0002** for the
  same reason (glitch-soc changed them, so they are not part of 0004).
