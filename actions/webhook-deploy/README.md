# webhook-deploy

Calls a redeploy webhook (Portainer, Coolify and the like) with retries, then waits until a
health URL answers as expected. Checking for the commit SHA in a version endpoint shows the new
image is the one serving, not the old one still up. [`container.yml`](../../docs/container.md)
runs it in its deploy job.

```yaml
- uses: The-Running-Dev/GitHub-ActionTemplates/actions/webhook-deploy@v0
  with:
    url: ${{ secrets.DEPLOY_WEBHOOK_URL }}
    health-url: https://example.com/version.json
    health-expect: ${{ github.sha }}
    health-consecutive: '3'
```

- The webhook URL usually carries its own token: it is masked and never printed, including in
  error messages.
- A webhook answer outside 2xx, or no answer, is retried `retries` times, `retry-delay` seconds
  apart.
- The health URL is polled every `health-interval` seconds until it answers one of
  `health-status`, with `health-expect` in the body, `health-consecutive` times in a row. A
  failed check resets the count.

## Inputs

| Name | Default | Description |
|---|---|---|
| `url` | | Webhook URL, from a secret. Empty only waits for `health-url`. |
| `method` | `POST` | `POST`, `GET` or `PUT`. |
| `retries` | `3` | Extra attempts when the webhook fails. |
| `retry-delay` | `10` | Seconds between webhook attempts. |
| `timeout` | `30` | Seconds each request may take. |
| `health-url` | | URL to poll after the webhook. Empty skips the wait. |
| `health-status` | `200` | Healthy status codes, separated by spaces, or `any`. |
| `health-expect` | | Text the body must contain. Empty checks the status only. |
| `health-timeout` | `300` | Seconds to wait for the health URL. |
| `health-interval` | `10` | Seconds between health checks. |
| `health-consecutive` | `1` | Healthy answers needed in a row. |

## Outputs

| Name | Description |
|---|---|
| `webhook-status` | Status code the webhook answered with. |
| `health-status` | Status code of the last health check. |
