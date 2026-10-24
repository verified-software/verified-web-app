#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/reproducer evidence/logs
status=0
agda --no-libraries --ignore-interfaces -i limitations limitations/SafePragma.agda > evidence/logs/safe-pragma.log 2>&1 || status=$?
[[ $status -ne 0 ]]
grep -Fiq 'safe' evidence/logs/safe-pragma.log
echo 'PASS expected rejection of backend COMPILE pragma in safe source'
flags=(--no-libraries --erasure -i vendor/agda2hs-base -i limitations)
status=0
agda2hs "${flags[@]}" --ignore-interfaces -o build/reproducer limitations/Indexed.agda > evidence/logs/indexed-datatype.log 2>&1 || status=$?
[[ $status -ne 0 ]]
grep -Fq 'Not supported: indexed datatypes' evidence/logs/indexed-datatype.log
echo 'PASS expected rejection of nonerased term indices'
agda2hs "${flags[@]}" --ignore-interfaces -o build/reproducer limitations/ErasedIndexed.agda > evidence/logs/erased-indexed.log 2>&1
ghc -fno-code build/reproducer/ErasedIndexed.hs >> evidence/logs/erased-indexed.log 2>&1
echo 'PASS erased-index extraction; Haskell state indices are absent'
bash limitations/config-cache.sh > evidence/logs/config-cache.log 2>&1
tail -1 evidence/logs/config-cache.log
