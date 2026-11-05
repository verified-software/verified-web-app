#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidence/logs evidence/baseline evidence/development bin
printf '[]\n' > evidence/checks.json
run() {
  local name=$1; shift
  local status=0
  "$@" > "evidence/logs/$name.log" 2>&1 || status=$?
  jq --arg name "$name" --arg command "$*" --argjson status "$status" \
    '. + [{name:$name,command:$command,exitCode:$status,log:("evidence/logs/"+$name+".log")}]' \
    evidence/checks.json > evidence/checks.next.json
  mv evidence/checks.next.json evidence/checks.json
  tail -6 "evidence/logs/$name.log"
  return "$status"
}
run prepare bash scripts/prepare.sh
run haskell-build cabal build all -j2
run core-tests bash scripts/run-tests.sh core-tests
run program-tests bash scripts/run-tests.sh program-tests
run tenant-tests bash scripts/run-tests.sh tenant-tests
cp "$(cabal list-bin exe:verified-forum)" bin/verified-forum
strip bin/verified-forum
run http-tests bash scripts/http-tests.sh
run program-http-tests bash scripts/program-http-tests.sh
run observer-http-tests bash scripts/observer-http-tests.sh
run tenant-http-tests python3 test/tenant_http.py bin/verified-forum
run limitations bash scripts/check-limitations.sh
{ ghc --version; cabal --version; agda --version; agda2hs --version; } > evidence/versions.txt
bash scripts/report.sh
echo 'Proofs, extraction, property tests, HTTP tests and compiler reproductions passed.'
