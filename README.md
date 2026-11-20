## Development requirements

- GHC 9.10.3
- Cabal
- Agda 2.9.0
- agda2hs (currently requires the Agda 2.8 compiler library)
- Git, Bash, jq
- Python 3 for existing e2e/HTTP integration tests

In the future: Scala and agda2scala

### Build

```sh
cabal update
cabal build exe:verified-forum
```

### Check Agda proofs and regenerate Haskell

```sh
bash scripts/prepare.sh
```

### Test

```sh
cabal test all
```

### End to end tests

```sh
cabal build exe:verified-forum
cabal run verified-forum -- 18080
```

In another terminal:

```sh
curl -sS localhost:18080/command -H 'Content-Type: application/json' \
  -d '{"op":"login","user":"alice","password":"alice-demo"}'
```

Copy token and set in variable `TOKEN='paste-token-here'`

```sh
curl -sS localhost:18080/tenants/alpha/command -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" -d '{"op":"create","body":"my tenant post"}'
curl -sS localhost:18080/tenants/alpha/posts -H "Authorization: Bearer $TOKEN"
```

Alice belongs to `alpha`; Bob (`bob/bob-demo`) belongs to `beta`. Cross-tenant reads and writes fail. Tenant routes require an existing bearer session; create one through `/command`. Tenant `GET` requires Reader or Writer; tenant `POST` requires Writer. The old `/posts`, `/command` and `/program` routes operate on a separate public forum.

Failed batches roll back post changes. If the interpreter rolls back a program that contains logout or permission reduction anywhere, it also revokes the session, even if that branch did not run. Log in again after such a failure. Requests rejected before the interpreter runs do not invoke this rule.

### Full verification

* make verify
  - checks Agda proofs
  - extracts executable Haskell
  - builds the application
  - runs property tests
  - run e2e integration HTTP tests
```sh
make verify
```

* validates file hashes:
```sh
make check-evidence
```
