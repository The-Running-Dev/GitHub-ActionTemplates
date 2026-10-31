# image-gate

Smoke-tests an image before anything is pushed. `start` runs it, waits until it is ready and
runs scripts inside it; `stop` prints the container log and removes it.
[`container.yml`](../../docs/container.md) runs it between the build and the push.

```yaml
- id: smoke
  uses: The-Running-Dev/GitHub-ActionTemplates/actions/image-gate@v1
  with:
    image: app:${{ github.sha }}
    port: '8080'
    health-path: /health
    env: |
      MODE=test
      API_KEY=${{ secrets.TEST_API_KEY }}
    exec: tests/smoke/in-container.sh

- run: ./tests/smoke/Test-Endpoints.ps1
  shell: pwsh
  env:
    SMOKE_URL: ${{ steps.smoke.outputs.url }}

- if: always()
  uses: The-Running-Dev/GitHub-ActionTemplates/actions/image-gate@v1
  with:
    mode: stop
```

Ready means, in order:

1. The container is running. One that exits fails the step with its exit code.
2. Its `HEALTHCHECK`, when the image has one, reports `healthy`. `unhealthy` fails.
3. With `port`: `GET <url><health-path>` answers one of `health-status`.

All within `timeout` seconds. Every failure prints the container log. Then each `exec` script
is copied into the container under `/tmp` and run: `.sh` with `sh`, `.ps1` with `pwsh`,
anything else directly. A script that exits non-zero fails the step.

- `port` is published on a free `127.0.0.1` port, so parallel jobs on one machine do not clash.
  When `DOCKER_HOST` is `tcp://<host>:<port>`, a daemon elsewhere such as a Docker-in-Docker
  sidecar, it is published on all of that daemon's addresses and probed at `<host>` instead.
- `env` goes through an env file that is deleted once the container starts, so values stay out
  of the log and the process list. Values may contain `;` and `=`.
- `options` lines are split on spaces; quoting is not supported.

## Inputs

| Name | Default | Description |
|---|---|---|
| `mode` | `start` | `start` or `stop`. Run `stop` with `if: always()`. |
| `name` | `ghat-smoke` | Container name; `start` and `stop` must match. |
| `image` | | Image to run. Required for `start`. |
| `port` | | Container port to probe over HTTP. Empty skips the probe. |
| `health-path` | `/` | Path the probe requests. Starts with `/`. |
| `health-status` | `200` | Accepted status codes, separated by spaces, or `any`. |
| `env` | | Container environment, `NAME=value`, one per line. |
| `options` | | Extra `docker run` options, one per line (`--volume /a:/b`). |
| `exec` | | Repository scripts run inside the container, by path, one per line. |
| `timeout` | `60` | Seconds the container has to become ready. |

## Outputs

| Name | Description |
|---|---|
| `container` | Container name. |
| `url` | `http://127.0.0.1:<port>` (`http://<DOCKER_HOST host>:<port>` for a tcp:// daemon), empty without `port`. |
