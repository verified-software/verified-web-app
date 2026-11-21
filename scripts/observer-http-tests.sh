#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
runner=${1:-bin/verified-forum}
left_port=${OBSERVER_LEFT_PORT:-18086}
right_port=${OBSERVER_RIGHT_PORT:-18087}
dir=build/observer-http
mkdir -p "$dir" evidence
printf '[]\n' > evidence/observer-http-tests.json
FORUM_ALICE_DRAFT='Alice draft one: secret alpha' FORUM_BOB_DRAFT='Bob private draft: beta' \
  "$runner" "$left_port" > "$dir/left-server.log" 2>&1 &
left_pid=$!
FORUM_ALICE_DRAFT='Changed Alice draft: secret omega' FORUM_BOB_DRAFT='Bob private draft: beta' \
  "$runner" "$right_port" > "$dir/right-server.log" 2>&1 &
right_pid=$!
trap 'kill "$left_pid" "$right_pid" 2>/dev/null || true; wait "$left_pid" "$right_pid" 2>/dev/null || true' EXIT
for port in "$left_port" "$right_port"; do
  ready=false
  for ((i=0;i<50;i++)); do
    if curl -sf --max-time 1 "http://127.0.0.1:$port/posts" > /dev/null; then ready=true; break; fi
    sleep 0.1
  done
  [[ $ready == true ]] || { cat "$dir/left-server.log" "$dir/right-server.log" >&2; exit 1; }
done
left_token= right_token=
pair() {
  local expected=$1 name=$2 request=$3 endpoint=${4:-program}
  local left_status right_status side port token status
  for side in left right; do
    if [[ $side == left ]]; then port=$left_port; token=$left_token; else port=$right_port; token=$right_token; fi
    local args=(-sS --max-time 4 -o "$dir/$side.json" -w '%{http_code}'
      -H 'Content-Type: application/json' --data-binary "$request")
    [[ -z $token ]] || args+=(-H "Authorization: Bearer $token")
    status=$(curl "${args[@]}" "http://127.0.0.1:$port/$endpoint")
    if [[ $side == left ]]; then left_status=$status; else right_status=$status; fi
    if jq -e 'has("token")' "$dir/$side.json" >/dev/null; then
      token=$(jq -er .token "$dir/$side.json")
      if [[ $side == left ]]; then left_token=$token; else right_token=$token; fi
    fi
    # Login necessarily issues independent random bearer tokens. This is the
    # ONLY omitted field; all other JSON and the HTTP status must be equal.
    jq -S 'del(.token)' "$dir/$side.json" > "$dir/$side-observation.json"
  done
  local equal=false
  if cmp -s "$dir/left-observation.json" "$dir/right-observation.json"; then equal=true; fi
  jq --arg name "$name" --arg request "$request" --arg expected "$expected" \
    --arg left "$left_status" --arg right "$right_status" --argjson equal "$equal" \
    --slurpfile l "$dir/left-observation.json" --slurpfile r "$dir/right-observation.json" \
    '. + [{name:$name,request:$request,expected:$expected,leftStatus:$left,rightStatus:$right,
      passed:($left==$expected and $right==$expected and $equal),left:$l[0],right:$r[0]}]' \
    evidence/observer-http-tests.json > "$dir/next.json"
  mv "$dir/next.json" evidence/observer-http-tests.json
  [[ $left_status == "$expected" && $right_status == "$expected" && $equal == true ]] || {
    echo "FAIL paired observation: $name" >&2
    cat "$dir/left-observation.json" "$dir/right-observation.json" >&2
    exit 1
  }
  printf 'PASS same Bob observation: %s (%s)\n' "$name" "$expected"
}
pair 200 'guest public read' '{"budget":1,"program":{"op":"read"}}'
pair 403 'guest cannot read Alice secret' '{"budget":1,"program":{"op":"inspect","value":{"private":"alice"}}}'
pair 200 'Bob login and own private response' '{"budget":2,"credentials":{"user":"bob","password":"bob-demo"},"program":{"op":"login","next":{"op":"inspect","value":{"private":"bob"}}}}'
jq -e '.trace[1].body=="Bob private draft: beta"' "$dir/left.json" >/dev/null
pair 403 'Bob cannot read Alice secret' '{"budget":1,"program":{"op":"inspect","value":{"private":"alice"}}}'
pair 403 'private sink denied' '{"budget":1,"program":{"op":"create","value":{"private":"bob"}}}'
pair 403 'private control denied' '{"budget":1,"program":{"if":{"private":"bob"},"then":{"done":true},"else":{"done":true}}}'
pair 200 'public write, own private read, public read' '{"budget":3,"program":{"op":"create","value":{"text":"Bob public text"},"next":{"op":"inspect","value":{"private":"bob"},"next":{"op":"read"}}}}'
pair 200 'only selected public branch executes' '{"budget":2,"program":{"if":{"text":"nonempty"},"then":{"op":"inspect","value":{"private":"alice"}},"else":{"op":"read"}}}'
pair 429 'exhausted batch rolls back public write' '{"budget":1,"program":{"op":"create","value":{"text":"rollback"},"next":{"op":"read"}}}'
pair 403 'failed batch with attenuation revokes session' '{"budget":2,"program":{"op":"restrict","next":{"op":"create","value":{"text":"denied"}}}}'
pair 401 'session revoked after failed attenuation batch' '{"budget":1,"program":{"op":"create","value":{"text":"denied"}}}'
left_token= right_token=
pair 200 'fresh login after failed attenuation' '{"budget":1,"credentials":{"user":"bob","password":"bob-demo"},"program":{"op":"login"}}'
pair 200 'successful attenuation persists' '{"budget":1,"program":{"op":"restrict"}}'
pair 403 'legacy write cannot bypass attenuation' '{"op":"create","body":"bypass"}' command
pair 200 'viewer still receives only own private value' '{"budget":1,"program":{"op":"inspect","value":{"private":"bob"}}}'
pair 403 'failed batch with logout revokes session' '{"budget":2,"program":{"op":"logout","next":{"op":"inspect","value":{"private":"bob"}}}}'
pair 401 'session revoked after failed logout batch' '{"budget":1,"program":{"op":"inspect","value":{"private":"bob"}}}'
left_token= right_token=
pair 200 'fresh login after failed logout' '{"budget":1,"credentials":{"user":"bob","password":"bob-demo"},"program":{"op":"login"}}'
pair 200 'successful logout' '{"budget":1,"program":{"op":"logout"}}'
pair 401 'replay after successful logout' '{"budget":1,"program":{"op":"inspect","value":{"private":"bob"}}}'
for side in left right; do
  if [[ $side == left ]]; then port=$left_port; else port=$right_port; fi
  curl -sf "http://127.0.0.1:$port/posts" > "$dir/$side-posts.json"
  curl -sf "http://127.0.0.1:$port/" > "$dir/$side-page.html"
done
cmp "$dir/left-posts.json" "$dir/right-posts.json"
cmp "$dir/left-page.html" "$dir/right-page.html"
if rg -q 'secret alpha|secret omega' "$dir/left-posts.json" "$dir/right-posts.json" "$dir/left-page.html" "$dir/right-page.html"; then
  echo 'FAIL private Alice data in public response' >&2; exit 1
fi
cp "$dir/left-posts.json" evidence/observer-public-posts.json
printf 'All paired HTTP checks passed: %s comparisons, plus identical public JSON/HTML.\n' "$(jq length evidence/observer-http-tests.json)"
