#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/cache-reproducer
cp limitations/NameClash.agda build/cache-reproducer/NameClash.agda
flags=(--no-libraries --erasure -i vendor/agda2hs-base -i build/cache-reproducer)
# Force initial generation, then change ONLY external backend configuration.
agda2hs "${flags[@]}" --ignore-interfaces -o build/cache-reproducer build/cache-reproducer/NameClash.agda
cp build/cache-reproducer/NameClash.hs build/cache-reproducer/before.hs
agda2hs "${flags[@]}" --config agda2hs.yaml -o build/cache-reproducer build/cache-reproducer/NameClash.agda
cmp build/cache-reproducer/before.hs build/cache-reproducer/NameClash.hs
echo 'Observed stale output: configuration-only change produced identical Haskell.'
if ghc -fno-code build/cache-reproducer/NameClash.hs > build/cache-reproducer/stale-ghc.log 2>&1; then
  echo 'Unexpected: stale name clash compiled' >&2; exit 1
fi
cat build/cache-reproducer/stale-ghc.log
agda2hs "${flags[@]}" --ignore-interfaces --config agda2hs.yaml -o build/cache-reproducer build/cache-reproducer/NameClash.agda
grep -Fq 'import Prelude hiding (LT)' build/cache-reproducer/NameClash.hs
ghc -fno-code build/cache-reproducer/NameClash.hs
echo 'PASS: --ignore-interfaces regenerates the corrected import; GHC accepts it.'
