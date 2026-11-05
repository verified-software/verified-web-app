# Verified tenant access

A small Agda-defined authorization policy, extracted to Haskell and Scala 3. The Haskell library is used by the existing forum server to protect tenant-scoped posts. The server is a **local demonstration**, not a production deployment: authentication uses two hardcoded demo accounts, and there is no TLS or persistent database.

## Library

`VerifiedTenant` exposes opaque `TenantId`, `Principal` and `Scoped` types. It accepts tenant IDs of 1–32 lowercase ASCII letters, digits or hyphens. An authenticated member can read their tenant; only a writer can write.

```haskell
import VerifiedTenant

readIfAllowed :: TenantId -> TenantId -> a -> Maybe a
readIfAllowed authenticatedTenant storedTenant value =
  guarded (member authenticatedTenant Reader) Read (forTenant storedTenant value)
```

`authenticatedTenant` must come from trusted authentication, and `storedTenant` must describe the actual stored record. `forTenant` does not verify a database row. Scope database queries by tenant too; do not attach a request's tenant ID to a record loaded without checking its ownership.

## Run

```sh
cabal build exe:verified-forum
cabal run verified-forum -- 18080
```

In another terminal:

```sh
curl -sS localhost:18080/command -H 'Content-Type: application/json' \
  -d '{"op":"login","user":"alice","password":"alice-demo"}'
# Copy the token from the response.
TOKEN='paste-token-here'
curl -sS localhost:18080/tenants/alpha/command -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" -d '{"op":"create","body":"my tenant post"}'
curl -sS localhost:18080/tenants/alpha/posts -H "Authorization: Bearer $TOKEN"
```

Alice belongs to `alpha`; Bob (`bob/bob-demo`) belongs to `beta`. Cross-tenant reads and writes fail. Tenant routes require an existing bearer session; create one through `/command`. Tenant `GET` requires Reader or Writer; tenant `POST` requires Writer. The old `/posts`, `/command` and `/program` routes operate on a separate public forum.

Failed batches roll back post changes. If the interpreter rolls back a program that contains logout or permission reduction anywhere, it also revokes the session, even if that branch did not run. Log in again after such a failure. Requests rejected before the interpreter runs do not invoke this rule.

## Verify

The pinned Haskell toolchain is GHC 9.6.6, cabal-install 3.12.1.0, Agda 2.8.0 and agda2hs 1.5 at commit `fc9b069b3e36d9e36a02f6f6e8f1284661f2fcfa`. `scripts/bootstrap.sh` installs Agda and agda2hs when GHC/Cabal are already available.

```sh
make verify                         # proofs, extraction, Haskell and HTTP tests
make check-evidence                 # compare saved hashes; does not rerun proofs
```

For the same `agda/TenantCore.agda` in Scala, install `agda2scala` at commit `9d59b857e9390434c60f9a0e2cf1d8324b35f91b` and Scala 3.3.6, put them on `PATH`, then run:

```sh
make scala-check                   # regenerate, compile and run 930 policy cases
```

The Scala output uses `scala/MaybeCompat.scala`, a small handwritten mapping from Agda's `Maybe` to Scala's `Option`. `scalac` emits unreachable-pattern warnings. See `SECURITY.md` for exact guarantees, threat examples and trust boundaries.
