#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/extraction build/model evidence/logs
flags=(--no-libraries --erasure --no-projection-like --ignore-interfaces -i vendor/agda2hs-base)
agda "${flags[@]}" --safe --double-check --ignore-interfaces -i agda agda/ForumProofs.agda > evidence/logs/agda-proofs.log 2>&1
agda "${flags[@]}" --safe --double-check --ignore-interfaces -i agda agda/ClientProofs.agda > evidence/logs/client-proofs.log 2>&1
agda "${flags[@]}" --safe --double-check --ignore-interfaces -i agda agda/TenantProofs.agda > evidence/logs/tenant-proofs.log 2>&1
agda "${flags[@]}" --safe --double-check -i agda agda/ClientFlow.agda > evidence/logs/client-flow.log 2>&1
agda "${flags[@]}" --safe --double-check -i agda agda/ClientSyntax.agda > evidence/logs/client-syntax.log 2>&1
agda "${flags[@]}" --safe --double-check -i agda agda/ClientTransactions.agda > evidence/logs/client-transactions.log 2>&1
agda "${flags[@]}" --safe --double-check -i agda agda/ClientExamples.agda > evidence/logs/client-examples.log 2>&1
agda "${flags[@]}" --safe --double-check -i agda agda/Examples.agda > evidence/logs/agda-examples.log 2>&1
sed 's/--safe //g' agda/ForumCore.agda > build/extraction/ForumCore.agda
cat scripts/extraction-pragmas.agda.inc >> build/extraction/ForumCore.agda
sed 's/--safe //g' agda/ClientCore.agda > build/extraction/ClientCore.agda
cat scripts/client-pragmas.agda.inc >> build/extraction/ClientCore.agda
sed 's/--safe //g' agda/TenantCore.agda > build/extraction/TenantCore.agda
cat scripts/tenant-pragmas.agda.inc >> build/extraction/TenantCore.agda
agda2hs "${flags[@]}" --ignore-interfaces -i build/extraction --config agda2hs.yaml -o generated build/extraction/ForumCore.agda > evidence/logs/agda2hs.log 2>&1
agda2hs "${flags[@]}" --ignore-interfaces -i build/extraction --config agda2hs.yaml -o generated build/extraction/ClientCore.agda >> evidence/logs/agda2hs.log 2>&1
agda2hs "${flags[@]}" --ignore-interfaces -i build/extraction --config agda2hs.yaml -o generated build/extraction/TenantCore.agda >> evidence/logs/agda2hs.log 2>&1
sed -i '${/^$/d;}' generated/TenantCore.hs
agda "${flags[@]}" --safe -i agda --compile --ghc-dont-call-ghc --no-main --compile-dir=build/model agda/ForumCore.agda > evidence/logs/agda-model.log 2>&1
agda "${flags[@]}" --safe -i agda --compile --ghc-dont-call-ghc --no-main --compile-dir=build/model agda/ClientCore.agda >> evidence/logs/agda-model.log 2>&1
agda "${flags[@]}" --safe -i agda --compile --ghc-dont-call-ghc --no-main --compile-dir=build/model agda/ClientModel.agda >> evidence/logs/agda-model.log 2>&1
agda "${flags[@]}" --safe -i agda --compile --ghc-dont-call-ghc --no-main --compile-dir=build/model agda/TenantCore.agda >> evidence/logs/agda-model.log 2>&1
bash scripts/make-oracle.sh
runghc scripts/MakeClientOracle.hs
echo 'Safe forum proofs checked; Haskell extracted; Agda model generated.'
