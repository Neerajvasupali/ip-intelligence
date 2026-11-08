# Event investigations — release candidate

## Release status

The repository contains a tested event-investigation release candidate. The production deployment remains the 48-node IP investigation workflow until the backend migration and 58-node unified workflow are approved and deployed. Local database tests and rendered reports do not establish authenticated production browser behavior.

## Event import

The new `events` portal action accepts one JSON file or pasted JSON. Files are limited to 256 KiB and 100 events. The server previews every row and requires an explicit second-page confirmation. Invalid batches persist no events. The backend revalidates the batch on confirmation, including conflicts introduced since preview.

Use `demo/*.json` for synthetic demonstration in **Synthetic demo** mode. These contain reserved documentation addresses and are rejected for live enrichment. Demo imports write labeled cases and evidence-unavailable markers but cannot create provider jobs. Live mode permits supported public IPs and reuses the established queue, provider budgets and cache. Demo mode is a trusted operator choice, not an input-file assertion.

Source and event ID form the deduplication key within live/demo mode. Identical replay is ignored; different content with the same key is rejected. Retention deletion also removes deduplication history for the deleted cases. This is bounded retention, not perpetual exactly-once delivery.

## Correlation policy 1.0

Group by source system, canonical source IP, asset ID and a fixed 15-minute UTC bucket. Bucket boundaries are explicit: 10:14:59 and 10:15:00 belong to different groups. Late events attach to an open matching group; new distinct activity for a closed group creates another case. Exact replay still references its original case. This policy avoids unbounded sliding-window groups and is intentionally simple.

Asset criticality is declared by the authenticated operator when a group is created and remains unchanged for subsequent events in that group. It is not independently discovered. Unknown criticality stays unknown.

Daily admission is bounded to 1,000 events, alongside the existing 200-case rolling-day ceiling. Imports are serialized transactionally. A limit error rolls back the batch. Duplicate rows count toward the conservative event admission check but create no additional records or requests.

## Priority rules 1.0

- Three or more failures and a success in the same group: high; investigate sequence and relationship.
- Three or more failures against a declared critical asset: high.
- Three or more failures: medium.
- Otherwise: unassessed.

Priority is activity context, not incident severity or proof of compromise. The existing reputation rules and evidence quality remain separate. Event context and priority are included in saved assessment conclusions and their fingerprints; changed activity produces another snapshot.

## Workspace and access

The new worklist shows the latest 50 matching cases, status, owner, asset, event count, priority and demo label. The report adds event timeline and contextual priority. Case IDs are still copied to the report/review forms; direct case navigation remains an interface improvement.

The existing n8n authenticated-user boundary remains in force. Editable actor fields are discarded; confirmation restores the payload captured before the confirmation form. All authorized workflow users share the workspace. Per-case tenant isolation is not implemented. Supabase RPC remains service-role-only; private event tables have RLS with no client policies.

## Migration reconciliation

The five baseline SQL files now reproduce the exact versions, names and SQL recorded in the deployed Supabase ledger. No production ledger was rewritten and no original migration was replayed against production. Fresh isolated PostgreSQL replay and the existing acceptance suites pass. `20261108000100_add_event_investigations.sql` is pending deployment; its final timestamp must match the recorded remote version when applied.

## Verification commands

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
python3 scripts/test_database.py
python3 scripts/check_workflow.py
python3 scripts/test_workflow_code.py
python3 scripts/run_demo.py
```

Docker tests use isolated disposable PostgreSQL containers with no published ports. Scripts currently use passwordless sudo and the existing `n8n-n8n-1` container's Node runtime. PostgreSQL image must be available; after pulling it, the demo creates no external API requests. Runtime prerequisites are explicit and are not yet a universal one-command installer.

## Remaining release gates

1. Approval for live backend migration and workflow publication.
2. Authenticated browser verification of actual upload, preview, confirmation, report and explained closure, plus anonymous rejection.
3. Controlled production smoke check with no unnecessary provider calls.
4. Human manual-versus-assisted investigation study. No time-saving or accuracy claim is made before measurements exist.
