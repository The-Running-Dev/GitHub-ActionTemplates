# image-push

Tags a local image with every reference and pushes them, reports the digest, and can sign the
digest with cosign. With `digest` instead of `source` it skips the push and only signs and
reports, for an image Buildx already pushed. Log in to the registry first.
[`container.yml`](../../docs/container.md) pushes the image its build job tested.

```yaml
- uses: docker/login-action@dbcb813823bdd20940b903addbd779551569679f # v4.6.0
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ github.token }}

- uses: sigstore/cosign-installer@6f9f17788090df1f26f669e9d70d6ae9567deba6 # v4.1.2

- id: push
  uses: The-Running-Dev/GitHub-ActionTemplates/actions/image-push@v1
  with:
    source: ${{ steps.load.outputs.image }}
    tags: ${{ steps.meta.outputs.tags }}
    sign: true
```

- All tags must name one repository; the digest belongs to it.
- Signing is keyless: the job needs `id-token: write`, and the signature is stored next to the
  image in the registry.
- Per-layer push progress is left out of the log.

## Inputs

| Name | Default | Description |
|---|---|---|
| `source` | | Local image to push. |
| `tags` | | References to push (`registry/owner/name:tag`), one per line. Required. |
| `digest` | | Digest of an image already pushed under `tags`, instead of `source`. |
| `sign` | `false` | Sign the digest with cosign, keyless. Needs cosign on the PATH. |

## Outputs

| Name | Description |
|---|---|
| `image` | Repository, without a tag. |
| `digest` | Pushed digest (`sha256:…`). |
| `reference` | `image@digest`. |
| `tags` | References that were pushed, one per line. |
