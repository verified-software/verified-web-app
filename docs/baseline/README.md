# Verified restricted forum protocol

An actual Haskell HTTP server calls Agda-extracted authorization, editing, size checks and HTML escaping. No Python implementation. The core and proofs are small enough to read: `agda/ForumCore.agda`, `agda/ForumProofs.agda`, and the generated `generated/ForumCore.hs`.

## Run

Included x86_64 Linux binary, built on Ubuntu 24.04:

```sh
bin/verified-forum 18080
# In another terminal:
curl -s http://127.0.0.1:18080/posts
token=$(curl -s http://127.0.0.1:18080/command -H 'Content-Type: application/json' \
  -d '{"op":"login","user":"alice","password":"alice-demo"}' | jq -r .token)
curl -s http://127.0.0.1:18080/command -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $token" -d '{"op":"create","body":"<script>alert(1)</script>"}'
curl -s http://127.0.0.1:18080/
```

The HTML contains `&lt;script&gt;`, never the submitted script element. Text is stored as text and remains readable. `bob` / `bob-demo` is a second demo account. Bob's token cannot edit Alice's post. Login credentials are **public demo fixtures**, not a production authentication scheme. The server binds only to loopback, stores state in memory and resets on restart.

Commands are flat JSON objects: `read`; `login` with `user,password`; `create` with `body`; `edit` with integer `id,body`; `logout`. There are no commands for JavaScript, SQL, fetching arbitrary URLs or loops. Extra fields are rejected. Post IDs are stable list positions because this demo never deletes posts.

## Build and verify

Use GHC **9.6.6**, cabal-install **3.12.1.0**, Agda **2.8.0**, agda2hs **1.5** at `fc9b069b3e36d9e36a02f6f6e8f1284661f2fcfa` (embedded Agda 2.8.0.2). Dependencies, including WAI 3.2.5 and Warp 3.4.16, are pinned in `cabal.project.freeze`. Requires `git`, `jq`, `curl`, GNU coreutils, `strip`, and normal GHC development libraries.

```sh
# Only if the tools are missing:
bash scripts/bootstrap.sh
export PATH="$PWD/.tools/bin:$PATH"
make verify
# Inspect saved evidence without rebuilding:
make check-evidence
```

This session reused the pinned tools from the Plinth experiment. The bootstrap script is supplied but was not rerun on a clean machine. `make verify` was run: it checks the canonical proofs with `--safe --double-check --ignore-interfaces`, extracts with stock agda2hs, generates an independent MAlonzo oracle, builds the server, runs property/HTTP tests and reproduces compiler limitations. The safe source has no postulates, holes, termination overrides or foreign executable definitions.

## What is machine-checked

| Definition in `ForumProofs` | Exact guarantee |
|---|---|
| `protocol-safety` | Every accepted `execute` result follows the indexed `Step` relation. Anonymous writes, repeated authentication and anonymous logout have no accepted transition. |
| `accepted-edit-secure` | An accepted edit targets an existing post owned by the acting user; before/after stores satisfy a pointwise `AllProtected` relation. |
| `unowned-unchanged`, `owner-preserved` | Other users' cells remain identical; every edited cell retains its original owner. |
| `render-no-tag` | Every rendered user fragment contains only `Plain SafeChar` or `Amp`. Raw `<`, `>`, single quotes and double quotes are absent. |
| `render-bounded` | At most six output glyphs per input glyph. With a 256-glyph body, the fragment is at most 1,536 glyphs. |
| `accepted-create-bounded`, `accepted-edit-bounded` | Every accepted incoming body fits the supplied text limit. |
| `store-bound-preserved` | Starting within the post-count limit, every accepted operation preserves that limit. |

These quantify over arbitrary finite stores, bodies, users and limits, not just the demo examples. Agda checks structural termination. `Examples.agda` additionally evaluates an authorized edit, a denied ownership attack and escaping.

`Step` and the proof relations are indexed types in Agda. The exported Haskell API is an ordinary ADT with a **proved runtime transition checker**; it is not a Haskell GADT that makes every illegal call unrepresentable. The same `execute` function proved above is extracted and called by `Server.hs`. Invalid ADT values can be constructed in Haskell, and `execute` rejects them.

## Boundaries and assumptions

`Authenticate User` represents a checked authentication decision. The HTTP adapter constructs it only after checking demo credentials. Wire clients cannot submit this constructor or choose an owner. Random 256-bit bearer tokens map to server-side sessions; logout removes the token. Authentication correctness, token secrecy/entropy and atomic `MVar` integration are **not Agda-proved**.

The rendering theorem concerns the actual extracted glyph output. `Adapter.hs` maps a finite alphabet to ASCII, and the server places the escaped fragment only in HTML text inside `<pre>`. Correct ASCII conversion, browser parsing and text-node placement are assumptions. Tests exhaust the entire supported ASCII alphabet and inspect real HTTP output. This is no theorem about every browser, attribute/URL/JavaScript/CSS contexts or later reparsing of text as markup. CSP and `nosniff` are additional tested adapter headers, not part of the proof.

Only printable ASCII plus newline is supported. Other Unicode and control characters are explicitly rejected. HTTP bodies are read with a 4,096-byte streaming cap, JSON nesting is capped at two before Aeson decoding, bodies are limited by the core to 256 glyphs, posts to 32, live sessions by the adapter to 64. The size theorems cover body acceptance, post-count preservation and rendering output. They do **not** establish a whole-server CPU/heap/time bound or resistance to denial of service. Parser and session limits are tested Haskell code. No general client-program DSL was needed; each request is one operation from the finite allowed language.

The core has no effect primitives, raw HTML/SQL/script fragments or network-address operations. SQL-like text is never executed because the application has no SQL interpreter or database. Unsupported network/program commands fail decoding. This is not a general object-capability sandbox or a theorem about arbitrary Haskell/PureScript programs.

Agda's kernel, primitives, agda2hs, GHC, MAlonzo and its runtime, dependencies, build scripts and OS are trusted. Theorems assume finite fully defined Haskell values. Neither extraction nor GHC compilation has a semantics-preservation certificate here. **The deployed application is not fully formally verified.**

## Tests and concrete attacks

- Six QuickCheck properties × **2,000 cases** with seed `20261024`: extracted/model agreement, renderer agreement and bounds, ownership, anonymous denial, random protocol traces, and wire-body roundtrips.
- **122 recorded command responses**, plus HTTP checks for escaping, unchanged unauthorized state, headers, chunked bodies, media type and unsupported endpoints. Includes malformed/deep/oversized inputs, forged/replayed tokens, spoofed ownership, cross-user edits, unsupported SQL/fetch/loop commands, 33rd-post and 65th-session rejection.
- `<script>alert('x')</script><img src=x onerror=alert(1)>` is accepted as post data and escaped by the extracted renderer. An implementation concatenating that body as raw HTML could produce executable elements. Our saved response in `evidence/attack-rendered.html` contains escaped text. No external attack endpoint is contacted.

See `evidence/logs/core-tests.log`, `evidence/logs/http-tests.log` and `evidence/http-tests.json`. Tests are evidence, not universal proofs. Failed development builds are retained and are not counted as passing checks.

## Agda/agda2hs findings

1. Nonerased term-indexed datatypes are unsupported. `limitations/Indexed.agda` reproduces the exact failure; `ErasedIndexed.agda` shows the supported workaround and its loss of Haskell state indices. Existing related issues: [#80](https://github.com/agda/agda2hs/issues/80) and [#437](https://github.com/agda/agda2hs/issues/437). This is a feature boundary, not a newly discovered bug.
2. Our `LT` glyph constructor clashes with `Prelude.LT`. Existing `agda2hs.yaml` Prelude-hiding configuration fixes this without rewriting executable definitions.
3. **Configuration changes can leave stale generated Haskell.** `limitations/config-cache.sh` reproduces a config-only edit that returns success but leaves the old ambiguous output. `--ignore-interfaces` regenerates the corrected import and GHC accepts it. The production script uses this correction. The relevant source is `Agda2Hs.Compile.moduleSetup`, which tests generated-file freshness against the Agda interface, without binding it to the configuration. No matching issue was found in the limited search. No upstream code was modified and no issue/PR was submitted.

The safe-source extraction view removes only `--safe` and appends backend/deriving annotations, as in Experiment 1. No executable body changes. The config changes only a Prelude import. See `limitations/README.md` for exact reproducers and plausible improvements.

`claims.json` and `evidence/verification-report.json` separate proofs, tests, assumptions and gaps, with commands/exit codes/tool versions/source commit. Hashes bind the exact source, generated Haskell, oracle, logs, interfaces and executable. They do not prove compiler correctness or authenticity. The report checker detects stale files; `make verify` performs fresh checks.

See [architecture.md](architecture.md) and [RESEARCH.md](RESEARCH.md). Source history is in Git; generated evidence/binaries are shipped in the ZIP and ignored by Git.
