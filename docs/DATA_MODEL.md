# Data model and RPC contract

> The original IP-enrichment architecture is described below. The deployed event release adds two private tables, event intake/confirmation and worklist branches; see [event release](EVENT_RELEASE.md) for the current behavior.


## Tables

| Table | Purpose | Important invariants |
| --- | --- | --- |
| `providers` | Enable flags, TTLs, daily reservations, cooldowns, latest status | Budget restricted to 1–100; UTC day accounting |
| `cases` | Request key, IP, reason, status, assignment, timestamps | Unique request key; status is open/investigating/closed |
| `jobs` | Provider lookup work, attempts, lease, result | One active IP/provider job; token required for completion |
| `case_sources` | Evidence snapshot or job reference for each case/provider | Unique case/provider pair |
| `cache` | Shared reusable provider evidence | Unique IP/provider; explicit expiry |
| `audit` | Submission, provider, and analyst events | Backend-generated events; associated case |
| `assessments` | Saved automated conclusion and evidence | Case/rule/fingerprint uniqueness; updates rejected |
| `reviews` | Human disposition and explanation | Authenticated actor source; updates rejected; saved assessment reference |

Assessment and review history is append-oriented within the retention policy. Deleting an eligible old closed case also removes dependent history. This is not a legal-hold system or cryptographically tamper-proof ledger. A database administrator retains administrative power.

## Backend RPC actions

All requests use `POST /rest/v1/rpc/ipintel_api` with a JSON envelope:

```json
{"action":"report","payload":{"case_id":"YOUR-CASE-UUID"}}
```

| Action | Inputs | Output / behavior |
| --- | --- | --- |
| `enqueue` | `ip`, `request_key`, optional `reason` | Creates/reuses a case and associates provider evidence/jobs |
| `claim` | Empty object | One eligible job with lease token, or `available: false` |
| `finish` | `job_id`, `token`, normalized `result`, optional `retry_at` | Completes, reschedules, or fails a job |
| `report` | `case_id` | Case, sources, conclusion, assessment ID/history, reviews, and audit timeline |
| `case_update` | Case ID, status, disposition, note, owner, trusted actor | Appends a review and updates case state |
| `metrics` | Empty object | Queue counts, provider usage/health context, cache count, recent cases |
| `configure` | `provider`, boolean `enabled` | Changes provider availability |
| `maintenance` | Empty object | Deletes eligible stale records under the retention policy |

`report` is not a strictly read-only operation: retrieving it can create a new assessment snapshot. Do not invoke it through a read-only monitoring routine and assume it never writes.

## Assessment snapshots

The fingerprint is an MD5 digest used for deduplication of canonical JSON evidence and evaluation. It is **not** a cryptographic integrity guarantee. A snapshot stores the full evidence, conclusion, rule version, and creation time.

An unchanged report reuses its assessment ID. Changed evidence or a materially changed evaluation creates another entry. Historical reports created before snapshots were introduced were not reconstructed.

## Analyst attribution

n8n constructs:

```json
{
  "id": "AUTHENTICATED-N8N-USER-ID",
  "name": "Authenticated reviewer display name",
  "source": "n8n_authenticated_user"
}
```

The browser's editable owner field is assignment only. The backend accepts the actor asserted by the trusted n8n backend; anyone holding the backend secret has equivalent privileged authority. Do not expose the RPC credential to the portal browser.
