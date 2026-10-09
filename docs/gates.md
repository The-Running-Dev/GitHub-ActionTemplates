# Gates file

A repository commits the list of commands its CI runs as **gates**: the checks a change must
pass. A local verification run reads the list instead of guessing from the workflows, and CI
fails when the list and the workflows drift apart.

```json
{
  "gates": [
    { "name": "ci / install", "command": "npm ci" },
    { "name": "ci / test", "command": "npm run test" }
  ]
}
```

The file is `.github/gates.json`. Each gate has a `name` and a `command` that runs from the
repository root in either a POSIX shell or PowerShell 7. AgentKit's `/verify` runs it when the
file exists.

## The check

[`node-ci.yml`](node-ci.md), [`pwsh-ci.yml`](pwsh-ci.md) and [`npm-package.yml`](npm-package.md)
run the [`gates`](../actions/gates/README.md) action once per run when the file exists (their
`gates-file` input; empty turns it off). It derives the gates from every workflow in
`.github/workflows` and fails when the committed list has a gate missing or one no workflow
runs. Order does not matter. The failure prints the expected file in the log and the step
summary, so fixing it is a copy and a commit.

To write the file the first time, run the action with `write: true`, or run its script in the
repository:

```bash
GITHUB_WORKSPACE=. INPUT_WRITE=true pwsh path/to/GitHub-ActionTemplates/actions/gates/gates.ps1
```

## Where the gates come from

In workflow-file order, then job and step order:

- **A job that calls `node-ci.yml` or `npm-package.yml`:** each `pre-build` script; a build of
  each `dependencies` project; each `setup` script (`npm run`); the install (`npm ci`,
  `npm install` without a lockfile, `pnpm install --frozen-lockfile` or `yarn install`); each
  `scripts` entry (`<manager> run <script>`); each `post-build` script. A `working-directory`
  other than the root prefixes `cd <folder> && `.
- **A job that calls `pwsh-ci.yml`:** each `pre-build` script; PSScriptAnalyzer for each of
  `paths` when `analyzer` is `true`; Pester on `tests` with the `tags` and `exclude-tags`
  filters; each `post-build` script.
- **A step marked `# verification: true`** on the line before it: its `run`, with
  `working-directory` as a `cd` prefix. The gate's name is the job and the step name.

Script entries become `pwsh -NoProfile -File ./path.ps1` for PowerShell and `./path` for other
files. Each gate is named `<job> / <what it runs>`.

Not gates: the syntax check (`pwsh-check`; Pester and the analyzer cover it locally),
`check-clean` (a working tree with changes in progress fails it), test reports, coverage gates
and uploads. A library input set with an expression (`${{ ... }}`) cannot be derived and fails
the check; pass a literal value.
