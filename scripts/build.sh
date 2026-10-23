#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidence/logs bin
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
run core-tests cabal test core-tests --test-show-details=direct
cp "$(cabal list-bin exe:verified-forum)" bin/verified-forum
strip bin/verified-forum
run http-tests bash scripts/http-tests.sh
run limitations bash scripts/check-limitations.sh
{ ghc --version; cabal --version; agda --version; agda2hs --version; } > evidence/versions.txt
bash scripts/report.sh
echo 'Forum proof, extraction, model comparison, HTTP and limitation checks passed.'
