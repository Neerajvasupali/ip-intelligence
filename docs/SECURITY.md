# Security model

## Trust boundaries

The authenticated n8n portal is the user entry point. n8n invokes Supabase with a server-side backend credential and calls the three intelligence providers with credentials stored in n8n. Browser clients must never receive the backend secret.

The exposed `public.ipintel_api` function uses `SECURITY DEFINER` with an empty search path and is executable only by `service_role`. Data lives in the private `ipintel` schema. Row-level security is enabled with no anonymous access policies. These settings reduce accidental exposure; they do not make a leaked service-role credential safe.

Review attribution trusts the original authenticated n8n Form Trigger user. Form-supplied actor fields are discarded. The backend trusts n8n's supplied identity, so a compromised privileged caller can forge attribution. This project does not implement independent cryptographic user assertions, per-case tenant isolation or a full enterprise role model.

## Implemented controls

- Public-IP input validation rejects unsupported/private/documentation targets before provider enrichment.
- Authenticated form access and workflow execution permissions guard the workspace.
- Provider budgets, cooldowns, bounded retries, leases and fencing control repeated work.
- Report rendering escapes untrusted text. Typed notes and provider content remain untrusted input.
- Assessment snapshots preserve the conclusion and rule version used for a review. Update triggers protect assessments and reviews from ordinary edits.
- No automatic network blocking or containment is performed.

Snapshot fingerprints use MD5 for deduplication. They are not signatures or a tamper-evident audit mechanism. Administrators and retention operations can remove records. No legal-hold or immutable external audit store is included.

## Secrets and repository hygiene

The portable workflow export removes credential bindings and pin data, blanks the backend URL and imports inactive. Credentials must be created and attached in the target n8n instance. Local credential-helper connection files, `.env` files, private keys, Python caches and runtime artifacts are excluded from Git. Ignore rules do not replace secret review: inspect every staged change before committing.

Rotate exposed credentials and keep replacements in n8n's credential store. Restrict access to n8n's encryption key, database backups and execution history. Execution logs can contain IPs, reasons and provider evidence; configure retention and access controls according to deployment requirements. Example payloads and screenshots must exclude credentials.

## Remaining assurance work

Independent penetration testing, production load benchmarking and disaster-recovery exercises remain planned assurance work. Shared deployments require a documented access review, retention policy, backup restoration exercise, audit monitoring and verification of reverse proxy and session configuration. Provider API terms and allowances must be reviewed for the intended deployment.

Report sensitive defects privately to the repository owner; no public security contact or disclosure service is configured in this repository.
