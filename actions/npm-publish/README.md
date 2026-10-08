# npm-publish

Publishes a packed npm tarball to npmjs or GitHub Packages. The package name and version are
read from the tarball, so the published package is exactly the file that was built and
tested. Prereleases go to the `next` dist-tag, so `npm install <name>` keeps getting the
latest stable version.

```yaml
permissions:
  contents: read
  id-token: write # provenance and trusted publishing

steps:
  - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0
    with:
      node-version: lts/*

  - uses: The-Running-Dev/GitHub-ActionTemplates/actions/npm-publish@v0
    with:
      tarball: dist-package/*.tgz
```

## Authentication

| Registry | `token` | Set up |
|---|---|---|
| npmjs, trusted publishing | empty | On npmjs.com, add the repository and the **calling** workflow file as a trusted publisher. Needs npm 11.5.1+ and `id-token: write`. |
| npmjs, token | an automation token secret | Store the token as a repository secret. |
| GitHub Packages | `${{ github.token }}` | The job needs `packages: write`. The package name must be scoped to the repository owner. |

The token never appears on the command line or in a file: npm reads it from the
`NODE_AUTH_TOKEN` environment variable through a temporary user config that is deleted
after the publish.

- `provenance` links the package to the run that built it. npmjs only; it is turned off with a
  notice for GitHub Packages. It needs `id-token: write` and a public repository.
- The registry must be `https://`.

## Inputs

| Name | Default | Description |
|---|---|---|
| `tarball` | required | Tarball to publish, relative to the workspace. Wildcards must match exactly one file. |
| `registry` | `https://registry.npmjs.org` | Registry URL. `https://npm.pkg.github.com` publishes to GitHub Packages. |
| `token` | | Registry token. Empty uses npm trusted publishing (OIDC). |
| `access` | | `public` or `restricted`. Empty uses the package.json `publishConfig` or the npm default. |
| `provenance` | `true` | Publish with a provenance statement (npmjs only). |
| `dist-tag` | | dist-tag to publish under. Empty uses `next` for prereleases and `latest` otherwise. |
| `dry-run` | `false` | Run `npm publish --dry-run`. |

## Outputs

| Name | Description |
|---|---|
| `name` / `version` | Package name and version, read from the tarball. |
| `dist-tag` | dist-tag the package was published under. |
| `published` | `true` when the package was published; `false` for a dry run. |
