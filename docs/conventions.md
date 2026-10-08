# Conventions

Rules every action and reusable workflow in this repository follows. A consumer who learns them
once can predict how any template behaves.

## Events and the publish decision

All templates derive the same facts from the run, through the shared module
`actions/_lib/Functions.psm1` (`Get-ActionContext`):

| Run | `is-pull-request` | `is-tag` | `is-default-branch` | `should-publish` |
|---|---|---|---|---|
| Pull request (`pull_request`, `pull_request_target`) | true | false | false | **false** |
| Push to the default branch | false | false | true | **true** |
| Push to another branch | false | false | false | **false** |
| Push of a tag | false | true | false | **true** |
| `workflow_dispatch` / `schedule` on the default branch | false | false | true | **true** |

- `branch` is the PR head branch for pull requests, the branch name for pushes, empty for tags.
- `ref-slug` is the branch or tag, lowercased, with every run of characters outside `[a-z0-9]`
  replaced by `-`, and cut to 63 characters. It is safe for image tags, DNS labels and
  environment names.
- The default branch comes from the event payload, not from a hard-coded `main`.

Templates publish only when `should-publish` is true. A caller that needs something different
(for example, publishing preview packages from a release branch) passes an explicit input; the
template does not guess.

## Versions

The `version` action has three strategies. All produce SemVer 2.0 without build metadata.

| Strategy | Tag build `v1.2.3` | Default branch, run 57 | Pull request #12, run 57 |
|---|---|---|---|
| `tag` (nearest `v*` tag is `v1.2.2`) | `1.2.3` | `1.2.3-ci.57` | `1.2.3-pr.12.57` |
| `manifest` (manifest says `1.2.3`) | `1.2.3`, fails if the tag differs | `1.2.3-ci.57` | `1.2.3-pr.12.57` |
| `run-number` (`base-version: '1.2'`) | `1.2.3` (the tag) | `1.2.57` | `1.2.57-pr.12` |

- `tag`: after a stable tag, builds are prereleases of the next patch. After a prerelease tag
  (`v1.3.0-rc.1`) they stay on `1.3.0`. With no tags at all the base is `0.0.0`, so the first
  build is `0.0.1-ci.<run>`. Needs `fetch-depth: 0` (the action warns on a shallow clone).
- `manifest`: reads `package.json`, `Directory.Build.props`, a single `*.csproj`, a single `*.psd1`,
  `Cargo.toml`, `pyproject.toml` or `VERSION`, in that order. When the manifest version already
  has a prerelease part, the CI suffix is appended with a dot (`2.0.0-rc.1.ci.57`).
- `run-number`: stable on the default branch, `-ci` on other branches, `-pr.<n>` on pull requests.
  Use it for things that are deployed rather than released.

The release tag is always the version with the `tag-prefix` (default `v`) in front.

## Inputs and outputs

- Names are kebab-case: `working-directory`, `tag-prefix`.
- Booleans are the strings `'true'` and `'false'`; outputs use the same spelling.
- Every input has a default that works for the common case. A template never requires an input
  that it could work out from the run.
- Paths are relative to `working-directory`, which defaults to `.`.
- `workflow_call` inputs have no object type. Maps and lists are JSON strings, read with
  `fromJSON`.
- Secrets are declared by name on `workflow_call` and documented. Templates do not rely on
  `secrets: inherit`, which only works inside one owner.

## Writing actions

- An action is `actions/<name>/action.yml` plus `<name>.ps1`, run with `shell: pwsh` as
  `& (Join-Path $env:GITHUB_ACTION_PATH <name>.ps1)`.
- Composite actions get no `INPUT_*` variables, so `action.yml` maps each input explicitly:
  `INPUT_TAG_PREFIX: ${{ inputs.tag-prefix }}`. Scripts read them with `Get-ActionInput`.
- Scripts write outputs with `Set-ActionOutput` and a short step summary with
  `Add-ActionSummary`. Errors are thrown, which fails the step with the message.
- Shared logic belongs in `actions/_lib/Functions.psm1` and is covered by `tests/`.
- Actions and workflows in this repository reference each other with `uses: $/...`.

## Security rules

- `permissions: {}` at the top of every workflow; each job lists its own permissions.
- Third-party actions are pinned to a full commit SHA with the version in a trailing comment.
- `actions/checkout` always sets `persist-credentials: false`, unless the job pushes.
- No `${{ }}` expression inside `run:`. Values reach scripts through `env:`.
- No `pull_request_target` with a checkout of the PR head.
- Anything printed is assumed public. Secrets are only passed to the step that needs them.
- actionlint, zizmor and PSScriptAnalyzer run on every pull request and must pass.
