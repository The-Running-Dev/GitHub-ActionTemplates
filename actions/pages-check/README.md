# pages-check

Checks a built static site before it is uploaded to GitHub Pages, and adds a `404.html` fallback
for single-page apps. [`pages.yml`](../../docs/pages.md) runs it after the build.

```yaml
- id: site
  uses: The-Running-Dev/GitHub-ActionTemplates/actions/pages-check@v0
  with:
    path: dist
    spa: true

- uses: actions/upload-pages-artifact@v5
  with:
    path: ${{ steps.site.outputs.path }}
```

- Fails when the folder is missing, empty or outside the workspace.
- Warns when there is no `index.html`, or the site is over the 1 GB Pages limit.
- With `spa: true`, copies `index.html` to `404.html` unless the site has its own, so a deep
  link such as `/app/users/7` loads the app and its router.
- Writes the file count and size to the job summary.

## Inputs

| Name | Default | Description |
|---|---|---|
| `path` | | Built site folder, relative to `working-directory`. |
| `working-directory` | workspace | Folder `path` is relative to. |
| `spa` | `false` | `true` adds the `404.html` fallback. |

## Outputs

| Name | Description |
|---|---|
| `path` | Site folder, relative to the workspace. |
| `files` | Number of files. |
| `size` | Size in bytes. |
