# Investigation correctness update

Status: locally tested, not deployed. The production release remains unchanged. This branch updates the backend and review form as a coordinated release.

## Assessment-bound review

A review must supply the assessment ID shown in the investigation report. The backend compares it with a newly evaluated current report inside the review transaction. A missing, mismatched or stale ID rejects the review; case status and review history remain unchanged. The core review stores the exact supplied assessment rather than selecting an unrelated latest record.

Report and review operations acquire the ingestion and provider-completion advisory locks in that order. They serialize against event intake and provider completion while establishing a coherent decision boundary. These conservative global locks favor consistency at this project's current scale; throughput has not been benchmarked. A future implementation can introduce narrower locks with concurrency tests before changing this invariant.

The form currently requires the assessment ID explicitly. The backend does not trust that value simply because it came from a form: it verifies case membership and current evidence. This is a binding to submitted evidence, not cryptographic proof that a person read the report. Direct report-to-review navigation is a subsequent usability milestone.

## Priority rules 1.1

High sequence-based priority requires at least three failures strictly earlier than a success for the same nonblank supplied account in the correlated group. Equal timestamps do not establish ordering. Account comparisons are case-sensitive after trimming; no account identity is inferred when data is missing.

A success before failures or for a different account does not establish the same-account sequence. Three total failures still produce medium priority, or high priority when the asset was declared critical. Reports include the sequence flag, count of targeted accounts and count of events without account information. These remain investigation leads, not compromise findings.

Existing saved assessments retain their previous conclusions. New report fingerprints include priority-rule version and updated context, so changed conclusions produce separate snapshots.

## Validation

Run `python3 scripts/test_database.py`, `python3 scripts/check_workflow.py`, `python3 scripts/test_workflow_code.py` and `python3 scripts/run_demo.py`. Seven migrations and all four transactional suites pass in isolated PostgreSQL. The regression suite covers unchanged review rejection, exact snapshot attribution, event order, different accounts, missing accounts and critical assets. No production or browser validation is claimed for this branch.

## Coordinated deployment

1. Restore access to the target Supabase project and inspect its migration ledger.
2. Temporarily pause review submissions during the backend/form transition.
3. Apply only the new migration; retain its recorded remote version locally.
4. Update the existing unified workflow with the assessment field, validation and RPC mapping. Preserve all credentials and authentication settings.
5. Verify a real signed-in report/review flow, including a new event arriving after a report is viewed and a fresh report permitting a later decision.
6. Re-enable review submissions and update release evidence before merging to the production branch.

The new required review field intentionally changes the backend contract. Applying only the migration would reject old-form reviews. Historical migrations must not be replayed over the live database.
