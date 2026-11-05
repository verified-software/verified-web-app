# Security scope

## Threat addressed

A logged-in user changes a tenant identifier in a URL to read or edit another tenant's records. The server derives the member's tenant and role from its session and calls the extracted `TenantCore.guarded` before returning or mutating the selected tenant store. The HTTP test checks both the legacy-command and program routes. This is the class of missing tenant checks described in [SigNoz issue #11830](https://github.com/SigNoz/signoz/issues/11830), which reports cross-organization access by rule ID. It is not a claim that this code fixes or prevents the complete SigNoz vulnerability.

[OWASP Top 10:2025 A01](https://top10.owasp.org/2025/A01_2025-Broken_Access_Control/) recommends server-side deny-by-default authorization and record ownership checks. [CISA's October 30, 2026 KEV notice](https://content.govdelivery.com/accounts/USDHSCISA/bulletins/4311c77) describes actively exploited missing-authentication and predictable-identifier vulnerabilities; this example is motivated by the category, not a reproduction of those CVEs.

## What Agda checks

`agda/TenantProofs.agda` is checked with `--safe --double-check --ignore-interfaces` against the executable `TenantCore` definitions:

- `guarded-isolation`: if a member receives a `Scoped` value, the value's tenant ID equals the member's tenant ID.
- `anonymous-denied` and `reader-write-denied`: those operations are rejected.
- `guarded-denied`: for fixed principal, tenant and action, changing a denied payload leaves the `guarded` result unchanged.
- `member-can-read` and `writer-can-write`: correct same-tenant requests are accepted.

The earlier forum proofs still check: accepted writes require authority, edits preserve other owners' posts, capability attenuation cannot invent authority, private data has the documented limited noninterference properties, and executed program steps fit the fuel budget. These statements are about the Agda core and finite, defined inputs. The differential tests compare generated Haskell with Agda's separate MAlonzo translation; tests do not prove compiler correctness.

## Trusted boundaries

- Authentication must supply a genuine server-side principal, role and tenant. `member` is public so trusted application code can create a principal; this library does not sandbox hostile code in the server process.
- `Scoped` protects the **label provided to it**. The application must bind that label to the actual stored record and ensure database queries, joins and updates are scoped. The example uses a per-tenant in-memory map; production SQL, caching and concurrency are not verified.
- The Haskell/Scala wrappers, tenant-name conversion, HTTP parsing and routing, session map, token entropy, compilers and runtimes are unverified. The HTTP tests exercise these boundaries but do not prove them. Scala's `MaybeCompat.scala` is handwritten and trusted; Scala `null` and external code are outside the Agda model.
- Input is bounded by the HTTP adapter: tenant names at 32 ASCII characters, request bodies at 4/16 KiB, program depth 24, syntax nodes 128 and interpreter budget at most 32. The Agda fuel theorem bounds core operations, not parsing, allocation, network work, timing or wall-clock time.
- Demo credentials, session expiry, TLS, production authentication, CSRF for any future cookie-based client, real database permissions and deployment configuration are not provided. A failed multi-action batch still rolls back a requested logout or rights reduction; use a successful single-action logout and verify session deletion. Do not deploy the demo as a production service.

## Compiler limits

Agda disallows backend `COMPILE` pragmas in safe modules. `scripts/prepare.sh` checks canonical safe sources, creates a separate extraction view with annotations and uses `--ignore-interfaces`. It removes one trailing blank line from the generated tenant Haskell; it makes no semantic edits. There is no proof that either compiler preserves semantics. agda2scala emits `Maybe`/`Just`/`Nothing` without an implementation for the Haskell compatibility type; `scala/MaybeCompat.scala` supplies `Option`, `Some` and `None`. The generated Scala also contains redundant match branches, producing four Scala 3.3.6 warnings. The included Scala test exhausts 930 small, non-null policy inputs; it does not verify the backend or provide a Scala HTTP server.
