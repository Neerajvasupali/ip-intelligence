# Setup and portability

## Requirements

- A compatible self-hosted n8n version with HTTP Request, Code, Form Trigger, Form, and Schedule nodes.
- A hosted Supabase project with permission to install SQL migrations.
- Provider accounts for AbuseIPDB, VirusTotal, and IPinfo Lite.
- Python 3 for local documentation serving and the optional credential helper.

The validated workflow uses Form Trigger 2.6, Form 2.5, HTTP Request 4.5, Code 2, and Set 3.5. Confirm your installed n8n supports these node versions and its user-authenticated form feature. Schema validation alone does not establish license/feature availability on a different instance.

## 1. Database schema

For a **fresh project**, review and apply the files in `supabase/migrations` in filename order. The first file is a consolidated initial schema containing the syntax/alias fixes. Later files add the analyst layer and review gating. Use a deployment method that respects your target's migration history.

### Existing deployment warning

The existing live project was provisioned with five migrations through Supabase MCP. Their recorded timestamps and boundaries differ from these local consolidated files. The remote ledger includes `initialize_ip_intelligence`, `fix_report_job_alias`, `fix_metrics_column_ambiguity`, `add_assessment_snapshots_and_analyst_reviews`, and `require_saved_assessment_for_review`.

**Do not blindly run `supabase db push` against that existing project.** Reconcile local migration files with its recorded history first. Do not run the initializer over an existing deployment as an upgrade mechanism. Keep any reconciliation reviewed and preserve deployed data.

## 2. Workflow import

Import `workflows/ip-intelligence-unified.sanitized.json` into n8n. It is deliberately inactive. Credential bindings and webhook identifiers were removed; the Supabase URL is blank. Importing it does not configure provider access or authenticate users.

In **System configuration**, enter the project's HTTPS URL. Let the target n8n instance generate its form/webhook identifiers.

## 3. Credentials

| Credential | Request authentication | Attach to |
| --- | --- | --- |
| Supabase backend secret | `apikey` header | All eight Supabase RPC nodes |
| AbuseIPDB key | `Key` header | AbuseIPDB lookup |
| VirusTotal account | Native `virusTotalApi`, supplying `x-apikey` | VirusTotal lookup |
| IPinfo token | `Authorization: Bearer …` | IPinfo Lite lookup |

Use n8n's credential store. Modern Supabase `sb_secret_…` keys go in `apikey`, not a JWT Bearer header. The optional `connect_supabase.py` also handles legacy service-role JWTs. It depends on the separately installed local `n8n-credentials` skill; that skill and its connection file are not bundled in this repository. Standard n8n credential creation works without the helper.

Provider budgets apply to this workflow's reservations, not all uses of a shared account key. Verify provider terms and current free-tier limits directly before deployment.

## 4. Access and activation

1. Require n8n user authentication on the portal and workflow execution permission.
2. Configure browser access/TLS for your deployment; localhost links assume you are on the n8n host.
3. Enable only providers whose credentials have been verified.
4. Run offline, database, and bounded live tests; inspect results before publication.
5. Publish the tested workflow version. Use its production form URL, not the editor's test URL.

The default configured path is `/form/ip-intelligence`. A test-form banner indicates a manual/test execution. Do not hide that banner to make a test look like production.

## 5. Local documentation

```bash
python3 -m http.server 8080 --bind 127.0.0.1 --directory docs/site
```

Open `http://127.0.0.1:8080`. This serves documentation only; it is not the investigation portal.
