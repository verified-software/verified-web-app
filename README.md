# Verified web capabilities — Experiment 3

A small forum whose **server** interprets an Agda-defined client language. Programs can read, log in, publish, edit their own posts, inspect their own private draft, reduce authority and log out. There is no operation for arbitrary network, filesystem, SQL, HTML execution, dynamic evaluation or recursion.

The executable core has machine-checked authorization, capability confinement, ownership, information-flow, syntax-origin and execution-budget proofs. agda2hs generates `generated/ClientCore.hs`; both `/program` and the original `/command` route invoke it. This extends Experiment 2; its renderer, store operations, proofs and tests remain in use.

**The whole application is not formally verified.** Parsing, authentication, session storage, response routing, the compilers and the runtime remain trusted. See [PROPERTIES.md](PROPERTIES.md) for exact statements and exclusions. SHA-256 binds artifacts; it does not prove compiler correctness.

## Run

The archive includes a Linux x86-64 executable:

```sh
./bin/verified-forum 18080
# In another terminal:
curl -sS localhost:18080/program -H 'Content-Type: application/json' --data-binary @examples/login-create.json
```

Save the returned token. Demo users are `alice/alice-demo` and `bob/bob-demo`.

```sh
TOKEN='paste the returned token'
curl -sS localhost:18080/program -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" --data-binary @examples/restrict.json
# Now create/edit fail through BOTH endpoints using that token.
curl -sS localhost:18080/program -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" --data-binary @examples/logout.json
```

In-memory, loopback only, demo authentication; no TLS or persistence. Private drafts are deliberately fake fixtures.

## Reproduce

Use GHC **9.6.6**, cabal-install **3.12.1.0**, Agda **2.8.0**, agda2hs **1.5** at `fc9b069b3e36d9e36a02f6f6e8f1284661f2fcfa` (its embedded Agda is **2.8.0.2**), `git`, `jq`, `curl`, `zip` and a C toolchain. Debian/Ubuntu development libraries: `libgmp-dev libtinfo-dev zlib1g-dev`. `scripts/bootstrap.sh` installs the two Agda tools after GHC/Cabal are available. `cabal.project.freeze` pins application dependencies; no upstream compiler is patched.

```sh
bash scripts/bootstrap.sh                 # skip if the pinned tools are on PATH
export PATH="$PWD/.tools/bin:$PATH"
make verify                              # fresh proofs, extraction, builds and tests
make check-evidence                      # hashes of the delivered run, no recompilation
```

Proof modules use `--safe --double-check`. Extraction removes only the `--safe` option and appends backend annotations: see `build/extraction`. Every extraction forces `--ignore-interfaces`, including after configuration changes. `build/model` contains a separate MAlonzo compilation of the same Agda semantics for differential testing; it is not a second handwritten interpreter.

Actual exit codes, commands and logs are in `evidence/checks.json` and `evidence/logs`. `evidence/verification-report.json` records counts, versions, Git commit, claims and manifest hash. Baseline reproduction evidence is separate under `evidence/baseline`. Rebuilding changes evidence; checking archived hashes should be done first.

## Language and limits

JSON is an unverified adapter to `Stop | Invoke Op Program | Choose Expr Program Program`. Expressions are literal text or a named private source. `if` selects `then` when a **public** expression is empty; private conditions are rejected. This deliberately small conditional has no secret-dependent control. A future AI client could emit this JSON; its output would receive the same server checks as any other client.

Requests: 16 KiB, JSON nesting 24, AST nodes 128, execution budget 0–32. Post bodies: 256 accepted ASCII glyphs; store: 32 posts. The proved budget counts executed primitives and branches, not CPU, memory or parsing work. Private data can be returned to its authenticated owner but cannot be published or used as a condition inside the language.

Programs commit atomically on `Finished`. A refused batch rolls back every action, **including logout and authority reduction**. A successful logout deletes the server token; a successful reduction persists Viewer authority. Login offers are issued by the adapter only after credential verification and cannot be constructed by program syntax. Viewer still permits reading the owner's private draft; it removes writing authority.

Read [ATTACKS.md](ATTACKS.md), [LIMITATIONS.md](LIMITATIONS.md), [COMPARISON.md](COMPARISON.md) and [architecture.md](architecture.md). Original experiment documentation is retained in `docs/baseline`; the Git parent is its delivered source commit.
