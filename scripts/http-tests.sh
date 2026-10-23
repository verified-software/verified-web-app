#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
runner=${1:-bin/verified-forum}
port=${FORUM_TEST_PORT:-18081}
base="http://127.0.0.1:$port"
mkdir -p build/http evidence
printf '[]\n' > evidence/http-tests.json
"$runner" "$port" > build/http/server.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true' EXIT
ready=false
for ((i=0;i<50;i++)); do
  if curl --silent --fail --max-time 1 "$base/posts" > build/http/initial.json; then ready=true; break; fi
  sleep 0.1
done
[[ $ready == true ]] || { cat build/http/server.log >&2; exit 1; }
expect() {
  local expected=$1 name=$2 data=$3 token=${4:-}
  local args=(-sS --max-time 4 -D build/http/headers -o build/http/response.json -w '%{http_code}'
    -H 'Content-Type: application/json' --data-binary "$data")
  [[ -z $token ]] || args+=(-H "Authorization: Bearer $token")
  local status
  status=$(curl "${args[@]}" "$base/command")
  jq --arg name "$name" --arg expected "$expected" --arg actual "$status" \
    '. + [{name:$name,expected:$expected,actual:$actual,passed:($expected==$actual)}]' \
    evidence/http-tests.json > build/http/next.json
  mv build/http/next.json evidence/http-tests.json
  if [[ $status != "$expected" ]]; then
    printf 'FAIL %s: expected %s, got %s\n' "$name" "$expected" "$status" >&2
    cat build/http/response.json >&2; exit 1
  fi
  printf 'PASS %s (%s)\n' "$name" "$status"
}
expect 401 'anonymous create' '{"op":"create","body":"unauthorized"}'
expect 401 'anonymous edit' '{"op":"edit","id":0,"body":"unauthorized"}'
expect 409 'logout in Guest state' '{"op":"logout"}'
expect 401 'bad credentials' '{"op":"login","user":"alice","password":"wrong"}'
expect 200 'Alice authenticates' '{"op":"login","user":"alice","password":"alice-demo"}'
alice=$(jq -er .token build/http/response.json)
expect 409 'repeated login is an illegal transition' '{"op":"login","user":"alice","password":"alice-demo"}' "$alice"
attack="<script>alert('x')</script><img src=x onerror=alert(1)>"
attack_json=$(jq -nc --arg body "$attack" '{op:"create",body:$body}')
expect 200 'script-like body is stored as data' "$attack_json" "$alice"
curl -sS --fail --max-time 4 -D build/http/page-headers "$base/" > evidence/attack-rendered.html
grep -Fq '&lt;script&gt;' evidence/attack-rendered.html
if grep -Eiq '<script|<img' evidence/attack-rendered.html; then echo 'FAIL executable markup in rendered page' >&2; exit 1; fi
grep -Fiq 'X-Content-Type-Options: nosniff' build/http/page-headers
grep -Fiq "default-src 'none'" build/http/page-headers
printf 'PASS extracted renderer escapes the attack; HTML response has restrictive headers\n'
expect 200 'Bob authenticates' '{"op":"login","user":"bob","password":"bob-demo"}'
bob=$(jq -er .token build/http/response.json)
expect 403 'Bob cannot edit Alice post' '{"op":"edit","id":0,"body":"stolen"}' "$bob"
curl -sS --fail --max-time 4 "$base/posts" | jq -e --arg original "$attack" '.[0].body==$original and .[0].owner=="alice"' > /dev/null
expect 200 'SQL-like text is data' '{"op":"create","body":"Robert'"'"'); DROP TABLE posts;--"}' "$bob"
expect 200 'owner can edit own post' '{"op":"edit","id":0,"body":"edited by Alice"}' "$alice"
expect 403 'edit of absent post rejected' '{"op":"edit","id":31,"body":"absent"}' "$alice"
long=$(jq -nc '{op:"create",body:("x"*257)}')
expect 413 '257-character body rejected by extracted core' "$long" "$alice"
oversized=$(jq -nc '{op:"create",body:("x"*5000)}')
expect 413 'request exceeds 4096 bytes' "$oversized" "$alice"
status=$(curl -sS --max-time 4 -o build/http/chunked.json -w '%{http_code}' -H 'Content-Type: application/json' \
  -H 'Transfer-Encoding: chunked' -H "Authorization: Bearer $alice" --data-binary "$oversized" "$base/command")
[[ $status == 413 ]]
printf 'PASS chunked body limit (%s)\n' "$status"
expect 400 'malformed JSON' '{'
expect 400 'array is not a command' '[]'
expect 400 'nested message complexity rejected' '{"op":"create","body":{"a":{"b":{"c":0}}}}' "$alice"
expect 400 'unknown network operation cannot enter core language' '{"op":"fetch","url":"https://attacker.invalid"}' "$alice"
expect 400 'arbitrary SQL operation cannot enter core language' '{"op":"sql","query":"DROP TABLE posts"}' "$alice"
expect 400 'unbounded program cannot enter core language' '{"op":"loop","program":"forever"}' "$alice"
expect 400 'caller cannot choose post owner' '{"op":"create","body":"x","owner":"bob"}' "$alice"
expect 400 'negative id rejected' '{"op":"edit","id":-1,"body":"x"}' "$alice"
expect 400 'fractional id rejected' '{"op":"edit","id":0.5,"body":"x"}' "$alice"
expect 400 'unsupported Unicode rejected' '{"op":"create","body":"\u2028"}' "$alice"
expect 401 'forged bearer rejected' '{"op":"create","body":"x"}' fake-token
expect 200 'logout invalidates Alice token' '{"op":"logout"}' "$alice"
expect 401 'logged-out bearer cannot be replayed' '{"op":"create","body":"x"}' "$alice"
status=$(curl -sS --max-time 4 -o build/http/wrong-type.json -w '%{http_code}' -H 'Content-Type: text/plain' --data '{}' "$base/command")
[[ $status == 415 ]]
printf 'PASS content type is restricted (%s)\n' "$status"
status=$(curl -sS --max-time 4 -o build/http/unsupported.json -w '%{http_code}' "$base/arbitrary")
[[ $status == 404 ]]
printf 'PASS unsupported HTTP endpoint rejected (%s)\n' "$status"
for ((i=2;i<32;i++)); do expect 200 "bounded store creation $i" '{"op":"create","body":"filler"}' "$bob"; done
expect 409 '33rd post exceeds core store bound' '{"op":"create","body":"over capacity"}' "$bob"
for ((i=1;i<64;i++)); do expect 200 "bounded session creation $i" '{"op":"login","user":"alice","password":"alice-demo"}'; done
expect 429 '65th live session exceeds adapter bound' '{"op":"login","user":"alice","password":"alice-demo"}'
jq -e 'all(.[]; .passed)' evidence/http-tests.json >/dev/null
printf 'All HTTP checks passed: %s recorded command responses plus rendering, unchanged-state, headers, chunking, media-type and endpoint checks.\n' "$(jq length evidence/http-tests.json)"
