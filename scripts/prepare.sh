#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/extraction build/model evidence/logs
flags=(--no-libraries --erasure --no-projection-like -i vendor/agda2hs-base)
agda "${flags[@]}" --safe --double-check --ignore-interfaces -i agda agda/ForumProofs.agda > evidence/logs/agda-proofs.log 2>&1
agda "${flags[@]}" --safe --double-check -i agda agda/Examples.agda > evidence/logs/agda-examples.log 2>&1
sed 's/--safe //g' agda/ForumCore.agda > build/extraction/ForumCore.agda
cat scripts/extraction-pragmas.agda.inc >> build/extraction/ForumCore.agda
agda2hs "${flags[@]}" --ignore-interfaces -i build/extraction --config agda2hs.yaml -o generated build/extraction/ForumCore.agda > evidence/logs/agda2hs.log 2>&1
agda "${flags[@]}" --safe -i agda --compile --ghc-dont-call-ghc --no-main --compile-dir=build/model agda/ForumCore.agda > evidence/logs/agda-model.log 2>&1
bash scripts/make-oracle.sh
echo 'Safe forum proofs checked; Haskell extracted; Agda model generated.'
