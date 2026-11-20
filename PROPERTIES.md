# What the evidence establishes

All theorems below concern the executable definitions in `ClientCore.agda` or the reused `ForumCore.agda`. They check with Agda 2.8 under `--safe --double-check`, without postulates, holes or termination bypasses. Indexed proof relations remain in Agda; the extracted public Haskell API uses ordinary ADTs and performs runtime validation.

| Proved | Definition and precise scope |
|---|---|
| Authorization at every accepted operation | `ClientProofs.program-authorized` constructs an `AuthorizedTrace` containing the **actual** successful `step` equations and intermediate states. Every create needs `canWrite = True`; every edit also has the original `EditGuarantee`: the target belongs to the actor, other owners' cells are unchanged and owners are preserved. |
| No authority manufactured | `initial-confined`, `step-confined`, `run-confined`: if current and pending grants originate below supplied grants, every successful resulting grant remains below those same sources. Owner must agree; Viewer may derive from Editor, never the reverse. Programs cannot contain Grant values. Initial grants are supplied by the trusted adapter. |
| Revocation | `logout-revokes` removes both current and pending grants; `relogin-after-logout-denied` cannot log in from that empty context. These concern core execution; HTTP token deletion and failed-batch rollback are adapter behavior. |
| Public noninterference | `ClientFlow.public-noninterference`: for a fixed program, fuel, context and public posts, replacing **all private vault data** leaves `publicView(run ...)` equal. The view retains errors, session state, public posts, trace structure and branch results; it erases only the body of explicitly Classified response values. |
| Another user's complete observation | `observer-noninterference`: if both available grants are confined to one observer and that observer's private value agrees, changing other private values leaves the **entire Result equal**, including the observer's own private responses. This is stronger than redaction alone. |
| Private access belongs to the principal | `private-access-owned`: every successful evaluation of a private source has the currently authenticated owner. `private-sink-denied` and `private-control-denied` reject private writes to public posts and conditions on private values. |
| Bounded execution | `ClientProofs.run-budget`: every accepted execution trace Fits its initial fuel. Every primitive and condition emits one event. Total fuel recursion terminates, including adversarial programs. This does not bound glyph traversal, parsing, allocation or wall time. |
| Code/data separation | `ClientSyntax.program-no-injection`: every event in an accepted run has an operation/branch origin in the original Program syntax, with matching constructor and edit index. Literal post data cannot introduce an operation. Public input can select an existing branch. |
| Transaction rollback | `ClientTransactions.transaction-rollback`: every Rollback returns the exact original post store. `transaction-authorized` preserves the full trace theorem on Commit; `transaction-observer` preserves complete observer noninterference. This wrapper is extracted and determines the store selected by the real server. Session map updates and actually installing the result remain trusted adapter behavior. |
| Existing forum invariants | `ForumProofs.protocol-safety`, `accepted-edit-secure`, `accepted-create-bounded`, `accepted-edit-bounded`, `store-bound-preserved`, `render-no-tag`, `render-bounded`: legal base transitions, authorization/ownership, post and store limits, no raw tag delimiters after escaping, and at most six rendered glyphs per input glyph. |

Noninterference fixes the program and literal inputs. It excludes adaptive clients that obtain plaintext then submit a different program, timing, allocation, termination of the HTTP runtime, packet sizes and external side channels. There is no declassification operation and no private-to-public conversion inside this language. We do not claim that an authorized user cannot copy their own draft outside it.

## Tested, not proved

`test/CoreSpec.hs`: six properties × 2,000 cases from Experiment 2. `test/ProgramSpec.hs`: eleven × 2,000, including independent Agda/MAlonzo interpreter and transaction equality, rollback, capability confinement, both information-flow observations, step ownership, budgets, literal separation and JSON AST round trips. Fixed seed 20261024; generated contexts include arbitrary current/pending principals and ranks. Small bounded generators do not exhaust all programs. Deterministic regressions cover logout, attenuation and forged syntax.

`scripts/http-tests.sh` preserves the original suite. `scripts/program-http-tests.sh` records program requests, expected/actual statuses and responses, exercising both endpoints. The report contains actual counts and exit codes. Testing a theorem on generated Haskell gives evidence about extraction; it is not a translation proof.

`scripts/observer-http-tests.sh` compares 18 pairs of complete HTTP results with different Alice private data and matching Bob data/public state. Only random login tokens are omitted. It also compares the public JSON and HTML byte for byte. These are adapter tests of the stated channel, not a theorem about arbitrary HTTP observations or scheduling.

## Assumed and unverified

Trusted: Agda kernel and primitive definitions; agda2hs and MAlonzo semantics preservation; GHC, runtime, dependencies, OS and build scripts; finite fully defined Haskell inputs. There is no compiler certificate for the host-code pipeline.

Adapters must correctly authenticate, issue only the intended login offer, bind a bearer token to its context, atomically commit only Finished results, return private responses only to that requesting authenticated client, preserve the glyph encoding and put rendered text in an HTML text node. JSON/HTTP parsing, duplicate-key behavior, nesting scans, byte/node limits, entropy and session capacity are outside the proof. Core capability constructors are public Haskell constructors: this does not sandbox hostile code running inside the server process.

No claim about production credentials, TLS, CSRF in a future cookie-based deployment, persistence, SQL databases, browsers in general, network/heap denial of service or arbitrary JavaScript. SQL and arbitrary effects are absent from the permitted language; the trusted server itself still performs IO.

SHA-256 records byte identity and links evidence to sources/generated code/executable. It is neither semantic proof nor an authenticated signature.
