#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v ghc cabal git jq >/dev/null
[[ $(ghc --numeric-version) == 9.6.6 ]] || { echo 'Use GHC 9.6.6.' >&2; exit 1; }
mkdir -p .tools/bin
cabal install Agda-2.8.0 --installdir="$PWD/.tools/bin" --install-method=copy --overwrite-policy=always
if [[ ! -d .tools/agda2hs/.git ]]; then git clone https://github.com/agda/agda2hs .tools/agda2hs; fi
git -C .tools/agda2hs checkout fc9b069b3e36d9e36a02f6f6e8f1284661f2fcfa
(cd .tools/agda2hs; cabal install exe:agda2hs --installdir="$(cd ../bin; pwd)" --install-method=copy --overwrite-policy=always)
echo 'export PATH="$PWD/.tools/bin:$PATH" before running scripts/build.sh.'
