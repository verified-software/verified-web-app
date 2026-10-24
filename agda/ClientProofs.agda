{-# OPTIONS --safe --erasure #-}
module ClientProofs where
open import Haskell.Prim
open import Haskell.Prim.Bool
open import Haskell.Prim.Maybe
import ForumCore as F
import ForumProofs as FP
open import ClientCore

andL : ∀ x y → (x && y) ≡ True → x ≡ True
andL True y p = refl
andL False y ()
andR : ∀ x y → (x && y) ≡ True → y ≡ True
andR True y p = p
andR False y ()
andI : ∀ x y → x ≡ True → y ≡ True → (x && y) ≡ True
andI .True .True refl refl = refl

below-refl : ∀ g → below g g ≡ True
below-refl (GrantC F.Alice Viewer) = refl
below-refl (GrantC F.Alice Editor) = refl
below-refl (GrantC F.Bob Viewer) = refl
below-refl (GrantC F.Bob Editor) = refl

initial-confined : ∀ ctx → confined ctx (sources ctx) ≡ True
initial-confined (Ctx Nothing Nothing) = refl
initial-confined (Ctx Nothing (Just g)) rewrite below-refl g = refl
initial-confined (Ctx (Just g) Nothing) rewrite below-refl g = refl
initial-confined (Ctx (Just g) (Just h)) rewrite below-refl g | below-refl h with below h g
... | True = refl
... | False = refl

covered-viewer : ∀ u r allowed → covered (GrantC u r) allowed ≡ True → covered (GrantC u Viewer) allowed ≡ True
covered-viewer u r [] ()
covered-viewer u r (GrantC v s ∷ rest) yes with F.sameUser u v
... | True = refl
... | False = covered-viewer u r rest yes

data StepConfined (allowed : List Grant) : StepResult → Type where
  rejected : ∀ {e} → StepConfined allowed (Rejected e)
  applied : ∀ {ctx ps e} → confined ctx allowed ≡ True → StepConfined allowed (Applied ctx ps e)

commit-confined : ∀ ctx allowed e result → confined ctx allowed ≡ True → StepConfined allowed (commitForum ctx e result)
commit-confined ctx allowed e (F.Denied err) yes = rejected
commit-confined ctx allowed e (F.Accepted s ps) yes = applied yes

write-confined : ∀ tl pl ctx mutation ps value allowed → confined ctx allowed ≡ True
  → StepConfined allowed (writeValue tl pl ctx mutation ps value)
write-confined tl pl ctx mutation ps Unavailable allowed yes = rejected
write-confined tl pl ctx mutation ps (Evaluated (Classified u text)) allowed yes = rejected
write-confined tl pl ctx mutation ps (Evaluated (Public text)) allowed yes with canWrite ctx
... | False = rejected
... | True = commit-confined ctx allowed (writeEvent ctx mutation)
  (F.execute tl pl (session ctx) (request mutation text) ps) yes

-- Every primitive preserves origin/attenuation relative to an arbitrary source
-- grant list. Neither expressions nor program data can add an authority source.
step-confined : ∀ tl pl ctx op ps vault allowed → confined ctx allowed ≡ True
  → StepConfined allowed (step tl pl ctx op ps vault)
step-confined tl pl ctx ReadPublic ps vault allowed yes = applied yes
step-confined tl pl (Ctx Nothing Nothing) SignIn ps vault allowed yes = rejected
step-confined tl pl (Ctx Nothing (Just g)) SignIn ps vault allowed yes = applied
  (andI (covered g allowed) True yes refl)
step-confined tl pl (Ctx (Just g) p) SignIn ps vault allowed yes = rejected
step-confined tl pl (Ctx Nothing p) SignOut ps vault allowed yes = rejected
step-confined tl pl (Ctx (Just g) p) SignOut ps vault allowed yes = applied refl
step-confined tl pl (Ctx Nothing p) ReadOnly ps vault allowed yes = rejected
step-confined tl pl (Ctx (Just (GrantC u r)) p) ReadOnly ps vault allowed yes = applied
  (andI (covered (GrantC u Viewer) allowed) True
    (covered-viewer u r allowed (andL (covered (GrantC u r) allowed) (maybeCovered p allowed) yes)) refl)
step-confined tl pl ctx (Publish expr) ps vault allowed yes =
  write-confined tl pl ctx Add ps (evaluate ctx expr vault) allowed yes
step-confined tl pl ctx (Revise i expr) ps vault allowed yes =
  write-confined tl pl ctx (Change i) ps (evaluate ctx expr vault) allowed yes
step-confined tl pl ctx (Inspect expr) ps vault allowed yes with evaluate ctx expr vault
... | Unavailable = rejected
... | Evaluated v = applied yes

data ConfinedResult (allowed : List Grant) : Result → Type where
  refused : ∀ {e} → ConfinedResult allowed (Refused e)
  finished : ∀ {ctx ps es} → confined ctx allowed ≡ True → ConfinedResult allowed (Finished ctx ps es)

prepend-confined : ∀ allowed e result → ConfinedResult allowed result → ConfinedResult allowed (prepend e result)
prepend-confined allowed e (Refused err) refused = refused
prepend-confined allowed e (Finished ctx ps es) (finished yes) = finished yes

continue-confined : ∀ allowed k result → StepConfined allowed result
  → (∀ ctx ps → confined ctx allowed ≡ True → ConfinedResult allowed (k ctx ps))
  → ConfinedResult allowed (continue k result)
continue-confined allowed k (Rejected err) rejected safe = refused
continue-confined allowed k (Applied ctx ps e) (applied yes) safe =
  prepend-confined allowed e (k ctx ps) (safe ctx ps yes)

choose-confined : ∀ allowed k value → (∀ b → ConfinedResult allowed (k b)) → ConfinedResult allowed (choose k value)
choose-confined allowed k Unavailable safe = refused
choose-confined allowed k (Evaluated (Classified u text)) safe = refused
choose-confined allowed k (Evaluated (Public [])) safe = prepend-confined allowed (Tested True) (k True) (safe True)
choose-confined allowed k (Evaluated (Public (_ ∷ _))) safe = prepend-confined allowed (Tested False) (k False) (safe False)

run-confined : ∀ tl pl fuel program ctx ps vault allowed → confined ctx allowed ≡ True
  → ConfinedResult allowed (run tl pl fuel program ctx ps vault)
run-confined tl pl fuel Stop ctx ps vault allowed yes = finished yes
run-confined tl pl F.Zero (Invoke op rest) ctx ps vault allowed yes = refused
run-confined tl pl F.Zero (Choose expr left right) ctx ps vault allowed yes = refused
run-confined tl pl (F.More fuel) (Invoke op rest) ctx ps vault allowed yes =
  continue-confined allowed (λ next posts → run tl pl fuel rest next posts vault)
    (step tl pl ctx op ps vault) (step-confined tl pl ctx op ps vault allowed yes)
    (λ next posts confinedNext → run-confined tl pl fuel rest next posts vault allowed confinedNext)
run-confined tl pl (F.More fuel) (Choose expr left right) ctx ps vault allowed yes =
  choose-confined allowed (λ b → if b then run tl pl fuel left ctx ps vault else run tl pl fuel right ctx ps vault)
    (evaluate ctx expr vault) λ where
      True → run-confined tl pl fuel left ctx ps vault allowed yes
      False → run-confined tl pl fuel right ctx ps vault allowed yes

data Budget (fuel : F.Count) : Result → Type where
  refusal : ∀ {e} → Budget fuel (Refused e)
  bounded : ∀ {ctx ps es} → FP.Fits fuel es → Budget fuel (Finished ctx ps es)

prepend-budget : ∀ fuel e result → Budget fuel result → Budget (F.More fuel) (prepend e result)
prepend-budget fuel e (Refused err) refusal = refusal
prepend-budget fuel e (Finished ctx ps es) (bounded fit) = bounded (FP.one fit)

continue-budget : ∀ fuel k result → (∀ ctx ps → Budget fuel (k ctx ps)) → Budget (F.More fuel) (continue k result)
continue-budget fuel k (Rejected e) safe = refusal
continue-budget fuel k (Applied ctx ps e) safe = prepend-budget fuel e (k ctx ps) (safe ctx ps)

choose-budget : ∀ fuel k value → (∀ b → Budget fuel (k b)) → Budget (F.More fuel) (choose k value)
choose-budget fuel k Unavailable safe = refusal
choose-budget fuel k (Evaluated (Classified u text)) safe = refusal
choose-budget fuel k (Evaluated (Public [])) safe = prepend-budget fuel (Tested True) (k True) (safe True)
choose-budget fuel k (Evaluated (Public (_ ∷ _))) safe = prepend-budget fuel (Tested False) (k False) (safe False)

-- The trace records EVERY accepted primitive and branch, one entry each.
-- Consequently primitive operations alone are also bounded by fuel.
run-budget : ∀ tl pl fuel program ctx ps vault → Budget fuel (run tl pl fuel program ctx ps vault)
run-budget tl pl fuel Stop ctx ps vault = bounded FP.none
run-budget tl pl F.Zero (Invoke op rest) ctx ps vault = refusal
run-budget tl pl F.Zero (Choose expr left right) ctx ps vault = refusal
run-budget tl pl (F.More fuel) (Invoke op rest) ctx ps vault =
  continue-budget fuel (λ next posts → run tl pl fuel rest next posts vault) (step tl pl ctx op ps vault)
    (λ next posts → run-budget tl pl fuel rest next posts vault)
run-budget tl pl (F.More fuel) (Choose expr left right) ctx ps vault =
  choose-budget fuel (λ b → if b then run tl pl fuel left ctx ps vault else run tl pl fuel right ctx ps vault)
    (evaluate ctx expr vault) λ where
      True → run-budget tl pl fuel left ctx ps vault
      False → run-budget tl pl fuel right ctx ps vault

-- Logout removes both current and offered authority. A second SignIn cannot
-- reuse the previously offered grant without a NEW trusted HTTP decision.
logout-revokes : ∀ g pendingGrant ps → signOut (Ctx (Just g) pendingGrant) ps ≡ Applied (Ctx Nothing Nothing) ps SessionClosed
logout-revokes g pendingGrant ps = refl
relogin-after-logout-denied : ∀ ps → signIn (Ctx Nothing Nothing) ps ≡ Rejected NoLoginOffer
relogin-after-logout-denied ps = refl

record EditAuthorized (ctx : Context) (i : F.Count) (before after : List F.Post) : Type where
  constructor authorizedEdit
  field
    writePermission : canWrite ctx ≡ True
    ownership : FP.EditGuarantee (actor ctx) i before after

MutationSafe : Context → Mutation → List F.Post → List F.Post → Type
MutationSafe ctx Add before after = canWrite ctx ≡ True
MutationSafe ctx (Change i) before after = EditAuthorized ctx i before after

data SafeMutation (ctx : Context) (m : Mutation) (before : List F.Post) : StepResult → Type where
  deniedMutation : ∀ {e} → SafeMutation ctx m before (Rejected e)
  allowedMutation : ∀ {next after e} → MutationSafe ctx m before after → SafeMutation ctx m before (Applied next after e)

commit-add-safe : ∀ u p before result → SafeMutation (Ctx (Just (GrantC u Editor)) p) Add before
  (commitForum (Ctx (Just (GrantC u Editor)) p) (Posted u) result)
commit-add-safe u p before (F.Denied e) = deniedMutation
commit-add-safe u p before (F.Accepted s after) = allowedMutation refl

write-safe : ∀ tl pl ctx m before value → SafeMutation ctx m before (writeValue tl pl ctx m before value)
write-safe tl pl ctx m before Unavailable = deniedMutation
write-safe tl pl ctx m before (Evaluated (Classified u text)) = deniedMutation
write-safe tl pl (Ctx Nothing p) m before (Evaluated (Public text)) = deniedMutation
write-safe tl pl (Ctx (Just (GrantC u Viewer)) p) m before (Evaluated (Public text)) = deniedMutation
write-safe tl pl (Ctx (Just (GrantC u Editor)) p) Add before (Evaluated (Public text)) =
  commit-add-safe u p before (F.execute tl pl (F.Logged u) (F.CreatePost text) before)
write-safe tl pl (Ctx (Just (GrantC u Editor)) p) (Change i) before (Evaluated (Public text))
  with F.execute tl pl (F.Logged u) (F.EditPost i text) before in executed
... | F.Denied e = deniedMutation
... | F.Accepted s after = allowedMutation (authorizedEdit refl
  (FP.accepted-edit-secure tl pl u i text before s after executed))

AuthorityFor : Context → Op → List F.Post → List F.Post → Type
AuthorityFor ctx (Publish expr) before after = MutationSafe ctx Add before after
AuthorityFor ctx (Revise i expr) before after = MutationSafe ctx (Change i) before after
AuthorityFor ctx _ before after = ⊤

data SafeStep (ctx : Context) (op : Op) (before : List F.Post) : StepResult → Type where
  deniedStep : ∀ {e} → SafeStep ctx op before (Rejected e)
  allowedStep : ∀ {next after e} → AuthorityFor ctx op before after → SafeStep ctx op before (Applied next after e)

publish-safe : ∀ ctx expr before result → SafeMutation ctx Add before result → SafeStep ctx (Publish expr) before result
publish-safe ctx expr before .(Rejected _) deniedMutation = deniedStep
publish-safe ctx expr before .(Applied _ _ _) (allowedMutation yes) = allowedStep yes
revise-safe : ∀ ctx i expr before result → SafeMutation ctx (Change i) before result → SafeStep ctx (Revise i expr) before result
revise-safe ctx i expr before .(Rejected _) deniedMutation = deniedStep
revise-safe ctx i expr before .(Applied _ _ _) (allowedMutation yes) = allowedStep yes

-- This is authorization of the ACTUAL executable step, including recursive
-- post ownership checks inherited from the original proved ForumCore.edit.
step-authorized : ∀ tl pl ctx op before vault → SafeStep ctx op before (step tl pl ctx op before vault)
step-authorized tl pl ctx ReadPublic before vault = allowedStep tt
step-authorized tl pl (Ctx Nothing Nothing) SignIn before vault = deniedStep
step-authorized tl pl (Ctx Nothing (Just g)) SignIn before vault = allowedStep tt
step-authorized tl pl (Ctx (Just g) p) SignIn before vault = deniedStep
step-authorized tl pl (Ctx Nothing p) SignOut before vault = deniedStep
step-authorized tl pl (Ctx (Just g) p) SignOut before vault = allowedStep tt
step-authorized tl pl (Ctx Nothing p) ReadOnly before vault = deniedStep
step-authorized tl pl (Ctx (Just g) p) ReadOnly before vault with g
... | GrantC u r = allowedStep tt
step-authorized tl pl ctx (Publish expr) before vault = publish-safe ctx expr before
  (writeValue tl pl ctx Add before (evaluate ctx expr vault))
  (write-safe tl pl ctx Add before (evaluate ctx expr vault))
step-authorized tl pl ctx (Revise i expr) before vault = revise-safe ctx i expr before
  (writeValue tl pl ctx (Change i) before (evaluate ctx expr vault))
  (write-safe tl pl ctx (Change i) before (evaluate ctx expr vault))
step-authorized tl pl ctx (Inspect expr) before vault with evaluate ctx expr vault
... | Unavailable = deniedStep
... | Evaluated v = allowedStep tt

get-authorization : ∀ ctx op before result next after e → SafeStep ctx op before result
  → result ≡ Applied next after e → AuthorityFor ctx op before after
get-authorization ctx op before .(Applied next after e) next after e (allowedStep yes) refl = yes

-- A proof trace follows the exact runtime event trace and records authorization
-- at EACH executed primitive, not merely a property of the final context.
data AuthorizedTrace (tl pl : F.Count) (vault : Vault) : Context → List F.Post → Program → Context → List F.Post → List Event → Type where
  stopped : ∀ {ctx ps} → AuthorizedTrace tl pl vault ctx ps Stop ctx ps []
  invoked : ∀ {ctx before op rest next middle final after e es}
    → step tl pl ctx op before vault ≡ Applied next middle e
    → AuthorityFor ctx op before middle
    → AuthorizedTrace tl pl vault next middle rest final after es
    → AuthorizedTrace tl pl vault ctx before (Invoke op rest) final after (e ∷ es)
  choseLeft : ∀ {ctx before expr left right final after es}
    → evaluate ctx expr vault ≡ Evaluated (Public [])
    → AuthorizedTrace tl pl vault ctx before left final after es
    → AuthorizedTrace tl pl vault ctx before (Choose expr left right) final after (Tested True ∷ es)
  choseRight : ∀ {ctx before expr left right final after es glyph glyphs}
    → evaluate ctx expr vault ≡ Evaluated (Public (glyph ∷ glyphs))
    → AuthorizedTrace tl pl vault ctx before right final after es
    → AuthorizedTrace tl pl vault ctx before (Choose expr left right) final after (Tested False ∷ es)

-- Every accepted executable program has such an authorization proof trace.
program-authorized : ∀ tl pl fuel program ctx before vault final after es
  → run tl pl fuel program ctx before vault ≡ Finished final after es
  → AuthorizedTrace tl pl vault ctx before program final after es
program-authorized tl pl fuel Stop ctx before vault .ctx .before .[] refl = stopped
program-authorized tl pl F.Zero (Invoke op rest) ctx before vault final after es ()
program-authorized tl pl F.Zero (Choose expr left right) ctx before vault final after es ()
program-authorized tl pl (F.More fuel) (Invoke op rest) ctx before vault final after es accepted
  with step tl pl ctx op before vault in stepped
... | Rejected err = impossible accepted where
  impossible : Refused err ≡ Finished final after es → AuthorizedTrace tl pl vault ctx before (Invoke op rest) final after es
  impossible ()
... | Applied next middle e with run tl pl fuel rest next middle vault in executed
...   | Refused err = impossible accepted where
  impossible : Refused err ≡ Finished final after es → AuthorizedTrace tl pl vault ctx before (Invoke op rest) final after es
  impossible ()
...   | Finished final' after' tail with accepted
...     | refl = invoked stepped
  (get-authorization ctx op before (step tl pl ctx op before vault) next middle e
    (step-authorized tl pl ctx op before vault) stepped)
  (program-authorized tl pl fuel rest next middle vault final' after' tail executed)
program-authorized tl pl (F.More fuel) (Choose expr left right) ctx before vault final after es accepted
  with evaluate ctx expr vault in evaluated
... | Unavailable = impossible accepted where
  impossible : Refused NoPrivateAccess ≡ Finished final after es → AuthorizedTrace tl pl vault ctx before (Choose expr left right) final after es
  impossible ()
... | Evaluated (Classified who text) = impossible accepted where
  impossible : Refused SecretControl ≡ Finished final after es → AuthorizedTrace tl pl vault ctx before (Choose expr left right) final after es
  impossible ()
... | Evaluated (Public []) with run tl pl fuel left ctx before vault in executed
...   | Refused err = impossible accepted where
  impossible : Refused err ≡ Finished final after es → AuthorizedTrace tl pl vault ctx before (Choose expr left right) final after es
  impossible ()
...   | Finished final' after' tail with accepted
...     | refl = choseLeft evaluated (program-authorized tl pl fuel left ctx before vault final' after' tail executed)
program-authorized tl pl (F.More fuel) (Choose expr left right) ctx before vault final after es accepted | Evaluated (Public (_ ∷ _))
  with run tl pl fuel right ctx before vault in executed
... | Refused err = impossible accepted where
  impossible : Refused err ≡ Finished final after es → AuthorizedTrace tl pl vault ctx before (Choose expr left right) final after es
  impossible ()
... | Finished final' after' tail with accepted
...   | refl = choseRight evaluated (program-authorized tl pl fuel right ctx before vault final' after' tail executed)
