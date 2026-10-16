# pages-env

Exports the GitHub Pages address of the repository, and build variables from the caller, to the
rest of the job. [`pages.yml`](../../docs/pages.md) runs it before the build.

```yaml
- uses: The-Running-Dev/GitHub-ActionTemplates/actions/pages-env@v0
  with:
    env: VITE_API_URL=${{ vars.API_URL }}
    secret-env: VITE_KEY=${{ secrets.KEY }}

- run: npm run build # vite.config.ts uses process.env.PAGES_BASE_PATH
```

| Variable | Example |
|---|---|
| `PAGES_URL` | `https://octo-org.github.io/app/` |
| `PAGES_ORIGIN` | `https://octo-org.github.io` |
| `PAGES_BASE_PATH` | `/app/` |

The address is read with `gh api repos/<repository>/pages`, so a custom domain is picked up;
that needs the `pages: read` permission. When Pages is not set up yet, or the token cannot read
it, the default `https://<owner>.github.io/<repository>/` is used (`/` for an
`<owner>.github.io` repository).

`env` and `secret-env` take `KEY=value` lines; blank lines and `#` comments are skipped. Each
`secret-env` value is masked before it is exported, and a malformed line is reported by its
number only. `GITHUB_*`, `RUNNER_*`, `ACTIONS_*`, `PATH`, `CI`, `NODE_OPTIONS` and the `PAGES_*`
names are reserved.

## Inputs

| Name | Default | Description |
|---|---|---|
| `base-path` | from the Pages settings | Path the site is served under, e.g. `/my-site/`. |
| `env` | | Build variables as `KEY=value`, one per line. |
| `secret-env` | | Like `env`, each value masked. |
| `repository` | run's repository | `owner/name`. |
| `token` | `github.token` | Token that can read the Pages settings. |

## Outputs

| Name | Description |
|---|---|
| `url` | Site URL with a trailing slash. |
| `origin` | Scheme and host, without a trailing slash. |
| `base-path` | Path with leading and trailing slashes. |
