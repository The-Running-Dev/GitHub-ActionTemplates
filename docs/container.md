# container.yml

Builds a container image, starts it and smoke-tests it, then pushes the image that was tested.
A deploy job can call a redeploy webhook and wait until the site serves the new build.

| Run | Build and smoke test | Push | Deploy |
|---|---|---|---|
| Pull request | yes | no | no |
| Push to the default branch | yes | yes, while the commit is still the branch tip | with `deploy: true` |
| Tag `v1.2.3` | yes | yes | with `deploy: true` |
| Push to another branch | yes | no | no |

| Job | Runs |
|---|---|
| `Build` | Checkout, version (when `tags` needs one), `artifact` download, `pre-build`, [`image-meta`](../actions/image-meta/README.md) labels, Buildx build loaded into Docker, [`image-gate`](../actions/image-gate/README.md) start, `smoke-npm-scripts` and `smoke-scripts`, `image-gate` stop, then [`image-archive`](../actions/image-archive/README.md) save and upload of the tested image. |
| `Publish` | [`branch-tip-gate`](../actions/branch-tip-gate/README.md), `image-meta` tags, `image-archive` load (the image ID must match), registry login, [`image-push`](../actions/image-push/README.md), optional cosign signature, build provenance attestation. |
| `Deploy` | [`webhook-deploy`](../actions/webhook-deploy/README.md): webhook, then the health URL; then `post-deploy` scripts. |
| `Result` | [`needs-gate`](../actions/needs-gate/README.md): the one check for branch protection to require, `<caller job> / Result`. |

What was smoke-tested is what is pushed: `Publish` loads the saved image and checks its ID
instead of building again. The exception is `platforms`: `docker load` cannot hold a
multi-platform image, so `Publish` rebuilds every platform from the layer cache and pushes that.
`Build` still smoke-tests the runner's platform.

## Set up

1. Choose the registry:

   | Registry | Set up |
   |---|---|
   | GHCR (default) | Nothing; `github.token` pushes to `ghcr.io/<owner>/<repository>`. If the package already exists and was created by another repository, give this repository **Write** under the package's **Manage Actions access**. |
   | Other | `registry: <host>`, `registry-username`, and the password as the `REGISTRY_TOKEN` secret. |

2. Decide how the container proves it is ready: a `HEALTHCHECK` in the Dockerfile, an HTTP
   `smoke-port`, scripts run inside it (`smoke-exec`), scripts run against it from the runner
   (`smoke-scripts`, `smoke-npm-scripts`), or any mix.
3. To deploy, store the redeploy webhook (Portainer, Coolify and the like) as the
   `DEPLOY_WEBHOOK_URL` secret and set `deploy: true` and `health-url`.
4. Add the workflow ([examples/container.yml](../examples/container.yml)):

```yaml
name: Container

on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:

permissions: {}

jobs:
  image:
    permissions:
      contents: read
      packages: write
      id-token: write
      attestations: write
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/workflows/container.yml@v1
    with:
      tags: short-sha version minor major latest
      fetch-depth: 0
      smoke-port: '8080'
      smoke-path: /health
      deploy: true
      health-url: https://example.com/version.json
      health-expect: ${{ github.sha }}
    secrets:
      DEPLOY_WEBHOOK_URL: ${{ secrets.DEPLOY_WEBHOOK_URL }}
```

The caller grants all four permissions even on pull requests, where only `Build` runs: GitHub
checks a reusable workflow's permissions before it runs any job. `Build` itself only reads.

## Tags

`tags` lists tag kinds; see [`image-meta`](../actions/image-meta/README.md) for each.
`version`, `minor` and `major` need a version: the workflow works one out with the
[`version`](../actions/version/README.md) action, from git tags unless `version-strategy` says
otherwise (`fetch-depth: 0` for the `tag` strategy). `latest` goes on default-branch builds and
stable tag builds only.

## Two pushes close together

Two pushes to `main` a minute apart start two runs; the older one can reach `Publish` last.
`Publish` asks GitHub for the branch head first, and `require-tip` decides:

| `require-tip` | Older run |
|---|---|
| `all` (default) | Pushes nothing and ends green with a note; the newer run publishes. |
| `latest` | Pushes its commit tags but leaves `latest` alone. |
| `none` | Pushes everything. |

Tag builds are never held back.

## Smoke test

`image-gate` runs the image with `smoke-env` and `smoke-options`, then waits up to
`smoke-timeout` seconds for it to be ready: running, its `HEALTHCHECK` healthy if it has one,
and, with `smoke-port`, `GET <smoke-path>` answering one of `smoke-status`. Then it copies each
`smoke-exec` script into the container and runs it there (`.sh` with `sh`, `.ps1` with `pwsh`).

After that `smoke-npm-scripts` (package.json scripts in `smoke-directory`) and `smoke-scripts`
(repository scripts) run on the runner with:

| Variable | Value |
|---|---|
| `IMAGE` | The image reference that was built. |
| `CONTAINER` | The running container's name, for `docker exec` or `docker logs`. |
| `SMOKE_URL` | `http://127.0.0.1:<port>` when `smoke-port` is set. |

The container log is printed when the container is stopped, pass or fail.

## Inputs

| Name | Default | Description |
|---|---|---|
| `context` | `.` | Build context, relative to the repository root. |
| `dockerfile` | | Dockerfile from the repository root. Empty uses `<context>/Dockerfile`. |
| `target` | | Build stage to stop at. |
| `build-args` | | Build arguments, `NAME=value`, one per line. |
| `image-name` | repository name | Image name under the owner. |
| `registry` | `ghcr.io` | Registry host. |
| `registry-username` | run's actor | Registry user. |
| `tags` | `sha latest` | Tag kinds, separated by spaces. |
| `labels` | | Extra labels, `key=value`, one per line. |
| `version-strategy` | | `tag`, `manifest` or `run-number`. Empty uses `tag` when `tags` needs a version. |
| `manifest` | | Manifest for the `manifest` strategy. |
| `tag-prefix` | `v` | Prefix of release tags. |
| `platforms` | | e.g. `linux/amd64,linux/arm64`. Empty pushes the runner's platform, the tested image. |
| `cache` | `true` | Cache layers in the GitHub Actions cache; pull requests only read it. |
| `push` | `true` | `false` only builds and smoke-tests. |
| `require-tip` | `all` | `all`, `latest` or `none`; see above. |
| `sign` | `false` | Sign the pushed digest with cosign, keyless. |
| `attest` | `true` | Attach a build provenance attestation to the digest. |
| `environment` | | Environment for `Publish`, for approvals and environment secrets. |
| `artifact` | | Artifact from an earlier job to download before the build, e.g. a built site. |
| `artifact-path` | `.` | Where `artifact` is downloaded. |
| `pre-build` | | Repository scripts run before the build, one per line. |
| `smoke-test` | `true` | `false` skips the smoke test. |
| `smoke-port` | | Container port to probe over HTTP. |
| `smoke-path` | `/` | Path the probe requests. |
| `smoke-status` | `200` | Accepted status codes, separated by spaces, or `any`. |
| `smoke-env` | | Container environment, `NAME=value`, one per line. |
| `smoke-options` | | Extra `docker run` options, one per line. |
| `smoke-exec` | | Repository scripts run inside the container, one per line. |
| `smoke-timeout` | `60` | Seconds the container has to become ready. |
| `smoke-scripts` | | Repository scripts run on the runner against the container, one per line. |
| `smoke-npm-scripts` | | package.json scripts run against the container, separated by spaces. |
| `smoke-directory` | `.` | Node project for `smoke-npm-scripts`. |
| `node-version` | | Node for the smoke and post-deploy scripts. |
| `deploy` | `false` | After a push, call `DEPLOY_WEBHOOK_URL` and wait for `health-url`. |
| `deploy-environment` | | Environment for `Deploy`. |
| `deploy-method` | `POST` | Webhook method: `POST`, `GET` or `PUT`. |
| `health-url` | | URL polled after the webhook. Empty skips the wait. |
| `health-status` | `200` | Healthy status codes, or `any`. |
| `health-expect` | | Text the health response must contain, e.g. `${{ github.sha }}`. |
| `health-timeout` | `300` | Seconds to wait for the health URL. |
| `post-deploy` | | Repository scripts run after the deploy, with `IMAGE`, `DIGEST` and `DEPLOY_TOKEN`. |
| `artifact-name` | `image-<image-name>` | Artifact that carries the image to `Publish`. Set it when `image-name` has a `/`. |
| `gates-file` | `.github/gates.json` | [Gates file](gates.md) checked when it exists; empty turns the check off. |
| `fetch-depth` | `1` | Commits to fetch; `0` for the `tag` version strategy. |
| `submodules` | `false` | `true`, `recursive` or `false`. |
| `timeout-minutes` | `30` | Timeout of the build job. |
| `runs-on` | `ubuntu-latest` | Runner for the Build and Publish jobs. It needs Docker; a self-hosted Linux runner whose `DOCKER_HOST` is a Docker-in-Docker sidecar works. |
| `utility-runs-on` | `ubuntu-latest` | Runner for the Deploy and Result jobs. |

| Secret | Description |
|---|---|
| `REGISTRY_TOKEN` | Registry password or token. Without it GHCR uses `github.token`. |
| `BUILD_SECRETS` | BuildKit secrets, `id=value`, one per line, for `RUN --mount=type=secret`. |
| `DEPLOY_WEBHOOK_URL` | Redeploy webhook URL. Masked, never printed. |
| `DEPLOY_TOKEN` | Given to `post-deploy` scripts as `DEPLOY_TOKEN`. |

## Outputs

| Name | Description |
|---|---|
| `image` | Image name without a tag, e.g. `ghcr.io/owner/name`. |
| `version` | Version that was built, empty when none was worked out. |
| `pushed` | `true` when the image was pushed. |
| `digest` | Pushed digest. |
| `tags` | Pushed references, one per line. |
| `deployed` | `true` when the deploy job finished. |
