#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/model
cat test/Oracle.header.hs > build/model/Oracle.hs
awk '
  /^data T_SafeChar_26/ {active=1; next}
  /^-- ForumCore.Glyph/ {active=0}
  active {while (match($0, /C_[A-Za-z0-9]+_[0-9]+/)) {
    symbol=substr($0,RSTART,RLENGTH); name=symbol; sub(/^C_/,"",name); sub(/_[0-9]+$/,"",name);
    print "toSafe C." name " = M." symbol;
    back=back "fromSafe M." symbol " = C." name "\n";
    $0=substr($0,RSTART+RLENGTH)
  }}
  END {print "\nfromSafe :: M.T_SafeChar_26 -> C.SafeChar\n" back}
' build/model/MAlonzo/Code/ForumCore.hs >> build/model/Oracle.hs
cat test/Oracle.footer.hs >> build/model/Oracle.hs
[[ $(grep -c '^toSafe C\.' build/model/Oracle.hs) == 91 ]]
