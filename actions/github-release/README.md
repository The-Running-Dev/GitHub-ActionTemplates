# github-release

Creates the GitHub release for a tag, or updates it when it already exists, with the notes
from the tag's `CHANGELOG.md` section and the given files attached. Running it again for the
same tag replaces the notes and overwrites attachments with the same name, so a re-run of a
release workflow does not fail.

```yaml
permissions:
  contents: write

steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    with:
      persist-credentials: false

  - uses: The-Running-Dev/GitHub-ActionTemplates/actions/github-release@v0
    with:
      files: dist/*.zip
```

- Notes: when the CHANGELOG exists, its `## [x.y.z]` section for the tag's version (the tag
  without `tag-prefix`) is required, and a missing or empty section fails the step before
  anything is published. Without a CHANGELOG, GitHub generates the notes from the merged pull
  requests.
- `prerelease: auto` marks `v1.2.0-rc.1` and other versions with a prerelease part as
  prereleases.
- The release is created with `--verify-tag`, so the tag must already be pushed.
- Every file pattern must match at least one file, checked before anything is published.

## Inputs

| Name | Default | Description |
|---|---|---|
| `tag` | the current tag | Release tag. Fails outside a tag build when empty. |
| `files` | | Files to attach, relative to the workspace, one per line. Wildcards are allowed and `**/` searches folders. |
| `changelog` | `CHANGELOG.md` | CHANGELOG file, relative to the workspace. |
| `tag-prefix` | `v` | Prefix stripped from the tag to find the CHANGELOG version. |
| `title` | the tag | Release title. |
| `prerelease` | `auto` | `true`, `false`, or `auto`. |
| `draft` | `false` | Create a draft release. |
| `token` | `github.token` | Token for the GitHub CLI; needs `contents: write`. |

## Outputs

| Name | Description |
|---|---|
| `url` | Release page URL. |
| `created` | `true` when the release was created, `false` when an existing one was updated. |
