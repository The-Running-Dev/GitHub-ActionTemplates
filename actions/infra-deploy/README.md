# infra-deploy

Asks the Infra repository to deploy an image digest, waits for that run, and fails if it fails.
The Portainer credentials stay in the Infra repository: the app repository holds only a token
that can start the Infra deploy workflow, and the Infra workflow validates the request before it
touches Portainer. It replaces calling [`portainer-deploy`](../portainer-deploy/README.md) with the
Portainer secrets in every app repository.

```yaml
deploy:
  needs: container
  if: github.event_name == 'push' && needs.container.outputs.pushed == 'true'
  runs-on: ubuntu-latest
  environment: production
  permissions:
    contents: read
  steps:
    - uses: The-Running-Dev/GitHub-ActionTemplates/actions/infra-deploy@v2
      with:
        app: subzerodev-dashboard
        digest: ${{ needs.container.outputs.digest }}
        token: ${{ secrets.INFRA_DISPATCH_TOKEN }}
```

- Dispatches `workflow` on `ref` of `infra-repository` with the inputs `app`, `digest` (or `images`), `revision`
  and `correlation`. When the dispatch answer carries a run id it is used; otherwise the run is
  found by its title, so the workflow must set `run-name: deploy <app> <correlation>`.
- Only a `sha256:` digest is sent. The Infra workflow decides the image repository, stack and
  health URL from its own per-app record, never from the request.
- For an app whose stack runs several images, pass `images` instead of `digest`: one
  `repository@sha256:digest` per line, every image built from `revision`. They are sent as the
  workflow input `images`, separated by spaces, and the Infra workflow checks each repository
  against its record and pins all of them in one redeploy:

  ```yaml
  images: |
    ghcr.io/owner/app-edge@${{ needs.edge.outputs.digest }}
    ghcr.io/owner/app-service@${{ needs.service.outputs.digest }}
  ```

  The Infra workflow must accept the `images` input; one that does not answers HTTP 422.
- The token is masked before anything runs. GitHub errors report the status and a hint only.
- A run that is still going when `run-timeout` ends fails the step but may still finish: check the
  linked run before dispatching again.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `app` | | App name the Infra deploy workflow knows. |
| `digest` | | Image digest, `sha256:` and 64 hex characters. Set this or `images`. |
| `images` | | Several images, one `repository@sha256:digest` per line. Set this or `digest`. |
| `token` | | Token with Actions write on the Infra repository only. |
| `revision` | `github.sha` | Commit the image was built from. |
| `infra-repository` | `The-Running-Dev/SubZeroDev.Infra` | Repository that holds the deploy workflow. |
| `workflow` | `deploy.yml` | Deploy workflow file. |
| `ref` | `main` | Branch the workflow runs from. |
| `api-url` | `https://api.github.com` | GitHub API base URL (HTTPS, or loopback for tests). |
| `timeout` | `30` | Seconds each API request may take. |
| `find-timeout` | `120` | Seconds to wait for the run to appear. |
| `run-timeout` | `1800` | Seconds to wait for the run to finish. |
| `poll-interval` | `5` | Seconds between checks. |

## Outputs

| Output | Description |
| --- | --- |
| `run-url` | URL of the Infra deploy run. |
| `correlation` | Identifier that tied the dispatch to its run. |
