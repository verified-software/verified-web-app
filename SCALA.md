# Optional Scala 3 probe

The Haskell application was finished and checkpointed first. Then unmodified [agda2scala](https://github.com/dancewithheart/agda2scala/tree/902859c0e7ad7f45126f9825634d19f43b55881d) **0.1.0.4**, using Agda **2.8.0.2**, was built successfully. `scripts/scala-probe.sh` reused the actual core with only backend annotations changed. Sources, output and logs are included under `build/scala-view`, `build/scala` and `evidence/scala`.

**Result: partial source generation, no working Scala interpreter.** Backend exit status is zero, but `evaluate`, `writeValue` and `run` are replaced by `SeUnhandled` / `UnsupportedTerm (Lam ...)` TODO comments. The problem is the erased equality-proof lambda introduced by agda2hs's `Haskell.Prim.if_then_else_`. There are also unresolved cross-module names and the custom `Haskell.Prim.Maybe` representation to integrate. No Scala compiler execution or Scala server is claimed.

Minimal reproducer: `limitations/ScalaErasedIf.agda`. Its ordinary Boolean case-split equivalent emits a method; its proof-lambda `if` version does not. Agda safely proves their equivalence. Compiler sites: `src/Agda/Compiler/Scala/Compile/Terms.hs` (`compileIfThenElse` / term lowering) and `Render/PrintScala3.hs` (`SeUnhandled` rendered as a comment).

Smallest improvements: lower erased lambdas correctly; report unsupported requested definitions as an explicit failed compilation rather than a successful partial artifact. Explicit case splits are a legitimate equivalent source formulation, demonstrated in the reproducer. They would require a separate checked source revision across this core, plus library/import integration. We did not rewrite the working Haskell core or patch upstream for this stretch goal.

To reproduce after building the pinned backend:

```sh
bash scripts/scala-probe.sh /absolute/path/to/agda2scala
```

The backend can share `toolchain/agda2hs.project.freeze`'s Agda version/flags and `aeson ==2.2.5.1` when built with GHC 9.6.6; the optional backend itself is a separate source package. See `evidence/scala/backend-build.log` and `result.json`.

Scala 3 capture checking/TACIT would still require explicit capability-safe library interfaces and validation of untyped HTTP input. Generating Scala does not automatically preserve Agda proofs, synthesize capture annotations or establish a TACIT guarantee. No Scala-specific security claim is made.
