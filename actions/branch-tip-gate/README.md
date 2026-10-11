# branch-tip-gate

Decides whether a branch build may still publish, by comparing its commit with the branch head.
When two pushes land close together, the older run can finish last and overwrite `latest` with
the older image; this gate stops it. Tag builds always pass: a tag points at one commit for good.
[`container.yml`](../../docs/container.md) runs it first in its publish job.

```yaml
- id: tip
  uses: The-Running-Dev/GitHub-ActionTemplates/actions/branch-tip-gate@v0
  with:
    require-tip: latest

- if: steps.tip.outputs.publish == 'true'
  uses: The-Running-Dev/GitHub-ActionTemplates/actions/image-meta@v0
  with:
    image: ghcr.io/${{ github.repository }}
    latest: ${{ steps.tip.outputs.latest }}
```

| `require-tip` | Tip | Not the tip |
|---|---|---|
| `all` | publish, `latest` | nothing (a notice says which commit is newer) |
| `latest` | publish, `latest` | publish without `latest` |
| `none` | publish, `latest` | publish, `latest` (not checked) |

The head is read with `gh api repos/<repository>/branches/<branch>`; the token needs read
access to the repository's contents.

## Inputs

| Name | Default | Description |
|---|---|---|
| `require-tip` | `all` | `all`, `latest` or `none`. |
| `sha` | run's commit | Commit that was built. |
| `branch` | run's branch | Branch to compare with; pull requests use the head branch, tag builds have none. |
| `repository` | run's repository | `owner/name`. |
| `token` | `github.token` | Token that can read the repository. |

## Outputs

| Name | Description |
|---|---|
| `is-tip` | `true` when the commit is the branch head, or the build is not for a branch. |
| `head` | Branch head commit. |
| `publish` | `true` when the build may publish. |
| `latest` | `true` when the build may move `latest`. |
