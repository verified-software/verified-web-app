#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v ghc cabal git jq >/dev/null
[[ $(ghc --numeric-version) == 9.6.6 ]] || { echo 'Use GHC 9.6.6.' >&2; exit 1; }
mkdir -p .tools/bin
cabal install --ignore-project Agda-2.8.0 --constraint='aeson >=2.2 && <3' --constraint='transformers-compat ==0.7.2' \
  --flags='-optimise-heavily' --disable-optimization \
  --installdir="$PWD/.tools/bin" --install-method=copy --overwrite-policy=always
if [[ ! -d .tools/agda2hs/.git ]]; then git clone https://github.com/agda/agda2hs .tools/agda2hs; fi
git -C .tools/agda2hs checkout fc9b069b3e36d9e36a02f6f6e8f1284661f2fcfa
cat > .tools/backend.project <<EOF
packages: $PWD/.tools/agda2hs
optimization: 0
constraints: Agda ==2.8.0.2, aeson >=2.2 && <3
package Agda
  flags: -optimise-heavily
EOF
cp toolchain/agda2hs.project.freeze .tools/backend.project.freeze
cabal build --project-file=.tools/backend.project exe:agda2hs -j2
cp "$(cabal list-bin --project-file=.tools/backend.project exe:agda2hs)" .tools/bin/agda2hs
echo 'export PATH="$PWD/.tools/bin:$PATH" before running scripts/build.sh.'
