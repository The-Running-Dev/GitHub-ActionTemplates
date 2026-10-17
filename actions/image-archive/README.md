# image-archive

Hands a built image from one job to another, so the job that pushes pushes the image that was
tested rather than a rebuild. `save` writes the image and its ID to a folder; `load` loads it
and fails unless the ID still matches. [`container.yml`](../../docs/container.md) saves in its
build job and loads in its publish job.

```yaml
# Build job
- uses: The-Running-Dev/GitHub-ActionTemplates/actions/image-archive@v1
  with:
    image: app:${{ github.sha }}
    path: ${{ runner.temp }}/image

- uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
  with:
    name: image
    path: ${{ runner.temp }}/image
    retention-days: 1

# Publish job
- uses: actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333 # v8.0.2
  with:
    name: image
    path: ${{ runner.temp }}/image

- id: load
  uses: The-Running-Dev/GitHub-ActionTemplates/actions/image-archive@v1
  with:
    mode: load
    path: ${{ runner.temp }}/image
```

The folder holds `image.tar` (`docker save`) and `image.json` (reference and ID).

## Inputs

| Name | Default | Description |
|---|---|---|
| `mode` | `save` | `save` or `load`. |
| `image` | | Reference to save. On `load`, when set, the archive must hold this reference. |
| `path` | `$RUNNER_TEMP/ghat-image` | Folder for `image.tar` and `image.json`. |

## Outputs

| Name | Description |
|---|---|
| `image` | Reference that was saved or loaded. |
| `id` | Image ID (`sha256:…`). |
| `path` | Full path of the folder. |
