# Attack tests

Reproduce with `bash scripts/http-tests.sh`, `bash scripts/program-http-tests.sh` and `bash scripts/observer-http-tests.sh` after building `bin/verified-forum`. Each script starts its own server(s). Full request/response evidence is in `evidence/http-tests.json`, `evidence/program-http-tests.json` and `evidence/observer-http-tests.json`; logs are under `evidence/logs`. These are tests, not proofs.

| Input / attempt | Enforcement and expected result |
|---|---|
| Anonymous create | Core `canWrite` is false; 401 NoAuthority. |
| Bob edits Alice's post | Reused `ForumCore.execute` rejects ownership mismatch; 403 ForumError EditDenied. |
| Reuse bearer after successful logout | Server deletes its mapping; replay through either endpoint is 401. Core logout also destroys the pending login offer. |
| Reuse login offer in login → logout → login | Core consumes the offer and clears it on logout; 401 NoLoginOffer. Failed batch commits nothing. |
| Reduce rights, then switch to old `/command` | Both routes call the same extracted interpreter. Viewer write attempts fail 403 through either route. |
| Inject `grant`, `rank`, `authority` fields | Exact-field JSON adapter rejects 400. Even constructing a Program value does not provide a Grant constructor inside its language. |
| Publish `{"private":"alice"}` | Even Alice cannot publish this expression: core returns 403 SecretSink. |
| Branch on private Alice data | Core returns 403 SecretControl, even when both branches are harmless. No secret-dependent branch result is exposed. |
| Bob inspects Alice's private source | Core principal check returns 403 NoPrivateAccess. Bob's own source succeeds. |
| Change Alice's secret and repeat Bob workflows | 18 paired-server comparisons retain identical HTTP statuses and JSON (only independent random login tokens omitted), plus identical public JSON/HTML. Includes denied reads, private sinks, branches, rollback, attenuation and logout. |
| Literal containing `{"op":"logout"}` and `<script>` | Accepted as one post, with exactly one created event. It does not change syntax or session. Rendering escapes the delimiters; literal `<script>` does not appear in the HTML response. |
| `fetch`, `shell`, `sql`, `eval`, `loop` | No constructors exist for these operations. Decoder rejects 400; there is no fallback to an interpreter for another language. |
| Nested / oversized program | Nesting pre-scan and byte limit reject 400/413; adapter node limit is also tested by generated decoding. These parser/resource checks are not Agda theorems. |
| Budget exhaustion after a valid write | Core returns 429 Exhausted; server commits neither the write nor any prior transition. Nonempty zero-fuel program also fails; Stop at zero succeeds. |
| Valid action followed by illegal repeated login | 409 BadState and atomic rollback, including the earlier write. |
| Malformed JSON, ambiguous expression, fractional/negative/excess budget, fractional ID, wrong value type | Decoder rejects 400 before execution. The core is independently invoked only after decoding and still checks authority. |

The byte parser may accept duplicate object keys according to Aeson's behavior; no duplicate-key security theorem is claimed. The final ADT must still pass core authorization. Clients cannot put session grant objects into the accepted grammar.

Both failed-logout and failed-attenuation batches are explicitly tested: the old session/authority remains. This is the documented atomic-batch contract, not irreversible revocation halfway through a refused request. Use a successful standalone logout/restrict operation when revocation must take effect.

Private drafts are fake data, returned only in authenticated program responses. This prevents specified cross-user and private-to-public flows **inside a fixed program**, not an authorized client reading their own draft and copying it elsewhere later. Capability tokens remain bearer credentials; stealing one defeats the adapter's identity assumption. Timing, HTTP/runtime denial of service, OS compromise and malicious server-side Haskell are outside the model.
