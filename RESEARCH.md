# Ideas used

Short source review; no external framework is claimed as part of our proof.

| Source | Concrete lesson used |
|---|---|
| [Ouroboros network specification](https://ouroboros-network.cardano.intersectmbo.org/pdfs/network-spec/network-spec.pdf) | Messages describe state transitions; agency says who may send. Our `Step` relation states permitted session transitions. HTTP transport/agency is not verified. |
| [typed-protocols Core.hs](https://github.com/IntersectMBO/typed-protocols/blob/main/typed-protocols/src/Network/TypedProtocol/Core.hs) | `Message ps from to` indexes legal edges; codecs are a separate boundary. We prove a runtime checker because ordinary nonerased term indices cannot be extracted by agda2hs. |
| [Chlipala, Ur/Web: A Simple Model for Programming the Web, POPL 2015](https://adam.chlipala.net/papers/UrWebPOPL15/UrWebPOPL15.pdf) | Keep data separate from executable syntax. We omit SQL/script/raw-HTML operations and use a proved escaping function in a fixed text context. We do not reproduce Ur/Web's compiler guarantees. |
| [PureScript Effect](https://book.purescript.org/chapter8.html), [FFI](https://book.purescript.org/chapter10.html) | Effect types organize permitted operations, while foreign JavaScript can invoke browser effects. Typed source is not a JavaScript sandbox. PureScript is a plausible future client, not an implementation target used here. |
| [Miller, Robust Composition](https://www.erights.org/talks/thesis/index.html) | Restrict authority exposed to less-trusted components. A bearer session is resolved server-side; the request language supplies no arbitrary URL or effect. This does not establish a general capability-security theorem. |
| [agda2hs features](https://agda.github.io/agda2hs/features.html) | Use erased proof/index information and existing Prelude configuration; inspect emitted Haskell and compile it. |

Design choices above are our application of these ideas. None imports the associated systems' security guarantees.
