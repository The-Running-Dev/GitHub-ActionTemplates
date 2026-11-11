# portainer-deploy

Pins one variable of a Portainer Git stack to an image digest, redeploys the stack with a pull,
then waits until the site's health endpoint reports the deployed commit. Deploying by digest
means a rollback is pinning an older digest, and the revision check shows the new container is
the one serving. [`container.yml`](../../docs/container.md) runs it in its deploy job when the
`PORTAINER_STACK_ID` variable is set.

```yaml
- uses: The-Running-Dev/GitHub-ActionTemplates/actions/portainer-deploy@v2
  with:
    image: ghcr.io/owner/app
    digest: ${{ needs.publish.outputs.digest }}
    portainer-url: ${{ vars.PORTAINER_URL }}
    stack-id: ${{ vars.PORTAINER_STACK_ID }}
    endpoint-id: ${{ vars.PORTAINER_ENDPOINT_ID }}
    api-key: ${{ secrets.PORTAINER_API_KEY }}
    access-client-id: ${{ secrets.CF_ACCESS_CLIENT_ID }}
    access-client-secret: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}
    image-variable: APP_IMAGE
    public-url: https://app.example.com
```

- The stack's environment is read and written back unchanged except `image-variable`, which
  becomes `image@digest` (added when missing). The stack's Git reference, prune setting and Git
  credentials are kept; the stored Git password is never read or sent.
- Only a `sha256:` digest is deployed. Tags are refused.
- The API key and Access token are masked before anything runs. Portainer errors report the
  status code only, because Portainer answers can echo the stack environment. Redirects are not
  followed: a redirect from Portainer usually means Cloudflare Access refused the service token.
- `portainer-url` and `public-url` must be HTTPS.
- The health endpoint must answer HTTP 200 with JSON whose `revision` field is the commit
  (`revision`, by default the commit being built). It is polled every `health-interval` seconds
  for up to `health-timeout` seconds; the step fails if it never reports the revision.

## Inputs

| Name | Default | Description |
|---|---|---|
| `image` | | Image repository without a tag, for example `ghcr.io/owner/app`. |
| `digest` | | Image digest, `sha256:` and 64 hex characters. |
| `portainer-url` | | Portainer base URL, HTTPS, no path. |
| `stack-id` | | Portainer stack ID. |
| `endpoint-id` | | Portainer environment (endpoint) ID the stack runs on. |
| `api-key` | | Portainer API key, from a secret. |
| `access-client-id` | | Cloudflare Access service token ID, when Portainer sits behind Access. |
| `access-client-secret` | | Cloudflare Access service token secret. Set both or neither. |
| `image-variable` | | Stack environment variable that holds the image. |
| `public-url` | | Public base URL of the app, HTTPS, no path. |
| `health-path` | `/health/ready` | Path on `public-url` that answers JSON with a `revision` field. |
| `revision` | `github.sha` | Revision the health endpoint must report. |
| `timeout` | `30` | Seconds each request may take. |
| `redeploy-timeout` | `600` | Seconds the redeploy may take. Portainer answers after the git pull, the image pull and compose up. |
| `health-timeout` | `300` | Seconds to wait for the revision. |
| `health-interval` | `10` | Seconds between health checks. |

## Outputs

| Name | Description |
|---|---|
| `image` | The deployed reference, `image@digest`. |
| `health-url` | The URL that reported the revision. |
