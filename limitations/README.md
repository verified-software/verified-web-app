# Reproduced limitations

All observations use agda2hs `fc9b069b3e36d9e36a02f6f6e8f1284661f2fcfa`, version 1.5/Agda 2.8.0.2, GHC 9.6.6. Run `bash scripts/check-limitations.sh` after setting the pinned tools on PATH.

| Case | Expected / actual | Relevant implementation | Smallest correction / improvement |
|---|---|---|---|
| `Indexed.agda` | A state-indexed command language would ideally extract with retained Haskell state types. Actual: `Not supported: indexed datatypes`. | `src/Agda2Hs/Compile/Data.hs`, `allIndicesErased` rejects nonerased indices. | Use ordinary runtime ADTs and prove accepted transitions; or erase indices (see successful `ErasedIndexed.agda`) while acknowledging the Haskell API loses them. Retained GADT indices would be a larger feature. |
| `NameClash.agda` | Valid Agda generates Haskell, but GHC rejects the unqualified `LT` use due to implicit Prelude import. | `src/Agda2Hs/Config.hs` and `src/Agda2Hs/Compile/Imports.hs` configure imports. | Existing `prelude.hiding: [LT]` configuration fixes it. Normal namespace integration, not a claimed new compiler bug. |
| `config-cache.sh` | Changing backend config should regenerate output. Actual: second invocation succeeds and preserves identical stale Haskell; GHC still fails. | `src/Agda2Hs/Compile.hs`, `moduleSetup`, compares output-file and Agda-interface timestamps. | Force `--ignore-interfaces` now. Proposed upstream change: fingerprint backend configuration/options in freshness decisions, with this scenario as regression test. |

Indexed-type related issues [#80](https://github.com/agda/agda2hs/issues/80) and [#437](https://github.com/agda/agda2hs/issues/437) are closed; erased indices work in this version. They do not imply retained term indices work. Searches for config/cache and `ignore-interfaces` found no matching incremental-config issue; that is not an exhaustive issue audit.

The config reproducer forces initial generation, changes only external configuration, compares outputs, shows the GHC ambiguity, then forces regeneration and successfully typechecks the corrected output. Logs and generated examples are included under `evidence/logs` and `build`.

Safe Agda also rejects `COMPILE` pragmas, as reproduced in Experiment 1. Our mechanical extraction view preserves executable definitions and appends only backend annotations. No upstream compiler was patched, and no issue/PR was submitted. Ordinary development errors and early failed build logs are retained separately.
