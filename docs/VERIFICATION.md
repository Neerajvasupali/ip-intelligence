# Verification evidence

Evidence snapshot: **7 November 2026**. Historical results below describe the recorded implementation checks. Documentation creation does not rerun external provider integrations or establish their present availability.

## Recorded checks

| Area | Evidence | Scope |
| --- | --- | --- |
| End-to-end enrichment | [Acceptance record](../test-results/2026-11-07-acceptance.json) | Real lookups for a public IP, queue processing, cache reuse, deduplication, report and case paths |
| Worker failure handling | Acceptance record | Pinned provider responses for rate limits, authentication failures, timeout, not-found and malformed payloads |
| Database safeguards | [Transactional suite](../tests/database_acceptance.sql) | Lease expiry/recovery, fencing, provider budgets, UTC reset, retry ceiling and maintenance; rollback fixtures |
| Analyst decisions | [Analyst suite](../tests/analyst_layer_acceptance.sql) | Snapshot reuse, changed evidence, append-only reviews and reviewer/closure constraints |
| Workflow analyst paths | [Analyst verification](../test-results/2026-11-07-analyst-layer-verification.json) | Executions 88, 90–93; authenticated trigger represented by a fixture; external calls pinned |
| Portal protection | Acceptance history | Anonymous GET and multipart POST rejected with HTTP 401 |

The analyst workflow tests deliberately exercise rejection paths. An execution reporting an error can be the expected result for missing reviewer identity, incomplete closure or a missing explanation. The report rendering check used a real database report supplied to a pinned RPC response. It was not a fresh full interactive browser login. No synthetic analyst decisions were committed as real reviews.

## Reproducing checks

Read each SQL test before execution. These suites require privileged database access and exercise writes inside transactions before rolling back; they are not read-only monitoring queries. Run against a disposable environment first. Never paste database credentials into shell history. Supply credentials using your database client's protected connection mechanism.

To validate an import, attach all four credentials, configure the backend URL, inspect operator metrics, submit one intended public IP, let the queue run, retrieve the saved report and perform an authenticated explained review. Inspect both provider outcomes and the stored assessment/review linkage. Test an unavailable provider separately and verify a useful partial report. Avoid spending provider quota on repeated checks of unchanged behavior.

## Limits

Passing recorded tests does not establish a throughput SLA, independent security assurance, every browser/session deployment, permanent external API availability or correctness of all third-party threat intelligence. Evidence dates, stale results and provider disagreements must remain visible to the analyst. Wazuh ingestion is future work.

## Documentation checks

The [documentation validation record](../test-results/2026-11-07-documentation-verification.json) records Firefox desktop and mobile interaction checks, local link and asset validation, export sanitization and repository secret-pattern checks. Browser previews were inspected at 1440×1000 and 390×844. These checks do not call production APIs.
