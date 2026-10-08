# docs-build

Builds a Docusaurus documentation site. Most repositories call the
[`docs.yml`](../../docs/docs.md) workflow, which runs this action in the right container and
deploys the result; use the action directly only inside your own job.

Two builders:

- **`template`** (default): merges the documentation folder into a Docusaurus template and runs
  `build node-template` from the [build-agent image](https://github.com/The-Running-Dev/Docker-BuildAgent),
  so the job must run in that container. Files in the folder win over the template's, so a
  folder can be just `docs/*.md` or bring its own `docusaurus.config.ts`, `sidebars.ts` and `src/`.
- **`node`**: the folder is a complete Node project. The action installs its dependencies
  (`npm ci`, `pnpm install --frozen-lockfile` or `yarn install`) and runs one package.json
  script. Works on any runner with Node.

```yaml
- uses: actions/checkout@v7
  with:
    persist-credentials: false

- id: docs
  uses: The-Running-Dev/GitHub-ActionTemplates/actions/docs-build@v0
  with:
    source: docs

- uses: actions/upload-pages-artifact@v5
  with:
    path: ${{ steps.docs.outputs.path }}
```

## The bundled template

The default template is in [`template/`](template): Docusaurus 3 with the classic preset,
Mermaid diagrams, local search, docs served from the site root and a sidebar generated from
the folder structure. It has no organisation-specific content. Without a config of its own the
site is set up from the environment:

| Setting | Default | Override |
|---|---|---|
| Title | repository name | `DOCS_TITLE` |
| URL | `https://<owner>.github.io` | `DOCS_URL` |
| Base URL | `/<repository>/`, or `/` for `<owner>.github.io` | `DOCS_BASE_URL` |
| Repository link | `https://github.com/<owner>/<repository>` | `DOCS_REPOSITORY_URL` |
| Tagline | empty | `DOCS_TAGLINE` |

`docs.yml` sets `DOCS_URL` and `DOCS_BASE_URL` from the repository's Pages settings when it
deploys, so custom domains work without configuration.

Dependencies are installed from the template's `pnpm-lock.yaml`. A folder that brings its own
`package.json` replaces the template's and no longer matches that lockfile; use the `node`
builder for those.

## Inputs

| Name | Default | Description |
|---|---|---|
| `source` | `docs` | Documentation folder, relative to the workspace. |
| `builder` | `template` | `template` or `node`. |
| `template` | bundled | Template git URL for the `template` builder, optionally `<url>#<branch>`. |
| `package-manager` | from the lockfile | `npm`, `pnpm` or `yarn`. |
| `build-command` | `build` | package.json script the `node` builder runs. |
| `output` | `<source>/build` | Folder the site ends up in. The `template` builder moves its site here; the `node` builder must write it here. The action fails if it has no `index.html`. |

`source` and `output` must be inside the workspace.

## Outputs

| Name | Example | Description |
|---|---|---|
| `path` | `docs/build` | Built site folder, relative to the workspace. |
