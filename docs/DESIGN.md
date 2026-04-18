# Chart Action — Design

Compile GrooveScript `.gs` files to PDF on pull requests and commit
the rendered output back onto the PR branch so it can be reviewed from
the GitHub iOS app before merging.

## Motivating workflow

A drummer keeps a private repo of `.gs` charts (transcriptions, original
grooves, personal practice material). Editing on a phone is fine —
pasting from the web editor, or editing directly in the GitHub mobile
app — but *reviewing* the resulting sheet music requires a rendered
PDF. The author opens a PR to change a chart, the action renders, the
rendered PDF lands on the PR branch, the author opens it in the iOS
GitHub app, scrolls through the score, and merges (or pushes fixes).

There is no LilyPond on iOS and no desire to run a server. GitHub
Actions is the render target; the PR is the review surface.

## Design decisions

- **Delivery**: bot commits the rendered `.pdf` (and the intermediate
  `.ly`) back onto the PR branch alongside the `.gs`. Shows up in
  "Files changed"; iOS app renders PDFs natively when tapped.
- **Hosting**: dedicated public repo `groovescript/chart-action`, so
  users reference `uses: groovescript/chart-action@v1` and don't have
  to pull the whole compiler repo at a pinned tag. Moving `v1` tag +
  immutable `v1.0.0` tag per release.
- **Packaging**: composite action (YAML steps) with `actions/cache`
  keyed on a LilyPond version string, so a cold run installs LilyPond
  once (~60-90 s) and subsequent PR runs in the same repo hit the
  cache (~2-5 s). No Docker image publishing infrastructure needed.
- **Outputs**: PDF only, produced via `groovescript compile` →
  `lilypond`. The `.ly` is an intermediate that gets committed
  alongside the PDF to match the repo convention and aid debugging.
  MIDI / MusicXML left as future inputs (see "Extensions").

## Repository layout

```
action.yml                  # Composite action definition
scripts/
  compile-changed.sh        # Detect changed .gs files, compile each
  install-lilypond.sh       # Install (or restore from cache) lilypond
  commit-artifacts.sh       # Stage .ly/.pdf, commit, push to PR branch
README.md                   # User-facing usage + example workflow
docs/
  DESIGN.md                 # This document
.github/workflows/
  self-test.yml             # Dogfood: run the action on a test fixture PR
  release.yml               # Tag v1.x.y → move v1
examples/
  minimal-workflow.yml      # Copy-pasteable example for consumers
  all-options.yml           # Every input documented
  fixture.gs                # Minimal chart used by self-test
LICENSE                     # MIT
```

## Key implementation details

### Change detection

`scripts/compile-changed.sh` uses `git diff --name-only --diff-filter=AM
origin/${BASE_REF}...HEAD -- '*.gs'` intersected with `inputs.paths`
globs. Deleted `.gs` files aren't recompiled but their matching
`.ly`/`.pdf` are removed in the same render commit (handled by
`commit-artifacts.sh` checking for orphaned pairs).

### Compile step

For each selected `.gs`:

```
groovescript compile "$gs" -o "${gs%.gs}.ly"
lilypond -o "${gs%.gs}" "${gs%.gs}.ly"
```

Run serially (charts are small; parallelism complicates error
aggregation). Capture stderr per file and re-emit as
`::error file=<path>,line=<n>::<msg>` annotations so errors surface
inline in the PR "Files changed" view.

### Commit step

- Identity: `github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>`
  (the well-known bot identity — no PAT needed)
- Message: `${COMMIT_MESSAGE}: file-a.gs, file-b.gs\n\n[skip ci]`
- Push with `git push origin HEAD:${HEAD_REF}`
- If nothing changed (e.g., all compiled files byte-identical to
  what's already committed), skip the commit entirely so we don't
  pollute history with empty commits.

### Loop prevention

Pushes made with the default `GITHUB_TOKEN` do **not** trigger other
workflow runs — this is GitHub's built-in safeguard. We rely on it
rather than on `[skip ci]` tags. The tag is included anyway as
belt-and-braces in case a user swaps in a PAT.

### Fork PRs

For the primary use case (private personal chart repo), fork PRs are
irrelevant. For public chart repos where external contributors may
open PRs from forks, the default `GITHUB_TOKEN` has read-only access
to the fork's branch and the commit step will fail cleanly. See README
for the `pull_request_target` workaround and its security implications.

### LilyPond caching

Install LilyPond to `/opt/lilypond` (user-owned, cacheable — not
`/usr/*` which `actions/cache` can't round-trip). Cache key:
`lilypond-${{ runner.os }}-${{ inputs.lilypond-version }}`.
Hit rate will be ~100 % once warm, since the key only changes when the
consumer explicitly bumps `lilypond-version`.

Using the official upstream tarball (not `apt-get install lilypond`)
gives a pinnable version across runners and a self-contained tree.

## Error UX

- Per-file compile/render errors → GitHub annotations, which show up
  inline in the PR "Files changed" diff.
- If any file fails and `fail-on-error=true` (default), the workflow
  step fails with a summary. No render commit is made (all-or-nothing).
- If `fail-on-error=false`, failed files are skipped, successful ones
  are committed. Useful for consumers who want partial progress
  during heavy refactors.

## Extensions (not in v1)

- `midi: true` / `musicxml: true` inputs producing additional outputs
  via `groovescript midi` / `groovescript musicxml`
- Optional PR comment summarising which files were (re-)rendered, with
  direct links to each `.pdf`'s blob URL on the PR head.
- macOS and Windows runner support (LilyPond tarballs exist for both;
  cache key already includes `runner.os`).
- `lint-only: true` mode that runs `groovescript lint` and fails on
  diagnostics without attempting to render.

## Release process

1. Land PR on `main` in `groovescript/chart-action`.
2. Tag `v0.1.0` (immutable) — `release.yml` force-moves `v0` automatically.
3. Write release notes against the immutable tag.
4. Promote to `v1.0.0` + `v1` after a period of dogfooding.

Consumers pin to `@v0` (or `@v1`) for automatic non-breaking updates,
or to `@v0.1.0` for reproducibility.
