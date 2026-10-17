# drift.yml

Reports, every Monday, the ref each repository of the owner pins this library at, so a repository
left on an old release or a branch is noticed before the next major version.

It runs in this repository only: [`drift-report`](../actions/drift-report/README.md) scans every
repository of `The-Running-Dev` that is not archived or a fork, writes the table to the run's
summary with a warning for each reference that is not on the latest release, and uploads the
JSON report as the `drift-report` artifact for 30 days. Run it at any time from **Actions → Drift
→ Run workflow**.

| Repository | Workflow | Uses | Ref | Version | Status |
|---|---|---|---|---|---|
| The-Running-Dev/SubZeroDev.Cleaner | `.github/workflows/ci.yml` | `.github/workflows/dotnet.yml` | `v0` | v0.7.1 | current |
| The-Running-Dev/SubZeroDev.Old | `.github/workflows/ci.yml` | `.github/workflows/node-ci.yml` | `v0.5.0` | v0.5.0 | behind 3 |

## Token

The `DRIFT_TOKEN` secret, when it is set, is the token. Without it, `github.token` reads only
public repositories, because a user's private repositories are listed for that user's own token.
Use a fine-grained token owned by `The-Running-Dev` with **Contents: read** (metadata is
included) on all repositories.

## Notes

- Only workflow files (`.github/workflows/*.yml`) on each repository's default branch are read.
  A composite action in a consumer that uses the library is not counted.
- `@v1` is current while `v1` is on the latest release. A repository still on `@v0` stays on
  0.8.4 and is reported `behind`.
- The step does not fail on drift. Another repository can run the action with
  `fail-on-drift: true` and a `repositories` list to enforce it.
