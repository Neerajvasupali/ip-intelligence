# Event-investigation task status

Release-candidate status, 8 November 2026. Implemented means present in the repository; it does not imply production deployment. No external alerting integration is included.

| # | Task | Status and evidence |
| --- | --- | --- |
| 1 | SSH use-case specification | Complete: `SSH_INVESTIGATION.md` |
| 2 | Synthetic fixtures | Complete: four labeled event scenarios in `tests/fixtures` and import-ready files in `demo` |
| 3 | Success measurements | Protocol complete; human results pending. See `evaluation/README.md` |
| 4 | Migration reconciliation | Complete for baseline: exact five recorded deployed migrations restored locally; fresh replay passes; no production ledger mutation |
| 5 | Event data model | Implemented and SQL-tested: events, event groups, original references and actor provenance |
| 6 | Bounded JSON import and preview | Implemented in candidate: file or JSON, preview, explicit confirmation, atomic revalidation; actual authenticated form upload pending deployment |
| 7 | Exact deduplication | SQL-tested: identical replay ignored; conflicting IDs rejected; retention bounds deduplication history |
| 8 | Correlation | SQL-tested: source/IP/asset/15-minute bucket; distinct bucket creates case; closed case remains closed |
| 9 | Enrichment queue reuse | SQL-tested: live-mode events share three provider jobs; replay creates no additional jobs; demo creates none |
| 10 | Explainable contextual priority | SQL-tested; activity and declared asset context included in assessment conclusion/fingerprint; separate reputation assessment |
| 11 | Investigation detail view | Implemented; actual renderer exercised with database output and inspected in Firefox; new worklist implemented; production integration pending |
| 12 | Authenticated browser journey | Pending deployment approval and actual end-to-end browser verification. Code tests cover missing user and discarded forged actor fields |
| 13 | Failure and recovery tests | Existing rollback suite passes on fresh schema, including leases/budgets/attempts; event malformed/conflicting-batch tests pass. Production smoke check pending |
| 14 | Manual/assisted comparison | Protocol and CSV ready; requires real participant measurements. No time-saving claim made |
| 15 | Self-contained demo | Passes: disposable database → fixtures → grouped investigation → replay suppression → assessment → fixture-attributed closure → HTML report; zero provider requests |

## Release gates

Automatic approval review rejected the live migration because it replaces the running Supabase API. Explicit approval is required for that deployment. The tested workflow export remains inactive; the existing live workflow was not changed. After approval, apply the migration, reconcile its generated remote version locally, update the existing unified workflow, verify all draft routes, publish and exercise the real authenticated browser journey.

The demo supplies a synthetic reviewer directly to the trusted backend. It is not evidence of browser authentication. The current workspace is shared among authorized n8n users; multi-tenant isolation is not claimed.
