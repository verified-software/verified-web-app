# Two working Agda → Haskell experiments

Experiment 1 was packaged and delivered before Experiment 2 began. Each archive is an independent Git repository with canonical Agda, proofs, extracted Haskell, a runnable x86_64 Linux binary, frozen Haskell dependencies, build scripts and actual evidence logs.

| Question | cabal-plan-submit | Web protocol |
|---|---|---|
| What is proved? | An accepted dependency certificate gives exactly the reachable units: closure soundness/completeness, valid root-to-target paths, vulnerable-node coverage, valid reported paths and no duplicate targets. The checker is structurally total, including cyclic graphs. | Every accepted operation follows the indexed protocol; edits require ownership, preserve other users' posts and retain owners. Rendered fragments have no raw tag openers; escaping expands by at most 6×. Accepted bodies fit their limit and transitions preserve the post-count bound. |
| What Haskell is extracted? | The complete graph/certificate checker, identity equality and vulnerability-path filter. | The actual transition function, edit operation, body/store checks and escaping/rendering functions. |
| What attacks or defects are ruled out? | Relative to an accepted certificate and its supplied graph: fabricated paths, unreachable additions, omitted reachable dependencies/vulnerable units and duplicate target entries. This does not prove an advisory is true or exploitable. | In the core: accepted anonymous writes, edits of another user's post, owner changes, raw `<` in rendered user fragments, accepted oversized bodies and post-count growth beyond an established bound. HTTP tests also reject forged/replayed tokens and unsupported commands. |
| What remains trusted? | Agda/kernel/primitives, agda2hs, GHC/runtime, MAlonzo oracle/runtime, parser/preflight, unit-ID interning, encoder, scripts/OS and advisory matching. BFS is an untrusted producer; the checker gates its results. | The same compiler/runtime base, plus credentials, token/session adapter, HTTP/JSON parsing, ASCII conversion, atomic state integration, HTML text-context placement and browser interpretation. |
| What blocks stronger verification? | No proved compiler translation; no refinement from Cabal parsing/resolution to the graph; no package/PURL quotient proof. Certificate-producer success/termination and shortest-path optimality are unproved. Peano IDs limit performance. | No proved compiler translation or byte-level parser/rendering refinement. Nonerased term indices do not extract. No whole-server CPU/heap/DoS or cryptographic authentication theorem. |
| What could become an upstream PR? | Explicit errors for missing IDs/incomplete items; an optional certificate-checking API; later a proof that merging package/PURL identities preserves required edges. Existing #49 was already fixed by #50. | An agda2hs regression and fix for config-sensitive build invalidation; documented safe-source extraction; eventually a carefully scoped retained-index/GADT feature. No upstream issues/PRs were posted. |

## Actual validation

- **Experiment 1:** 6,000 successful generated cases across six QuickCheck properties, 36 upstream examples, malformed/forged-certificate regressions, and real plans with 43, 96 and 256 units. Compared with `Data.Graph`, existing `Hgs.Why`, and independent Agda/MAlonzo execution. A supplied cryptonite advisory produces a real checked dependency path.
- **Experiment 2:** 12,000 generated cases across six properties; 122 recorded HTTP command responses plus escaping, unchanged-state, headers, chunking, media-type and endpoint checks. The live server accepts script-like input as post data and emits escaped HTML text. Bob's unauthorized edit fails; replay after logout fails.
- Both use Agda 2.8.0 with `--safe --double-check`; agda2hs 1.5 at `fc9b069b3e36d9e36a02f6f6e8f1284661f2fcfa`; GHC 9.6.6; cabal-install 3.12.1.0. The extraction backend embeds Agda 2.8.0.2. See each archive's exact report, source commit and logs.

`claims.json` distinguishes theorem checking, totality, generated tests and integration tests. The reports record commands, exit codes, assumptions, source/generated/binary hashes and unverified links. A changed generated file was deliberately detected as stale. Hashes identify bytes; they do not prove correct translation or authenticity. Neither experiment supplies semantic-preservation certification for extraction or native compilation.

## Most useful next step

**Make agda2hs extraction cache-safe and auditable.** A real config-only change here returned success while retaining incompatible old Haskell. The included minimal reproducer shows the stale output, GHC failure and successful forced rebuild. The source freshness check considers generated Haskell versus Agda interfaces; it must also account for backend configuration/options. Start with that small regression/fix, then document a supported safe-source extraction workflow with pinned configuration and explicit evidence bindings.

For application work, the dependency certificate checker is the stronger immediate adoption candidate: it adds a useful guarantee without replacing the existing search algorithm. For research, byte-level decoder/renderer refinements would close a meaningful web boundary. Retaining selected GADT indices would improve Haskell API guarantees, but is a larger compiler feature.

The result is **two checked executable cores influencing real Haskell behavior**. Neither whole application is fully formally verified.
