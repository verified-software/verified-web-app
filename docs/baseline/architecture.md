# Architecture and protocol

```mermaid
flowchart TD
  H["HTTP + bounded JSON decoder"] --> A["Credential/session adapter\nsrc/Server.hs"]
  A --> C["Extracted transition function\nForumCore.execute"]
  C --> S["In-memory store + sessions"]
  S --> R["Extracted escaping → HTML text\nForumCore.render"]
```

`execute` and `render` are the proved executable core. HTTP parsing, credentials, session tokens, state storage, ASCII conversion and the browser are outside that proof boundary.

```mermaid
stateDiagram-v2
  [*] --> Guest
  Guest --> Guest: read
  Guest --> Logged: checked authentication
  Logged --> Logged: read / create / owned edit
  Logged --> Guest: logout
```

Invalid transitions are rejected. Edit additionally requires an existing owned post and bounded body. Haskell accepts ordinary request ADTs; Agda's indexed `Step` relation certifies every accepted transition.
