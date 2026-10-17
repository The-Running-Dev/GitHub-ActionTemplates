# image-meta

Works out an image's tags and OCI labels from the run. You pick tag kinds; the action turns
them into full references, and keeps `latest` to the builds that should move it.
[`container.yml`](../../docs/container.md) uses it for the labels in its build job and for the
tags in its publish job.

```yaml
- id: meta
  uses: The-Running-Dev/GitHub-ActionTemplates/actions/image-meta@v1
  with:
    image: ghcr.io/${{ github.repository }}
    tags: short-sha version minor major latest
    version: ${{ steps.version.outputs.version }}

- run: ./scripts/Show-Tags.ps1
  shell: pwsh
  env:
    TAGS: ${{ steps.meta.outputs.tags }}
```

| Kind | Tag | Notes |
|---|---|---|
| `sha` | full commit SHA | |
| `short-sha` | first 7 characters | |
| `version` | `1.2.3` | Needs the `version` input. |
| `minor` | `1.2` | Needs `version`; stable versions only. |
| `major` | `1` | Needs `version`; stable versions only. |
| `date` | `20261011` | UTC. |
| `branch` | branch slug | `feature/Add-Thing` becomes `feature-add-thing`; pull requests use the head branch. |
| `latest` | `latest` | Default-branch builds and stable tag builds only, and not when `latest` is `false`. |

- The image name is lowercased; registries reject upper case.
- Labels: `org.opencontainers.image.source`, `revision`, `created` and `version` (the version,
  else the SHA). `labels` adds more and overrides these by key.

## Inputs

| Name | Default | Description |
|---|---|---|
| `image` | | Image name without a tag, for example `ghcr.io/owner/name`. Required. |
| `tags` | `sha latest` | Tag kinds, separated by spaces or commas. |
| `version` | | Version for `version`, `minor`, `major` and the version label. |
| `latest` | `true` | `false` withholds `latest` even when the run would get it. |
| `tag-prefix` | `v` | Prefix of release tags. Without `version`, a tag build is stable when its tag, less the prefix, has no prerelease part. |
| `labels` | | Extra labels, `key=value`, one per line. |

## Outputs

| Name | Description |
|---|---|
| `image` | Lowercased image name. |
| `tags` | Full references (`image:tag`), one per line. |
| `tag-names` | Tag names only, separated by spaces. |
| `labels` | Labels, `key=value`, one per line. |
| `latest` | `true` when the tags include `latest`. |
