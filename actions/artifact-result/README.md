# artifact-result

Reports an upload step's `outcome` (before `continue-on-error`) in the job summary.
An optional failure emits a warning and succeeds. A required failure fails this action
as well as the upload. Pass `required` from `artifact-policy.outputs.required`.

| Input | Default | Meaning |
|---|---|---|
| `outcome` | required | Raw upload step outcome: `success`, `failure`, `skipped`, `cancelled`. |
| `required` | `false` | Whether the artifact is required transport. |

There are no outputs. Skipped/cancelled uploads produce no success message.

The reusable workflows wire this up automatically. See [artifact storage](../../docs/artifact-storage.md).
