#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
jq -e 'length == 5 and all(.[]; .exitCode == 0)' evidence/checks.json >/dev/null
jq -e 'all(.[]; .passed)' evidence/http-tests.json >/dev/null
find agda generated src app test scripts fixtures vendor limitations bin -type f \
  ! -name '*.agdai' ! -name '*.hi' ! -name '*.o' -print0 | sort -z | xargs -0 sha256sum > evidence/checksums.sha256
sha256sum claims.json cabal.project cabal.project.freeze agda2hs.yaml verified-forum.cabal >> evidence/checksums.sha256
find build/model build/extraction build/reproducer evidence/logs -type f ! -name '*.hi' ! -name '*.o' -print0 \
  | sort -z | xargs -0 sha256sum >> evidence/checksums.sha256
find agda -name '*.agdai' -print0 | sort -z | xargs -0 sha256sum >> evidence/checksums.sha256
sha256sum evidence/http-tests.json evidence/attack-rendered.html >> evidence/checksums.sha256
jq -n --slurpfile claims claims.json --slurpfile checks evidence/checks.json \
  --arg commit "$(git rev-parse HEAD)" --arg status "$(git status --porcelain)" \
  --arg agda2hs fc9b069b3e36d9e36a02f6f6e8f1284661f2fcfa \
  --arg versions "$(cat evidence/versions.txt)" --arg manifest "$(sha256sum evidence/checksums.sha256 | cut -d' ' -f1)" \
  --argjson httpCount "$(jq length evidence/http-tests.json)" \
  '{schemaVersion:1,fullyFormallyVerifiedApplication:false,git:{commit:$commit,workingTree:$status},
    agda2hsCommit:$agda2hs,toolchain:$versions,properties:$claims[0],checks:$checks[0],
    httpRecordedCommandResponses:$httpCount,
    artifacts:{manifest:"evidence/checksums.sha256",manifestSHA256:$manifest,
      generated:"generated/ForumCore.hs",executable:"bin/verified-forum",
      agdaInterfaces:["agda/ForumCore.agdai","agda/ForumProofs.agdai"],
      extractionView:"build/extraction/ForumCore.agda",model:"build/model/MAlonzo/Code/ForumCore.hs"}}' \
  > evidence/verification-report.json
bash scripts/check-evidence.sh
