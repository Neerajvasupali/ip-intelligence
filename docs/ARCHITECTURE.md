# Architecture

## System boundary

The runtime is one n8n workflow plus a hosted Supabase database. n8n owns form presentation, routing, HTTP calls, normalization, and HTML output. Supabase owns durable jobs, quotas, cache, cases, audit records, assessment snapshots, and analyst reviews.

The documentation site is a separate static artifact. It does not connect to the runtime or contain credentials.

## Entrances and routing

| Entrance | Purpose | Authentication |
| --- | --- | --- |
| Investigation portal | Submit an IP, retrieve a report, or review a case | n8n user authentication plus workflow execution permission |
| Operator console | Setup package, demo, metrics, provider control, retention | n8n editor/API execution access |
| Queue schedule | Claim and process a provider job every minute | Internal scheduled execution |

The portal first collects an action, then renders a dynamic details page. The aggregation step restores the original trigger's authenticated `user` object after merging page answers. It derives the reviewer actor from that original object, ignoring a page-supplied actor or user override.

The shared configuration stores the Supabase URL. Credentials are attached to individual request nodes through n8n's credential store.

## Investigation lifecycle

1. Normalize an IP literal and reject invalid or conservatively excluded special-use ranges.
2. Submit a request key, canonical IP, and reason to the backend RPC.
3. Reuse an existing case for the same request key; reject a conflicting IP for that key.
4. Reuse unexpired provider evidence, or link a case to an existing active provider job for that IP.
5. A scheduled worker claims one eligible job, reserves budget, and receives a lease token.
6. Query the selected provider with a bounded request timeout; normalize the result.
7. Commit using the job ID and lease token. Stale or expired workers cannot commit.
8. On report retrieval, evaluate current case evidence and save an assessment snapshot if its evidence/conclusion fingerprint is new.
9. An authenticated reviewer records a disposition, explanation, and case status, referencing the latest saved assessment.

## Queue and failure controls

| Control | Implemented behavior |
| --- | --- |
| Active-job deduplication | Unique active `(ip, provider)` jobs; cases can share their enrichment |
| Claim coordination | Transaction advisory lock and row selection/locking |
| Provider budget | 100 requests/provider/UTC day; reservations count toward usage even if a request fails |
| Request spacing | At least 60 seconds between claims for the same provider |
| Lease | 10 minutes; worker execution timeout is 180 seconds |
| Attempts | Maximum three claimed attempts before terminal failure |
| Transient failure | Exponential retry timing with provider cooldown |
| Rate limiting | Cooldown of at least one hour, extended by a later valid Retry-After time |
| Authentication failure | Provider is disabled and job fails; credentials need repair and deliberate re-enabling |
| Worker loss | Expired jobs are recovered on a later claim; new token fences out old workers |

A timeout can still mean that an external provider received a request. Quotas are conservative reservations, not an exact reconstruction of a provider's billing or account-wide usage.

## Persistence and trust

The exposed endpoint is `public.ipintel_api(action, payload)`. Its execution is granted to `service_role`, not to anonymous or ordinary authenticated Supabase client roles. Tables reside in a private `ipintel` schema with RLS enabled and no public policies.

The function runs as its owner with an empty search path and fully qualified application tables. n8n's backend credential is therefore a privileged trust boundary: database actor attribution trusts the identity asserted by authenticated n8n processing, not a separate Supabase user login.

## Runtime scale

The current single-job minute scheduler is intentionally conservative for a personal project. It has no measured enterprise throughput target. A busier environment would require measured worker capacity, stronger operational reporting, and a deliberate scaling plan while retaining provider-wide limits.
