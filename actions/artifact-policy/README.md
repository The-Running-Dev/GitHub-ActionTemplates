# artifact-policy

Computes an upload decision; it does not transfer files. Required transport is independent
of optional output policy. A failed or cancelled producer never creates a required handoff.

| Input | Default | Meaning |
|---|---|---|
| `policy` | `never` | Optional uploads: `never`, `failure`, or `always`. |
| `required` | `false` | A downstream consumer needs the output of a successful producer. |
| `status` | `success` | Producer `job.status`: `success`, `failure`, `cancelled`, or `skipped`. |
| `retention-days` | `1` | Optional output lifetime, integer 1–90. |
| `required-retention-days` | `1` | Required transfer lifetime, integer 1–90. |

Outputs: `upload`, `required` (both `true`/`false`) and `retention-days`.
The caller uses `required` to decide whether upload failure is fatal. Include an explicit
status check such as `!cancelled()` on diagnostic decision/upload steps so they can run after
an earlier failure. Policies and retention values are validated even when no upload is needed.

See [artifact storage and the v2 migration](../../docs/artifact-storage.md).
