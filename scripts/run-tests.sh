#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
suite=${1:?Usage: bash scripts/run-tests.sh core-tests|program-tests}
case "$suite" in core-tests|program-tests) ;; *) echo 'Unknown suite' >&2; exit 1;; esac
# Build happens explicitly in build.sh. Execute the binary itself: a quiet
# Cabal invocation is not evidence that QuickCheck cases actually ran.
runner=$(cabal list-bin "test:$suite")
"$runner"
