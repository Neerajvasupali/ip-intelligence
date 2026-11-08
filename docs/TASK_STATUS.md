# Event-investigation task status

Release status, 8 November 2026. The event backend and 58-node unified workflow are deployed. No external alerting integration is included.

| # | Task | Status and evidence |
| --- | --- | --- |
| 1 | SSH use-case specification | Complete: `SSH_INVESTIGATION.md` |
| 2 | Synthetic fixtures | Complete: four labeled event scenarios in `tests/fixtures` and import-ready files in `demo` |
| 3 | Success measurements | Protocol complete; human results pending. See `evaluation/README.md` |
| 4 | Migration reconciliation | Complete for baseline: exact five recorded deployed migrations restored locally; fresh replay passes; no production ledger mutation |
| 5 | Event data model | Implemented and SQL-tested: events, event groups, original references and actor provenance |
| 6 | Bounded JSON import and preview | Implemented in candidate: file or JSON, preview, explicit confirmation, atomic revalidation; actual authenticated file upload and confirmation passed |
| 7 | Exact deduplication | SQL-tested: identical replay ignored; conflicting IDs rejected; retention bounds deduplication history |
| 8 | Correlation | SQL-tested: source/IP/asset/15-minute bucket; distinct bucket creates case; closed case remains closed |
| 9 | Enrichment queue reuse | SQL-tested: live-mode events share three provider jobs; replay creates no additional jobs; demo creates none |
| 10 | Explainable contextual priority | SQL-tested; activity and declared asset context included in assessment conclusion/fingerprint; separate reputation assessment |
| 11 | Investigation detail view | Implemented; actual renderer exercised with database output and inspected in Firefox; new worklist implemented; production browser report and worklist verified |
| 12 | Authenticated browser journey | Passed actual authenticated upload → preview → confirmation → report → explained closure → review history → worklist. Code tests also cover missing user and discarded forged actor fields |
| 13 | Failure and recovery tests | Existing rollback suite passes on fresh schema, including leases/budgets/attempts; event malformed/conflicting-batch tests pass. Production backend acceptance and browser smoke checks passed |
| 14 | Manual/assisted comparison | Protocol and CSV ready; requires real participant measurements. No time-saving claim made |
| 15 | Self-contained demo | Passes: disposable database → fixtures → grouped investigation → replay suppression → assessment → fixture-attributed closure → HTML report; zero provider requests |

## Remaining evaluation

The human manual-versus-assisted study remains unmeasured. The protocol and CSV are ready; no time-saving claims are inferred from automated tests. The current workspace is shared among authorized n8n users; multi-tenant isolation is not claimed.

## Deployment evidence

Migration version `20261108063105` matches the Supabase ledger. Production browser verification used a real signed-in n8n user and synthetic demo events. The demo case is closed with an explained insufficient-evidence decision and remains clearly labeled. See `test-results/2026-11-08-production-event-release.json` for the verification summary.
