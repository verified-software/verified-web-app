#!/usr/bin/env bash
# Optional probe only. Not a Scala application or a claimed verified backend.
set -euo pipefail
cd "$(dirname "$0")/.."
backend=${1:?Usage: bash scripts/scala-probe.sh /path/to/pinned/agda2scala}
mkdir -p build/scala-view build/scala evidence/scala
for name in ForumCore ClientCore; do
  if [[ $name == ForumCore ]]; then annotations=scripts/extraction-pragmas.agda.inc; else annotations=scripts/client-pragmas.agda.inc; fi
  sed 's/--safe //g' "agda/$name.agda" > "build/scala-view/$name.agda"
  sed -E 's/AGDA2HS/AGDA2SCALA/g; s/ deriving .*#-\}/ #-}/' "$annotations" >> "build/scala-view/$name.agda"
done
"$backend" --no-libraries --erasure --ignore-interfaces --no-projection-like \
  -i vendor/agda2hs-base -i build/scala-view --scala-dialect=Scala3 \
  --out-dir=build/scala build/scala-view/ClientCore.agda > evidence/scala/extraction.log 2>&1
find build/scala -type f -print
agda --safe --double-check --no-libraries --ignore-interfaces --erasure \
  -i vendor/agda2hs-base -i limitations limitations/ScalaErasedIf.agda > evidence/scala/reproducer-proof.log 2>&1
sed 's/--safe //g' limitations/ScalaErasedIf.agda > build/scala-view/ScalaErasedIf.agda
printf '\n{-# COMPILE AGDA2SCALA ifChoice #-}\n{-# COMPILE AGDA2SCALA caseChoice #-}\n' >> build/scala-view/ScalaErasedIf.agda
"$backend" --no-libraries --erasure --ignore-interfaces -i vendor/agda2hs-base -i build/scala-view \
  --scala-dialect=Scala3 --out-dir=build/scala build/scala-view/ScalaErasedIf.agda > evidence/scala/reproducer.log 2>&1
rg -q '^  def caseChoice' build/scala/ScalaErasedIf.scala
rg -q 'UnsupportedTerm \(Lam' build/scala/ScalaErasedIf.scala
if rg -q '^  def ifChoice' build/scala/ScalaErasedIf.scala; then
  echo 'Unexpected backend change: erased-if reproducer now emitted; reassess finding.' >&2; exit 1
fi
jq -n '{backendCommit:"902859c0e7ad7f45126f9825634d19f43b55881d",backendVersion:"0.1.0.4",
  agdaVersion:"2.8.0.2",backendExitCode:0,scalaCompilationAttempted:false,scalaApplicationWorking:false,
  finding:"Erased-proof lambdas in Haskell.Prim.if_then_else_ become UnsupportedTerm TODO comments; required evaluate/writeValue/run definitions are omitted.",
  reproducer:"limitations/ScalaErasedIf.agda",equivalentCaseDefinitionEmitted:true,
  correction:"Explicit Boolean case splits avoid the lambda in the reproducer; complete-core port also needs cross-module and Haskell.Prim.Maybe integration."}' \
  > evidence/scala/result.json
echo 'Probe completed: partial Scala emitted; complete interpreter is NOT available.'
