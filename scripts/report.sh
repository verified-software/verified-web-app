#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
jq -e 'length == 10 and all(.[]; .exitCode == 0)' evidence/checks.json >/dev/null
for file in evidence/http-tests.json evidence/program-http-tests.json evidence/observer-http-tests.json; do
  jq -e 'length > 0 and all(.[]; .passed)' "$file" >/dev/null
done
[[ $(rg -c '^\+\+\+ OK, passed 2000 tests' evidence/logs/core-tests.log) == 6 ]]
[[ $(rg -c '^\+\+\+ OK, passed 2000 tests' evidence/logs/program-tests.log) == 12 ]]
[[ $(rg -c '^\+\+\+ OK, passed 5000 tests' evidence/logs/tenant-tests.log) == 2 ]]
find agda generated security scala src app test scripts examples fixtures vendor limitations bin toolchain -type f \
  ! -name '*.agdai' ! -name '*.hi' ! -name '*.o' -print0 | sort -z | xargs -0 sha256sum > evidence/checksums.sha256
sha256sum claims.json cabal.project cabal.project.freeze agda2hs.yaml verified-forum.cabal README.md SECURITY.md LICENSE >> evidence/checksums.sha256
find build/model build/extraction build/reproducer build/cache-reproducer evidence/logs -type f \
  ! -name '*.hi' ! -name '*.o' -print0 | sort -z | xargs -0 sha256sum >> evidence/checksums.sha256
sha256sum evidence/http-tests.json evidence/program-http-tests.json evidence/observer-http-tests.json evidence/checks.json evidence/versions.txt >> evidence/checksums.sha256
if [[ -f evidence/scala/tenant-scala.log ]]; then sha256sum evidence/scala/tenant-scala.log >> evidence/checksums.sha256; fi
find evidence/baseline -type f -print0 | sort -z | xargs -0 -r sha256sum >> evidence/checksums.sha256
jq -n --slurpfile claims claims.json --slurpfile checks evidence/checks.json \
  --arg commit "$(git rev-parse HEAD)" --arg status "$(git status --porcelain)" \
  --arg versions "$(cat evidence/versions.txt)" \
  --arg manifest "$(sha256sum evidence/checksums.sha256 | cut -d' ' -f1)" \
  --arg core "$(sha256sum generated/TenantCore.hs | cut -d' ' -f1)" \
  '{schemaVersion:1,experiment:"3.1",fullyFormallyVerifiedApplication:false,
    git:{commit:$commit,workingTree:$status},toolchain:$versions,properties:$claims[0],checks:$checks[0],
    tests:{forumGeneratedCases:36000,forumSeed:20261024,tenantGeneratedCases:10000,tenantSeed:20261105,tenantHTTP:"test/tenant_http.py"},
    artifacts:{manifest:"evidence/checksums.sha256",manifestSHA256:$manifest,
      extractedTenantCore:{path:"generated/TenantCore.hs",sha256:$core}, executable:"bin/verified-forum"}}' > evidence/verification-report.json
bash scripts/check-evidence.sh
