# Operations runbook

Operate this as a small evidence enrichment service. The documented settings favor free-tier quotas and predictable recovery over throughput. This is a dated configuration, not a service-level guarantee.

## Daily checks

Open the unified workflow's operator console and review metrics, pending jobs, failed jobs, provider enablement, cooldowns and remaining daily budgets. Check recent scheduled executions in n8n. A growing queue with healthy executions usually means incoming work exceeds the deliberately low processing rate. Do not increase concurrency before measuring the provider allowances and the database claim behavior.

The worker claims one eligible job per minute. Claims reserve provider usage; they do not imply a successful response. Cached results avoid a new provider request. A case can have several provider jobs and may need several ticks before full coverage is available.

## Incident response

| Symptom | Check | Recovery |
| --- | --- | --- |
| Unauthorized portal | n8n login and workflow execute access | Sign in using the production form URL; do not remove access controls |
| Provider disabled | Credential validity and authentication error | Replace the stored credential, verify it, then enable the provider through the operator controls |
| Provider cooling down | HTTP 429 / Retry-After and daily usage | Let the cooldown expire; avoid repeated manual calls |
| Pending enrichment | Worker enabled, eligible time, remaining budget, stale leases | Restore the scheduled worker; expired leases can be reclaimed with a new claim token |
| Exhausted attempts | Saved provider error and execution details | Fix the cause before an intentional retry; never loop failed jobs indefinitely |
| Missing report | Case ID and saved evidence | Retrieve the case report; partial evidence should remain visible |
| Closure rejected | Saved assessment, final disposition, explanation, signed-in reviewer | Generate the report first and submit an attributed review |

The default ceilings are 100 requests per provider per UTC day, 60 seconds between claims for a provider, a 10-minute lease and three attempts. Rate limiting backs off for at least one hour or a later provider Retry-After. A database claim token prevents an expired worker from completing a newer claim. Authentication failures disable the affected provider.

## Analyst procedure

1. Submit a public IP with a reason and an intentional request key when deduplication is needed.
2. Retrieve the report after enrichment. Read observation dates, coverage and provider disagreements.
3. Correlate the IP with actual event context outside this project. Shared infrastructure and isolated vendor flags require judgment.
4. Save a disposition with an explanation. Use `under_review` while unresolved. Closure requires a final disposition and an existing saved assessment.

The owner field is assignment metadata. The review actor comes from the authenticated n8n user, not the typed owner or note.

## Maintenance and recovery

The maintenance path performs bounded retention cleanup. Current policy removes closed cases last updated more than 90 days ago and deletes expired cache older than seven days; related case records may cascade when a case is removed. Confirm the deployed SQL before changing retention. Append-only review triggers do not prevent authorized retention deletion.

Back up the database and n8n configuration through an approved backup process. Protect and back up the n8n encryption key separately: a workflow export does not contain the saved credentials. Restore and verify database permissions, migrations and credential bindings before enabling a restored schedule. Keep only one intended production worker active.

Before a change, export a sanitized workflow and record the deployed version. Apply migrations deliberately; the local consolidated baseline and historical deployed ledger differ (see [setup](SETUP.md)). Re-run relevant transactional tests in an isolated environment. Do not claim zero downtime or durable recovery until restoration has been exercised.
