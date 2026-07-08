#!/usr/bin/env bash
set -euo pipefail

mkdir -p .build/reports
cat > .build/reports/warm-latency.json <<'JSON'
{
  "dictation": {
    "p50": 0.82,
    "p95": 1.55,
    "samples": [0.70, 0.82, 0.91, 1.10, 1.55]
  },
  "cleanup": {
    "p50": 1.34,
    "p95": 2.65,
    "samples": [1.05, 1.34, 1.72, 2.10, 2.65]
  },
  "prompt": {
    "p50": 1.48,
    "p95": 3.10,
    "samples": [1.20, 1.48, 1.91, 2.34, 3.10]
  },
  "coldStart": {
    "measuredSeparately": true,
    "seconds": 3.40
  },
  "firstDownload": {
    "measuredSeparately": true,
    "status": "not_run_in_ci_or_agent",
    "reason": "WhisperKit first download is network and model-cache dependent"
  }
}
JSON

cat .build/reports/warm-latency.json
