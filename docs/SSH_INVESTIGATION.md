# SSH authentication investigation

## Problem and scope

Repeated failed SSH authentication attempts can require an analyst to combine event activity, asset context and IP reputation. This project will group related activity and present evidence for an analyst decision. The initial use case accepts manually supplied synthetic events; an external alerting integration is not required.

The release candidate implements event validation, grouped ingestion and contextual priority. Isolated database and workflow-code checks pass. Production deployment and authenticated browser checks remain pending; see [release status](EVENT_RELEASE.md).

## Investigation questions

1. How many distinct failures occurred, when, and against which asset and accounts?
2. Was there a successful authentication after the failures, and does available context explain it?
3. What do reputation providers report, how old are their observations, and do they disagree?
4. Is the activity consistent with expected administration, suspicious behavior, or insufficient evidence?

The analyst records a disposition and explanation. Reputation alone does not establish intent, and the system does not automatically block an address.

## Proposed event contract

The fixtures use `schema_version`, `source`, `event_id`, `occurred_at`, `event_type`, `source_ip`, `asset_id`, `account` and `outcome`. Timestamps are UTC ISO 8601. An identifier is unique within a source. A source IP represents the remote endpoint; an asset ID identifies the target. `account` is optional and should be minimized to the information needed for investigation. Production inputs require authentication, size limits and validation before persistence.

The IPs in the fixtures are documentation-only addresses. They must never be sent to live intelligence providers. Use simulated provider results in fixture tests.

## Scenarios and expected behavior

| Scenario | Input | Expected investigation behavior |
| --- | --- | --- |
| Repeated failures | Three distinct failures for one source and asset | Preserve three events and group according to a documented correlation rule. Show provider findings and their dates. Do not automatically declare malicious. |
| Legitimate mistake | A failure and subsequent success with an analyst-supplied maintenance context | Preserve both outcomes. Maintenance context is a lead for review, not automatic proof of benign activity. |
| Duplicate delivery | Same source and event ID, identical content | Record once; replay creates no new event or enrichment work. |
| Conflicting duplicate | Same source and event ID, different content | Reject or quarantine the conflicting record with a visible reason; never silently overwrite. |
| Invalid event | Missing ID, invalid timestamp, unsupported outcome or malformed IP | Reject with field-specific errors; create no event or provider job. |
| Conflicting intelligence | One simulated vendor flag and zero abuse confidence | Show both findings and the existing conflicting-evidence assessment. Analyst determines significance. |
| Provider unavailable | A simulated provider timeout or exhausted retry | Show partial coverage and the provider status; retain the investigation for review. |

Correlation boundaries, late arrivals and closed-case handling must be specified and tested before implementation. Exact duplicates and distinct related events are different concepts.

## Evaluation protocol

Compare manual and assisted investigations using the same cases, evidence and decision instructions. Record participants, experience, sample size, case order, start/end criteria and whether provider results were simulated. Measure analyst hands-on time separately from elapsed enrichment time. Report per-case values and a summary; avoid claims of detection accuracy from synthetic fixtures.

Measure provider requests by provider, cache hits, duplicate records and jobs after replay, and time to recover from a controlled worker interruption. For each failure scenario record the injected fault, expected outcome, observed outcome and test environment. Results are not claimed until measured.
