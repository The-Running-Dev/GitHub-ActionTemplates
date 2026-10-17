# drift-report

Lists the repositories whose workflows use this library, the ref each one pins, and how far each
is behind the latest release. [`drift.yml`](../../docs/drift.md) runs it every week in this
repository.

```yaml
- uses: The-Running-Dev/GitHub-ActionTemplates/actions/drift-report@v1
  with:
    token: ${{ secrets.DRIFT_TOKEN }}
    report: drift-report.json
```

- Scans every repository of `owner` that is not archived or a fork, or the `repositories` list.
- Reads each `.github/workflows/*.yml` file on the default branch and finds the
  `uses: <library>/...@<ref>` lines, one row per workflow and ref.
- Resolves the ref to a commit: a tag of the library, a full commit SHA, or a branch.
- Writes the table to the job summary, a warning for each reference that is not current, and the
  JSON report when `report` is set.

| Status | Meaning |
|---|---|
| `current` | The ref is the latest `vX.Y.Z` release, or a tag or commit at the same commit (`v1`). |
| `behind` | An older release; the report gives the number of releases since. |
| `unreleased` | A commit that is not a release, such as a pre-release tag. |
| `branch` | A branch, which moves with every merge. |
| `unknown` | Not a tag, commit or branch of the library. |

The default `github.token` reads the public repositories of other owners and its own repository.
A user's private repositories are listed only for that user's own token; use a fine-grained token
with read access to the contents and metadata of every repository to scan.

## Inputs

| Name | Default | Description |
|---|---|---|
| `owner` | run's owner | User or organisation whose repositories are scanned. |
| `repositories` | | Repositories as owner/name, one per line, instead of every repository of `owner`. |
| `library` | the action's repository | Library repository as owner/name. |
| `token` | `github.token` | Token that can read the repositories and their contents. |
| `fail-on-drift` | `false` | `true` fails the step when a reference is not current. |
| `report` | | Path of the JSON report, relative to the workspace. |

## Outputs

| Name | Description |
|---|---|
| `latest` | Latest release of the library, e.g. `v1.2.0`. |
| `repositories` | Number of repositories scanned. |
| `references` | Number of workflow references to the library. |
| `current` | Number of references on the latest release. |
| `drifted` | Number of references that are not. |

## Report

```json
{
  "library": "The-Running-Dev/GitHub-ActionTemplates",
  "latest": "v0.7.1",
  "repositories": ["The-Running-Dev/SubZeroDev.Cleaner", "..."],
  "references": [
    {
      "repository": "The-Running-Dev/SubZeroDev.Cleaner",
      "workflow": ".github/workflows/ci.yml",
      "uses": [".github/workflows/dotnet.yml"],
      "ref": "v0",
      "sha": "9dd317bd904ad7a7c0b2cc5c735593fb0bddf756",
      "version": "v0.7.1",
      "behind": 0,
      "status": "current"
    }
  ],
  "unused": ["The-Running-Dev/WinUpdater"]
}
```

`unused` lists the repositories that have workflows but none of them use the library.
