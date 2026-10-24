# What this buys

Research was limited to primary documentation and selected implementation files. None of the other systems was rebuilt or formally audited here.

| Approach | Static / proved guarantees | Runtime enforcement and trust | Cost / difference |
|---|---|---|---|
| Original Experiment 2 | Agda proves one-command protocol legality, ownership, glyph escaping and size invariants. | Haskell parses requests, authenticates and invokes extracted `execute`. | No client programs, authority attenuation or private-data channel. Preserved here. |
| This experiment | Agda proves accepted-program authorization at every intermediate step, grant-source confinement, complete observer noninterference, public noninterference, event budget and syntax origin. Indexed proof relations describe actual runtime transitions. | Every external client goes through the extracted interpreter; parser, login offers, bearer binding, commits, compilers and response routing remain trusted. | Tiny finite language; no general effects, recursion, private conditions or private-to-public conversion. Haskell constructors alone do not exclude malformed protocol programs. |
| Guardians | Structured workflows, symbolic/taint and automaton checks over declared tools and policies; Z3-based checking described by the project. This is not an Agda proof of those tools. | Executor also checks allowlist, preconditions, automaton state and budget before calling tools. Tool specifications and real effects must match. | More useful general workflow language. We use an even smaller closed instruction set and prove its interpreter, but cannot control arbitrary external tools. |
| Elba | Haskell-generated agent code must typecheck in a restricted Safe Haskell environment; IFC example uses LIO/DCLabel and trusted bridges. | `LBAC` uses hint/GHC, a selected tool environment and subagent bounds. IFC wrappers taint labels and enforce write-integrity checks. TCB modules implement effects and label operations. | Much more expressive Haskell programs and dynamic labels. Our stronger advantage is an application-specific, universal theorem relating actual transitions, source grants and cross-user results; our expressiveness is much lower. |
| TACIT | Scala capture checking and tracked capabilities constrain code in a permitted compiler/library subset. Classified values constrain captures in mapping operations. | Compiler/validator, capability library, trusted wrappers and effect implementations remain trusted. Untyped HTTP clients still need a server gate. | Better integration with a general language. We do not prove Scala checking weaker or unsound; we prove a deliberately smaller interpreter with precise application invariants. |

Ordinary Haskell ADTs can encode the same syntax, and GADTs can rule out many state mistakes in trusted clients. Neither prevents a remote client sending arbitrary bytes, and neither alone proves that **every** accepted interpreter trace preserves ownership, authority sources or a relational information-flow property. Those quantified semantic theorems are the useful extra evidence from Agda. They still do not verify the Haskell compiler or adapter.

LIO supports useful effectful IFC beyond this demonstration. Our immutable vault and rejection of all private conditions make noninterference substantially easier. An SMT-backed verified checker could establish similar bounded policies; there is no evidence that Agda is uniquely necessary. Its benefit here is kernel-checkable, unbounded-by-test-size proofs over a total interpreter, with the implementation itself extracted. The deployment gap remains material.

## Ideas reused, not imported guarantees

* [Ouroboros typed-protocols](https://github.com/IntersectMBO/typed-protocols): explicit state/message transitions and protocol agency. We retain indexed evidence in Agda and runtime-check the extracted ADTs; we do not claim preserved Haskell state indices.
* [Ur/Web, Chlipala POPL 2015](https://adam.chlipala.net/papers/UrWebPOPL15/UrWebPOPL15.pdf): code/data separation and restrictive typed interfaces. Our renderer covers a smaller text-only context; there is no typed SQL subsystem.
* [Project Everest / EverParse](https://project-everest.github.io/everparse/): verified parsers reduce a boundary our JSON adapter still leaves unproved. No Everest component is used here.
* [Meijer, Guardians of the Agents](https://cacm.acm.org/practice/guardians-of-the-agents/), Universalis and Automind: language-based restrictions and controlled agent programs are relevant design ideas. Public author descriptions were inspected; an accessible implementation establishing their claimed enforcement was not audited. We do not claim equivalence to those systems.

## Implementation sources inspected

* [Guardians](https://github.com/metareflection/guardians/tree/59e52d9f1cbefdb344245304e260e647489a647b), README and `src/guardians/execute.py`.
* [Elba](https://github.com/timothytmzhou/elba/tree/5232ae4a22ac2f1580e605e38d28bde524e5381c), `core/LBAC.hs`, `core/Env.hs`, `core/core.cabal`, `examples/ifc/lib/IFC.hs` and `Policy.hs`. The IFC wrapper explicitly uses trusted LIO internals; that defines a trust boundary, not by itself a discovered defect.
* [TACIT](https://github.com/lampepfl/tacit/tree/9b036bcd25915ac26b684413b2a61b3c133963f6), README and `library/impl/ClassifiedImpl.scala`. Trusted capture-library internals do not constitute an automatic sandbox for arbitrary compiled Scala or JavaScript.

**Most useful next upstream change:** config-aware agda2hs cache invalidation with the included regression. **Most useful next application step:** a small verified wire decoder and an extracted transaction/response policy, reducing the adapter assumptions before adding a larger language. Retained indexed/GADT extraction would help typed Haskell callers but would not remove the need to validate remote clients.
