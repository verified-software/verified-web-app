# Compiler findings and remaining boundaries

Pinned backend: agda2hs 1.5, `fc9b069b3e36d9e36a02f6f6e8f1284661f2fcfa`, embedded Agda 2.8.0.2. Proof checker: standalone Agda 2.8.0. GHC 9.6.6. No upstream source modifications or PRs.

## Reproduced backend limitations

`bash scripts/check-limitations.sh` runs the minimal examples in `limitations/` and records the actual diagnostics.

| Reproducer | Expected / actual | Classification and smallest improvement |
|---|---|---|
| `Indexed.agda` | Want a state-indexed command datatype in generated Haskell. Actual diagnostic: `Not supported: indexed datatypes`. | Missing retained-index feature. `src/Agda2Hs/Compile/Data.hs`, `allIndicesErased`. Use ordinary runtime ADTs plus checked indexed proof relations; erased indices extract but do not protect the Haskell API. Retaining them would need supported GADT translation. |
| `ErasedIndexed.agda` | Erased type index extracts and GHC accepts it. | Supported workaround, with explicitly weaker Haskell API typing. We do not equate erased indices with runtime enforcement. |
| `NameClash.agda` | Valid Agda constructor LT generates ambiguous Haskell under implicit Prelude. | Namespace/configuration integration: `src/Agda2Hs/Config.hs`, `Compile/Imports.hs`. Existing `prelude.hiding: [LT]` fixes it; no compiler patch needed. |
| `config-cache.sh` | Change only backend YAML; expect output to regenerate. Actual: successful invocation preserves stale Haskell, still rejected by GHC. | Incremental-build defect at `src/Agda2Hs/Compile.hs`, `moduleSetup` freshness check. A fingerprint of backend config/options in cache validity plus this regression test is the smallest useful upstream change. We force `--ignore-interfaces` for **every** extraction. |
| `SafePragma.agda` | Safe checking rejects a backend COMPILE pragma. | Safe-mode restriction, not a claimed compiler defect. Check canonical sources safely, append extraction annotations in a separate mechanical view. |

Related indexed-type issues: [#80](https://github.com/agda/agda2hs/issues/80) and [#437](https://github.com/agda/agda2hs/issues/437). Their existence does not mean retained term indices are supported by this pinned version. No exact config-cache issue was established; do not treat that as proof no such issue exists.

## Safe source and extraction view

Agda safe mode refuses backend COMPILE pragmas. Canonical executable sources and all proofs remain safe. `scripts/prepare.sh` mechanically removes the `--safe` option from a source copy, appends `scripts/*pragmas.agda.inc`, then extracts it. Function bodies and imports are unchanged. Generated Haskell is never patched by hand. This workflow carries no theorem of agda2hs correctness; differential testing checks a separate MAlonzo compilation against generated Haskell.

## MAlonzo bridge

The independent backend represents polymorphic Maybe payloads as `AgdaAny`. Rather than adding `unsafeCoerce` to the handwritten oracle bridge, `ClientModel.agda` exposes zero/one grant lists and first-order flat results, converting Maybe **inside Agda**. It invokes the same actual `run`, `step` and `confined`; there is no second implementation. `scripts/MakeClientOracle.hs` reads generated constructor names, writes explicit conversions and fails if names are missing/ambiguous. MAlonzo's own erased runtime casts remain trusted. This is backend representation friction, not an agda2hs defect.

## Ordinary environment/development failures

The reset environment lacked GHC, Agda and agda2hs. Rebuilding required native GMP headers, a local libtinfo link and making GHC's installed `unlit` executable. These are environment setup failures, not source-language defects. New Haskell test syntax errors and a WAI `vault` field clash were corrected without changing verified semantics. Early failed build logs remain under `evidence/development`.

The final evidence guard rejected a successful Cabal test invocation whose log contained only build output. We did not infer test execution from that exit code. The driver now executes both built test binaries directly and requires all 17 QuickCheck success lines. The source-install bootstrap also initially inherited the application's `transformers-compat ==0.8` freeze, conflicting with Agda 2.8.0's `monad-control` dependency. `--ignore-project` and the backend's compatible `0.7.2` constraint resolve the solver; both failed and corrected dry-run logs are retained. The bootstrap installer was solver-checked, not rerun as a full clean-machine installation; actual proof/build/test execution used the restored pinned tools.

JSON parsing and rendering-to-browser correspondence remain the largest unproved application boundaries. The HTML theorem covers the glyph renderer and safe text placement assumption; it does not model the browser. The fuel theorem covers semantic events, not runtime cost. All details are in [PROPERTIES.md](PROPERTIES.md).
