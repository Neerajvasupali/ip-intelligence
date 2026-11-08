# Assessment rules v2.0

These are explainable project heuristics, not calibrated probabilities or a substitute for event investigation. The first matching condition wins.

| Condition | Assessment |
| --- | --- |
| Abuse confidence ≥ 50 with reports, plus at least one VirusTotal flag | `cross_source_signals` |
| Abuse confidence ≥ 50 with reports | `abuse_signal` |
| Exactly one VirusTotal flag and available AbuseIPDB confidence of zero | `conflicting_evidence` |
| Exactly one VirusTotal flag | `isolated_signal` |
| More than one VirusTotal flag | `multiple_vendor_signals` |
| No positive rule above, but jobs are queued/running | `pending` |
| No positive rule above and reputation coverage is missing | `inconclusive` |
| Coverage exists but relevant underlying observation is over 30 days old | `outdated_evidence` |
| Otherwise | `no_known_malicious_evidence` |

A VirusTotal flag is a malicious or suspicious vendor result. Multiple vendor flags are not assumed independent; feeds may share intelligence. Zero AbuseIPDB confidence does not establish that an IP is benign. Report counts are not interchangeable with confidence.

## Coverage, freshness, and priority

- Reputation coverage requires successful AbuseIPDB and VirusTotal results. IPinfo is network context.
- Evidence quality is partial, stale, or available. Missing/uninterpretable observation dates generate warnings where implemented.
- Retrieval time and underlying observation time are different. A recently retrieved report can describe old activity.
- Country and ASN are not maliciousness scores.
- The system does not calculate business incident severity from an IP alone.

## Human outcomes

The analyst chooses under review, confirmed malicious activity, confirmed benign activity, insufficient evidence, or duplicate investigation. An explanation and authenticated reviewer identity are required. A closed case cannot remain under review.

The analyst outcome does not overwrite the automated assessment. Reviews reference the most recently saved assessment; retrieve the report before recording a decision.
