# changelog

Writes a Markdown changelog page from the git history: one entry per commit, newest first,
with a link to the pull request when the subject ends in `(#123)`. Made for repositories that
squash-merge every pull request, where each commit on the default branch is one change.
[`docs.yml`](../../docs/docs.md) runs it before the build when its `changelog` input is set.

```yaml
- uses: actions/checkout@v7
  with:
    fetch-depth: 0
    persist-credentials: false

- uses: The-Running-Dev/GitHub-ActionTemplates/actions/changelog@v0
  with:
    path: docs/docs/CHANGELOG.md
    front-matter: |
      slug: changelog
      sidebar_position: 99
```

The page is written into the workspace only; nothing is committed. The checkout needs the full
history (`fetch-depth: 0`): the action fails on a shallow one rather than write a partial page.

An entry looks like this:

```markdown
- **2026-10-08** — [feat: add the docs workflow (#5)](https://github.com/owner/repo/pull/5)
```

`<`, `>`, `[`, `]` and `\` in subjects are escaped, so the page is safe for MDX.

## Inputs

| Name | Default | Description |
|---|---|---|
| `path` | required | Page to write, relative to the workspace. |
| `front-matter` | none | Front matter, one `key: value` per line, without the `---` fences. |
| `title` | `Changelog` | Page heading. |
| `ref` | `HEAD` | Commit or branch whose history is listed. |
| `exclude` | `(?i)update changelog` | Regular expression; matching subjects are left out. |
| `repository` | current repository | `owner/repo` for pull request links. |

## Outputs

| Name | Example | Description |
|---|---|---|
| `entries` | `42` | Number of entries written. |
