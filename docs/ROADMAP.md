# Roadmap

These are proposed next steps, not implemented features. Keep the single unified workflow and introduce changes in small reviewable releases.

## 1. Operational confidence

Add measured queue age, enrichment latency, provider error rate, cache hit rate and budget-exhaustion tracking. Establish a baseline with synthetic inputs and mocked provider responses before any controlled load exercise. Define an acceptable backlog for this low-throughput deployment. Exercise backup restoration and document secret rotation.

## 2. Analyst context

Add structured event context: source/destination role, event timestamp, asset identifier, detection rule and business relevance. Separate evidence strength from incident severity. Add an authenticated case worklist and explicit authorization rules if multiple analysts use the system. Preserve existing saved conclusions when rules change.

## 3. Integration contract

Define a versioned authenticated ingestion envelope with validation, stable idempotency keys and bounded admission. Test duplicate delivery, delayed events, malformed payloads and partial provider outages. Add observability before opening a new automated input source.

## 4. Wazuh integration

Connect Wazuh only after the ingestion contract and admission controls exist. Filter eligible alerts, extract the relevant public IP with direction/context, deduplicate repeated events and preserve the original alert reference. Do not send every alert directly to all providers. Keep enrichment asynchronous so a slow third-party API cannot block alert ingestion.

## 5. Response decisions

Consider analyst-approved response actions only after false-positive review, authorization, rollback and an audit trail are demonstrated. Automatic blocking is outside the current system. Shared hosting, resolvers and cloud addresses make reputation-only containment unsafe to infer.
