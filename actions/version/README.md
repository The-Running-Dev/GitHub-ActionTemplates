# version

Computes a semantic version for the build from git tags, a project manifest, or the run number.
The rules are in [docs/conventions.md](../../docs/conventions.md#versions).

```yaml
- uses: actions/checkout@v7
  with:
    fetch-depth: 0
    persist-credentials: false

- id: version
  uses: The-Running-Dev/GitHub-ActionTemplates/actions/version@v0
  with:
    strategy: manifest # tag | manifest | run-number

- run: dotnet pack -p:Version="$VERSION"
  env:
    VERSION: ${{ steps.version.outputs.version }}
```

## Inputs

| Name | Default | Description |
|---|---|---|
| `strategy` | `tag` | `tag`: nearest `v*` tag, next patch as a prerelease. `manifest`: the version in the project manifest. `run-number`: `base-version` plus the run number. |
| `manifest` | auto-detected | Manifest path relative to `working-directory` (`manifest` strategy). |
| `base-version` | | `Major.Minor` for the `run-number` strategy, for example `1.0`. |
| `tag-prefix` | `v` | Prefix of release tags. |
| `prerelease-label` | `ci` | Prerelease label for builds that are not tag builds. |
| `pr-label` | `pr` | Prerelease label for pull request builds. |
| `working-directory` | `.` | Directory with the git checkout and manifest. |

## Outputs

| Name | Example | Description |
|---|---|---|
| `version` | `1.2.4-ci.57` | Full semantic version. |
| `major` / `minor` / `patch` | `1` / `2` / `4` | Version components. |
| `prerelease` | `ci.57` | Prerelease part without the dash; empty for stable versions. |
| `is-prerelease` | `true` | Whether the version has a prerelease part. |
| `is-release` | `false` | Whether the build runs for a tag. |
| `tag` | `v1.2.4-ci.57` | The version with the tag prefix. |

## Failures

- A tag build whose tag does not start with `tag-prefix`.
- `manifest` strategy on a tag build when the manifest version differs from the tag.
- `run-number` strategy without a `Major.Minor` `base-version`.
- A label containing characters other than `[0-9A-Za-z-]` and dots.
