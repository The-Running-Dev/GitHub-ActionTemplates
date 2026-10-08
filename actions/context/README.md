# context

Turns the run context into plain outputs so later steps and jobs do not repeat
`github.event_name == 'pull_request' || ...` expressions. The rules are in
[docs/conventions.md](../../docs/conventions.md#events-and-the-publish-decision).

```yaml
- id: context
  uses: The-Running-Dev/GitHub-ActionTemplates/actions/context@v0

- if: steps.context.outputs.should-publish == 'true'
  run: docker push "$IMAGE:$SHORT_SHA"
  env:
    IMAGE: ${{ steps.context.outputs.image }}
    SHORT_SHA: ${{ steps.context.outputs.short-sha }}
```

## Inputs

| Name | Default | Description |
|---|---|---|
| `registry` | `ghcr.io` | Registry host for the `image` output. Empty for Docker Hub. |
| `image-name` | repository name | Image name under the owner. |

## Outputs

| Name | Example | Description |
|---|---|---|
| `owner` | `octo-org` | Repository owner, lowercased. |
| `repository` | `Sample.Repo` | Repository name without the owner. |
| `sha` / `short-sha` | `0123456…` / `0123456` | Commit SHA, full and 7 characters. |
| `event` | `push` | Triggering event. |
| `ref-name` | `main`, `v1.2.3`, `12/merge` | Short ref name. |
| `branch` | `feature/login` | Source branch (PR head for pull requests); empty for tags. |
| `ref-slug` | `feature-login` | Branch or tag as a lowercase `[a-z0-9-]` slug, at most 63 characters. |
| `default-branch` | `main` | Repository default branch. |
| `is-pull-request` | `false` | `pull_request` or `pull_request_target`. |
| `is-tag` | `false` | The build runs for a tag. |
| `is-default-branch` | `true` | The build runs for the default branch (never for a pull request). |
| `should-publish` | `true` | Tag or default-branch build. |
| `image` | `ghcr.io/octo-org/sample.repo` | Lowercased `<registry>/<owner>/<image-name>`. |
