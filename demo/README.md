# Synthetic investigation demonstration

The JSON files are import-ready event examples. Select **Synthetic demo** in the candidate portal. Documentation-only IP addresses are intentionally rejected for live enrichment.

## Isolated demonstration

Requirements: Python 3, Docker with passwordless sudo, PostgreSQL image `postgres:17-alpine`, and the existing `n8n-n8n-1` container for its Node runtime. No provider keys or backend keys are needed.

```bash
python3 scripts/run_demo.py
python3 -m http.server 8082 --bind 127.0.0.1 --directory .preview/demo
```

Open http://127.0.0.1:8082/report.html. The script creates and destroys a disposable PostgreSQL container with no published port. It applies the actual migrations and invokes the actual backend functions. Only report artifacts remain in the ignored `.preview/demo` directory. It creates no provider requests.

The demonstration imports three failures, verifies that replay adds no events, retrieves a medium-priority investigation and records a fixture-attributed insufficient-evidence closure. Unavailable provider evidence is shown honestly. A fixture actor is not a signed-in browser user. Invalid-event files demonstrate validation failure rather than a successful import.

## Suggested walkthrough

1. Explain the repeated-authentication investigation problem.
2. Show the synthetic event input and three preserved references.
3. Show one grouped investigation and duplicate replay result.
4. Explain activity priority separately from missing reputation evidence.
5. Show the saved assessment and explained review.
6. Explain the deployment and evaluation gates in `docs/TASK_STATUS.md`.
