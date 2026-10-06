# How the result relates to the fork

`scripts/compare-with-fork.sh` answers "is this still my fork?" and is meant to be
run after every rebase.

```sh
scripts/compare-with-fork.sh --result ~/src/fedi.my.id \
  [--fork ~/Workspace/mastodon/fedi.my.id] [--fork-ref origin/dev] [--all]
```

Defaults: `--result` is `build/` if `setup.sh` put it there and the current
directory otherwise; `--fork` is the sibling `fedi.my.id` checkout of this
repository; `--fork-ref` is `origin/dev`, then `dev`. A bare name also matches
`origin/<name>`, so `--fork-ref backup-20261006` works on a clone that only has that
branch as a remote-tracking ref.

## Which fork ref to compare against

`fedi.my.id@dev` was rebuilt from this series on 2026-10-06: commit `43e2b637c8`,
whose second parent is the series and whose tree is the verified build tree
`b473d8b76fe2fb8cd5084e3135a62ea923c2d126`, pushed as a fast-forward over the
previous dev `b416d280e0` (kept as the branch `backup-20261006`). The default
`--fork-ref origin/dev` therefore compares the result with itself — a **mirror
check**: 0 differing paths, all 470 fork changes present, all 470 fork-only files
byte-identical. To reproduce the analysis below, compare against the fork as it was
before the sync:

```sh
scripts/compare-with-fork.sh --result ~/src/fedi.my.id --fork-ref backup-20261006
```

## Why it cannot be byte-identical (against the pre-sync fork)

The patch set is the fork **rebased onto a newer glitch-soc**. The pre-sync
`fedi.my.id@dev` (`backup-20261006`) is based on glitch-soc `64e05b4b2e`; this
series targets `b3877d5b24`. Everything glitch-soc changed in between is therefore
newer in the result, and files that both sides touched necessarily differ from that
`dev` in their bytes. What must hold instead is:

- every file the fork changed since its merge point still differs from that
  pre-fork baseline (customisation present), and
- every difference between the result and `dev` is explained by glitch-soc's own
  evolution or is a deviation documented in the README.

## What the script does

1. Fetches `--fork-ref` from the fork clone into the result checkout as
   `refs/patchset-compare/fork` (removed again unless `--keep-ref`).
2. `MERGE_POINT=$(git merge-base .base-commit <fork-ref>)` — the fork's last
   glitch-soc merge, `64e05b4b2e` for the current revision.
3. Builds four path sets, all with rename detection off so that a rename counts as
   a deletion plus an addition (unambiguous classification):
   - `MERGE_POINT → base`: files glitch-soc changed;
   - `MERGE_POINT → fork`: files the fork changed;
   - fork-only = the difference;
   - `MERGE_POINT → result` and `fork → result`: what actually differs.
4. Reports:
   - **preservation** — fork-changed files that are *identical* to the pre-fork
     baseline are lost customisations and make the script exit 1 (a file glitch-soc
     deleted still counts as differing, so upstream deletions are not mistaken for
     lost changes);
   - **fork-only files** — how many are byte-identical to the fork, and which
     differ;
   - **result vs fork** — every differing path classified as modified/added/removed
     by glitch-soc, or as a deviation;
   - **warnings** — a file the fork customised that glitch-soc removed or renamed
     (the rename is reported with its new name), and deviations in files *neither*
     side changed, i.e. edits the patch set introduces itself (the lint fixes and
     the new fan-out specs); a deviation inside a file glitch-soc did change is
     invisible here, because the path is attributed to glitch-soc.

Exit status 0 means: nothing lost, no path differs for an unexplained reason.

## Current numbers

### Mirror check — against `dev`

`.base-commit` `b3877d5b24`, fork `origin/dev` `43e2b637c8`. Because `dev` *is* the
result, the merge point is the base commit itself and the two trees are identical:

```
==> Inputs
  result     : ~/src/fedi.my.id (43e2b637c8)
  fork       : fedi.my.id (origin/dev 43e2b637c8)
  base       : b3877d5b24 (glitch-soc)
  merge point: b3877d5b24 (the fork's last glitch-soc merge)

==> Fork changes preserved (fork relative to its merge point)
  files the fork changed since the merge point : 470
  still differing in the result                : 470
  ok    no fork change was silently dropped

==> Fork-only files (glitch-soc did not touch them)
  count                      : 470
  byte-identical to the fork : 470
  differing                  : 0

==> Result vs fork
  differing paths in total              : 0
  modified by glitch-soc since the merge: 0
  added by glitch-soc                   : 0
  removed by glitch-soc                 : 0
  deviations (not glitch-soc-driven)    : 0
```

`470` is the file count of the series itself (the README's "470 files changed"):
because the merge point *is* the base commit, glitch-soc contributes no differences
of its own, so every path is classified as fork-side — and all of it is
byte-identical to `dev`. That makes this run a cheap way to prove a rebuild still
reproduces the branch, but it says nothing about the fork's customisations versus
glitch-soc, because both sides of the comparison moved together. Use the run below
for that.

### Against the pre-sync fork — `--fork-ref backup-20261006`

For `.base-commit` `b3877d5b24`, fork `backup-20261006` `b416d280e0`, merge point
`64e05b4b2e` (refresh these after a rebase):

```
==> Fork changes preserved (fork relative to its merge point)
  files the fork changed since the merge point : 464
  still differing in the result                : 464
  ok    no fork change was silently dropped

==> Fork-only files (glitch-soc did not touch them)
  count                      : 421
  byte-identical to the fork : 340
  differing                  : 81        (63 theme SCSS + 18 code, see README)

==> Result vs fork
  differing paths in total              : 806
  modified by glitch-soc since the merge: 620
  added by glitch-soc                   : 77
  removed by glitch-soc                 : 19
  deviations (not glitch-soc-driven)    : 90
  warn  the fork customised config/vite/plugin-sw-locales.ts, which glitch-soc
        renamed to config/vite/plugin-sw-locales.mts (see Deviations in README.md)
  warn  9 deviation(s) are in files the fork does not change — patch-set
        additions, check they are intentional
```

Read it as: 806 paths differ from `dev`; 716 of them are glitch-soc's own work
(620 modified, 77 added, 19 removed, renames counted as both), and 90 are
deviations documented in the README — 81 in files only the fork touches, plus 9 in
files neither the fork nor glitch-soc changed, which only the patch set edits. The 9
are the five lint/type fixes (`flavours/glitch/components/scrollable_list/index.jsx`,
`flavours/glitch/features/local_settings/navigation/item/index.jsx`,
`flavours/glitch/features/notifications/components/pill_bar_button.jsx`,
`mastodon/components/scrollable_list/index.jsx`,
`mastodon/components/status/legacy/content.jsx`),
`spec/services/fan_out_on_write_service_spec.rb` (the fan-out spec cases, README
deviation 1), and the three upstream specs the fork's behaviour and its root-level
`domain_blocks.csv` forced us to adjust (`spec/requests/cache_spec.rb`,
`spec/models/form/import_spec.rb`,
`spec/controllers/admin/export_domain_blocks_controller_spec.rb`; deviations
11–12).

The 81 fork-only deviations are 63 theme SCSS files (formatter normalisation, README
deviation 5) plus 18 code, test and locale files: the fan-out service (deviation 1),
`flavours/glitch/initial_state.ts` (2), `streaming/index.js` (3), the two files of
deviation 8 (`api/v1/custom_emojis_controller.rb`, `lib/paperclip/qr_decoder.rb`),
the three of deviation 9 (`app/views/admin/settings/other/show.html.haml`,
`config/locales-glitch/en.yml`, `config/locales-glitch/simple_form.fr.yml`), the
seven specs of deviation 10 (`spec/models/notification_spec.rb`,
`spec/policies/status_policy_spec.rb`,
`spec/requests/api/v1/statuses/reactions_controller_spec.rb`,
`spec/services/{react,unreact}_service_spec.rb`,
`spec/validators/status_reaction_validator_spec.rb`,
`spec/workers/unreact_worker_spec.rb`) and three lint fixes in files the fork does
not otherwise share with glitch-soc
(`flavours/glitch/components/status/legacy/content.jsx`,
`features/gif_modal/index.tsx`, `features/ui/components/sign_in_banner.jsx`).

Two things are worth knowing about the counting:

- renames inflate the added/removed figures (a rename is one deletion plus one
  addition); the current revision has 11 renamed files, hence 19 removed instead of
  8;
- the 8 files that exist in `dev` and not in the result are all composer-redesign
  files glitch-soc deleted (`containers/compose_container.jsx`,
  `features/compose/util/counter.js`,
  `features/notifications/components/clear_column_button.jsx`,
  `features/standalone/compose/index.jsx`, in both flavours). The fork never
  customised them, so nothing was lost — the script checks that and warns only if a
  customised file goes missing.

## Limitations

- Classification is per file. A cosmetic deviation *inside* a file that glitch-soc
  also changed is invisible to it — for example the dropped whitespace-only line in
  `autosuggest_textarea.jsx` (README deviation 4) or the `eslint.config.mjs` edits
  that glitch-soc also touched — both are therefore counted as glitch-soc
  modifications rather than deviations. There are 43 files that both sides changed;
  their merge was reviewed by hand for the 8 that conflicted and auto-merged for the
  rest, and the preservation check (464/464) is the safety net that matters: it
  proves the fork's change to each of those files is still present.
- It compares commits, not the working tree, so it is unaffected by local edits.
- It cannot compare against what is running on fedi.my.id, only against a branch
  that exists in your clone: `dev` by default, or `backup-20261006` for the fork as
  it was before the 2026-10-06 sync. Fetch before you compare.
- The numbers move whenever `dev`, the base commit or the deviations change; treat
  them as a report of the current revision, not as constants.

## What to do with a finding

| Output | Meaning | Action |
|---|---|---|
| `FAIL n fork change(s) are identical to the pre-fork baseline` | that many customisations are missing from the result | the merge dropped them; re-apply the fork's change to those files and re-export (`docs/updating.md`) |
| `FAIL n path(s) differ from the fork for no glitch-soc reason` | a path was added or removed without glitch-soc doing it | investigate the patch set; it usually means a hand-edit or a bad merge resolution |
| `warn … renamed to …` | the fork customised a file glitch-soc renamed | confirm the tweak is either carried over by hand or listed as a deviation |
| `warn n deviation(s) are in files the fork does not change` | edits the patch set introduces itself (lint fixes, added specs) | confirm each is intentional and documented; these are the only deviations with no fork counterpart to compare against |
| a deviation that is not in the README | undocumented behaviour difference | either revert it or document it under "Deviations" |
