# groovescript/chart-action

A GitHub Action that compiles [GrooveScript](https://github.com/groovescript/groovescript) `.gs` drum charts to PDF on pull requests and commits the rendered output back onto the PR branch — enabling sheet-music review from the GitHub iOS app before merging.

## Quick start

Create `.github/workflows/render-charts.yml` in your chart repo:

```yaml
name: Render charts

on:
  pull_request:
    paths:
      - "**/*.gs"

jobs:
  render:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: read
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.ref }}
          repository: ${{ github.event.pull_request.head.repo.full_name }}
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}

      - uses: groovescript/chart-action@v0
```

That's it. When you open a PR that touches a `.gs` file, the action
compiles the changed charts and commits the `.pdf` (and `.ly`) back
onto your PR branch. Open the PDF in the GitHub iOS app to review the
score before merging.

## How it works

1. **Change detection** — finds `.gs` files added or modified in the PR
   (relative to the base branch).
2. **Compile** — runs `groovescript compile` then `lilypond` for each file.
3. **Commit** — pushes a bot commit with the `.ly` and `.pdf` back onto
   the PR branch. The commit uses the `github-actions[bot]` identity
   so no personal access token is needed.

## Inputs

| Input | Default | Description |
|---|---|---|
| `groovescript-version` | `latest` | Git ref (tag, branch, SHA) of `groovescript/groovescript` to install. |
| `lilypond-version` | `2.24.3` | LilyPond version to install. Cached after the first run. |
| `paths` | `**/*.gs` | Newline-separated glob(s) of `.gs` files to consider. |
| `only-changed` | `true` | Compile only PR-changed files. Set to `false` to recompile everything. |
| `commit-ly` | `true` | Commit the intermediate `.ly` alongside the `.pdf`. |
| `commit-message` | `Re-render charts` | Prefix for the render commit message. |
| `fail-on-error` | `true` | Fail the workflow if any `.gs` fails to compile. No render commit is made when this triggers. Set to `false` for partial progress. |
| `working-directory` | `.` | Restrict the action to a subdirectory of the repo. |

## Performance

| Run | Time |
|---|---|
| Cold (LilyPond not cached) | ~60–90 s |
| Warm (LilyPond cached) | ~5–10 s |

LilyPond is cached in `/opt/lilypond` keyed on `lilypond-version` and
`runner.os`. The cache warms on the first run and hits on every
subsequent PR in the same repo.

## Pinning

```yaml
# Automatically get non-breaking updates:
- uses: groovescript/chart-action@v0

# Fully reproducible:
- uses: groovescript/chart-action@v0.1.0
```

## Limitations

### Fork PRs

The default `GITHUB_TOKEN` has read-only access to a fork's branch,
so the commit-back step will fail for PRs opened from forks. This is
fine for private personal chart repos (no forks). For public repos
that want fork rendering, use `pull_request_target` with strict path
filtering — but be aware that this runs the action with privileged
token access on untrusted code, which is a security risk if any shell
inputs are derived from PR contents.

### PDF size

PDFs are small (~30–80 KB per chart) but do accumulate over time.
`git lfs` is available if repo size ever becomes a concern.

## Examples

See [`examples/`](examples/) for copy-pasteable workflow files.

## License

MIT — see [LICENSE](LICENSE).
