# node-scripts

Installs a Node project and runs its package.json scripts in order, after building the local
projects it depends on. [`docs.yml`](../../docs/docs.md) runs it after the documentation build
when its `node-project` input is set, for a site project that checks or merges the built docs.

```yaml
- uses: The-Running-Dev/GitHub-ActionTemplates/actions/node-scripts@v0
  with:
    path: site
    scripts: check merge
    dependencies: src/engine
    browser: true
```

1. Each folder in `dependencies` is installed and its `build` script run, in order. Use it for
   `file:` dependencies that must be built before the project installs them.
2. Each script in `setup` runs with `npm run` before the project is installed, for a script that
   vendors local packages or generates files the install needs.
3. The project is installed and each script in `scripts` runs in order. The first failure fails
   the step.

Installs use the lockfile: `npm ci` (or `npm install` without a lockfile),
`pnpm install --frozen-lockfile` or `yarn install`. The package manager is detected per folder
from its lockfile unless `package-manager` is set. When pnpm or yarn is not installed, it runs
`corepack enable` first.

## Browser tests

`browser: true` finds a system Chromium or Chrome and exposes it to the scripts as
`PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH`, `PUPPETEER_EXECUTABLE_PATH`, `CHROME_BIN` and `CHROME_PATH`.
It looks on `PATH` (`chromium`, `chromium-browser`, `google-chrome-stable`, `google-chrome`,
`chrome`), then in the install folders Windows and macOS use (`Google\Chrome\Application\chrome.exe`
under Program Files or the local app data folder, `/Applications/Google Chrome.app`), so it uses the
Chrome the Windows and macOS runner images ship. On Linux without one, it installs the `chromium`
and `fonts-liberation` packages with apt-get (with `sudo` unless it runs as root), so it works on
Ubuntu runners and in the build-agent container. Elsewhere it fails, and a browser must be
installed before the step. The test tooling must read one of those variables.

## Inputs

| Name | Default | Description |
|---|---|---|
| `path` | required | Node project folder, relative to the workspace. |
| `scripts` | `build` | package.json scripts to run in order, separated by spaces or new lines. |
| `setup` | none | package.json scripts to run before the install, separated by spaces or new lines. |
| `dependencies` | none | Local Node project folders to build first, one per line. |
| `package-manager` | from each lockfile | `npm`, `pnpm` or `yarn`. |
| `browser` | `false` | `true` provides a system Chromium or Chrome. |

All folders must be inside the workspace and contain a `package.json`.
