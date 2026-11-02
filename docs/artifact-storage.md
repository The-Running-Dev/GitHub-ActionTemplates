# Artifact storage and v2 migration

Successful validation should normally create no optional downloadable full build.
Building, testing, packing, reporting and coverage gates still run. Published GitHub release
assets and registry packages are separate durable outputs; this policy does not delete them.

| Output | Default | Upload failure |
|---|---|---|
| .NET/PowerShell diagnostics | Failure-only, 3 days | Warning and summary; validation result preserved |
| Optional package/site download | Disabled; explicit opt-in, 1 day | Warning and summary |
| Node paths | Disabled; select a policy or declare a required consumer | Optional failures warn; required failures block |
| Required package/site/image transfer | Enabled only for its consumer, 1 day | Blocks the dependent publish/deploy |
| Docker build records | Disabled; opt-in, 1 day | Docker action manages its post-build record |
| Weekly drift report | 30 days | Best effort |

The `never` policy disables **optional** uploads. It cannot suppress a declared required
transfer. Required artifacts upload only after a successful producer. Diagnostic `failure`
and `always` policies may collect partial evidence after failure, unless cancelled.

## Moving from v1

Pin a reviewed v2 release or immutable implementation SHA. v1 retains its previous contract.
Inspect every downloader, including jobs in another reusable workflow, before migrating.

- `.NET` and `npm-package` still pack on validation runs. Packages upload for registry
  publishing on tags, configured default-branch prereleases, **or** GitHub-release-only tags.
  Set `upload-builds: true` for an additional optional download. Package retention is separate
  from diagnostic retention: `build-retention-days` and `handoff-retention-days` default to 1.
- `.NET` and `pwsh-ci` default to `diagnostic-policy: failure` and `retention-days: 3`.
  Use `always` only when successful evidence is useful. In-job test summaries still run.
- `node-ci` no longer uploads merely because `artifacts` has paths. Set `artifact-policy:
  failure` with `retention-days: 3` for diagnostics, `always` for a requested optional build,
  or **`artifact-required: true`** if another job downloads the output. Required paths cannot
  be empty. Match the downstream consumer to the OS/Node-qualified artifact name.
- `docs` and `pages` build and validate PR previews without uploading. Deployment still gets
  its required GitHub Pages artifact. Set `upload-builds: true` for a preview download without
  deployment. Optional retention and deployment handoff retention both default to 1 day.
- `container` keeps the tested image archive required by its publishing job. Do not disable
  this transfer to save space. Both Docker build paths disable build records unless
  `upload-build-records: true`; opted-in records default to 1 day.

## Manual downloads

For a package or site caller:

```yaml
on:
  push:
  pull_request:
  workflow_dispatch:
    inputs:
      upload_builds:
        description: Keep a downloadable CI build for one day
        type: boolean
        default: false
jobs:
  build:
    permissions: { contents: read, packages: write, id-token: write }
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/workflows/dotnet.yml@v2
    with:
      publish: false
      github-release: false
      upload-builds: ${{ github.event_name == 'workflow_dispatch' && inputs.upload_builds }}
```

For Node builds, pass the same expression through
`artifact-policy: ${{ github.event_name == 'workflow_dispatch' && inputs.upload_builds && 'always' || 'never' }}`.

## Required handoffs, expiry and capacity

Set `handoff-retention-days` long enough for approval delays and reruns of downstream jobs.
For example, a seven-day approval window requires an explicit seven-day handoff. After an
artifact expires, rerun the producer as well as the consumer. GitHub must store a Pages
deployment artifact; an external copy cannot replace the Pages API's input.

Short retention bounds accumulation, not the size of an individual upload. A single required
image/build can exceed available quota. An external backend must replace the required
producer-to-consumer transport and verify integrity before it removes that quota dependency;
adding a second copy on a VPS does not do so. No VPS credentials or external backend are
configured by these templates.

Policy validation accepts integer lifetimes from 1 to 90 days; the repository's own limit
must also permit the selected lifetime. Optional upload failures do not turn failed tests
green. Required transfer failures remain fatal, with a summary explaining the blocked handoff.
Only stage allowlisted diagnostics; exclude secrets, signing keys and unrelated working files.
