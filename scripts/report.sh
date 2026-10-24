#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
jq -e 'length == 8 and all(.[]; .exitCode == 0)' evidence/checks.json >/dev/null
for file in evidence/http-tests.json evidence/program-http-tests.json evidence/observer-http-tests.json; do
  jq -e 'length > 0 and all(.[]; .passed)' "$file" >/dev/null
done
find agda generated src app test scripts examples fixtures vendor limitations bin docs toolchain -type f \
  ! -name '*.agdai' ! -name '*.hi' ! -name '*.o' -print0 | sort -z | xargs -0 sha256sum > evidence/checksums.sha256
sha256sum claims.json cabal.project cabal.project.freeze agda2hs.yaml verified-forum.cabal README.md \
  PROPERTIES.md ATTACKS.md LIMITATIONS.md COMPARISON.md SCALA.md architecture.md LICENSE >> evidence/checksums.sha256
find build/model build/extraction build/reproducer build/cache-reproducer evidence/logs evidence/baseline evidence/development -type f \
  ! -name '*.hi' ! -name '*.o' -print0 | sort -z | xargs -0 sha256sum >> evidence/checksums.sha256
if [[ -d build/scala && -d build/scala-view && -d evidence/scala ]]; then
  find build/scala build/scala-view evidence/scala -type f -print0 | sort -z | xargs -0 sha256sum >> evidence/checksums.sha256
fi
find agda -name '*.agdai' -print0 | sort -z | xargs -0 sha256sum >> evidence/checksums.sha256
sha256sum evidence/http-tests.json evidence/program-http-tests.json evidence/attack-rendered.html evidence/program-attack-rendered.html \
  evidence/observer-http-tests.json evidence/observer-public-posts.json evidence/checks.json evidence/versions.txt >> evidence/checksums.sha256
core_properties=$(rg -c '^\+\+\+ OK, passed 2000 tests' evidence/logs/core-tests.log)
program_properties=$(rg -c '^\+\+\+ OK, passed 2000 tests' evidence/logs/program-tests.log)
[[ $core_properties == 6 && $program_properties == 11 ]]
baseline_evidence=false
if [[ -f evidence/baseline/fresh-http-tests.log && -f evidence/baseline/source-tests.log ]]; then baseline_evidence=true; fi
jq -n --slurpfile claims claims.json --slurpfile checks evidence/checks.json \
  --arg commit "$(git rev-parse HEAD)" --arg status "$(git status --porcelain)" \
  --arg agda2hs fc9b069b3e36d9e36a02f6f6e8f1284661f2fcfa \
  --arg versions "$(cat evidence/versions.txt)" \
  --arg manifest "$(sha256sum evidence/checksums.sha256 | cut -d' ' -f1)" \
  --arg executable "$(sha256sum bin/verified-forum | cut -d' ' -f1)" \
  --arg core "$(sha256sum generated/ClientCore.hs | cut -d' ' -f1)" \
  --argjson legacyHTTP "$(jq length evidence/http-tests.json)" \
  --argjson programHTTP "$(jq length evidence/program-http-tests.json)" \
  --argjson observerHTTP "$(jq length evidence/observer-http-tests.json)" \
  --argjson originalCases "$((core_properties * 2000))" --argjson programCases "$((program_properties * 2000))" \
  --argjson baselineEvidence "$baseline_evidence" \
  '{schemaVersion:3,experiment:3,fullyFormallyVerifiedApplication:false,
    baseline:{commit:"ccc759d0b5e172ca6cc4052680931818528290bb",archiveSHA256:"ee95372f4c4dc80ba3f5dc5628f360df5550d6ed9157db13cea410efccd541a7",reproduction:"evidence/baseline",evidenceAvailable:$baselineEvidence},
    git:{commit:$commit,workingTree:$status},agda2hsCommit:$agda2hs,toolchain:$versions,
    properties:$claims[0],checks:$checks[0],
    tests:{originalGeneratedCases:$originalCases,programGeneratedCases:$programCases,
      legacyHTTP:$legacyHTTP,programHTTP:$programHTTP,observerHTTPPairs:$observerHTTP,seed:20261024},
    artifacts:{manifest:"evidence/checksums.sha256",manifestSHA256:$manifest,
      executable:{path:"bin/verified-forum",sha256:$executable},
      extractedCore:{path:"generated/ClientCore.hs",sha256:$core},
      proofModules:["agda/ForumProofs.agda","agda/ClientProofs.agda","agda/ClientFlow.agda","agda/ClientSyntax.agda","agda/ClientTransactions.agda"],
      extractionViews:"build/extraction",independentModel:"build/model"}}' > evidence/verification-report.json
bash scripts/check-evidence.sh
