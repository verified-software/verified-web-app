#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
actual=$(sha256sum evidence/checksums.sha256 | cut -d' ' -f1)
expected=$(jq -r .artifacts.manifestSHA256 evidence/verification-report.json)
[[ "$actual" == "$expected" ]]
sha256sum --check --quiet evidence/checksums.sha256
jq -e '.checks | length == 8 and all(.[]; .exitCode == 0)' evidence/verification-report.json >/dev/null
echo 'Source, generated code, evidence and executable match recorded hashes. Use make verify for fresh checking.'
