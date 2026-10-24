{-# OPTIONS --safe --erasure #-}
module ClientFlow where
open import Haskell.Prim
open import Haskell.Prim.Bool
open import Haskell.Prim.Maybe
import ForumCore as F
open import ClientCore
open import ClientProofs using (andL; StepConfined; rejected; applied; step-confined)

sym : ∀ {a : Type} {x y : a} → x ≡ y → y ≡ x
sym refl = refl
trans : ∀ {a : Type} {x y z : a} → x ≡ y → y ≡ z → x ≡ z
trans refl q = q
cong₂ : ∀ {a b c : Type} (f : a → b → c) {x x' y y'} → x ≡ x' → y ≡ y' → f x y ≡ f x' y'
cong₂ f refl refl = refl

data StepLow : StepResult → StepResult → Type where
  failure : ∀ {e} → StepLow (Rejected e) (Rejected e)
  success : ∀ {ctx ps e e'} → redactEvent e ≡ redactEvent e' → StepLow (Applied ctx ps e) (Applied ctx ps e')

step-low-refl : ∀ result → StepLow result result
step-low-refl (Rejected e) = failure
step-low-refl (Applied ctx ps e) = success refl

-- Evaluating private content can change a labelled private payload, never
-- authority, a public mutation, a branch decision, or a failure reason.
step-low : ∀ tl pl ctx op ps first second → StepLow (step tl pl ctx op ps first) (step tl pl ctx op ps second)
step-low tl pl ctx ReadPublic ps first second = success refl
step-low tl pl ctx SignIn ps first second = step-low-refl (signIn ctx ps)
step-low tl pl ctx SignOut ps first second = step-low-refl (signOut ctx ps)
step-low tl pl ctx ReadOnly ps first second = step-low-refl (readOnly ctx ps)
step-low tl pl ctx (Publish (Literal text)) ps first second =
  step-low-refl (writeValue tl pl ctx Add ps (Evaluated (Public text)))
step-low tl pl (Ctx Nothing p) (Publish (PrivateOf u)) ps first second = failure
step-low tl pl (Ctx (Just g) p) (Publish (PrivateOf u)) ps first second with F.sameUser (grantUser g) u
... | True = failure
... | False = failure
step-low tl pl ctx (Revise i (Literal text)) ps first second =
  step-low-refl (writeValue tl pl ctx (Change i) ps (Evaluated (Public text)))
step-low tl pl (Ctx Nothing p) (Revise i (PrivateOf u)) ps first second = failure
step-low tl pl (Ctx (Just g) p) (Revise i (PrivateOf u)) ps first second with F.sameUser (grantUser g) u
... | True = failure
... | False = failure
step-low tl pl ctx (Inspect (Literal text)) ps first second = success refl
step-low tl pl (Ctx Nothing p) (Inspect (PrivateOf u)) ps first second = failure
step-low tl pl (Ctx (Just g) p) (Inspect (PrivateOf u)) ps first second with F.sameUser (grantUser g) u
... | True = success refl
... | False = failure

view-prepend : ∀ e result → publicView (prepend e result) ≡ prepend (redactEvent e) (publicView result)
view-prepend e (Refused err) = refl
view-prepend e (Finished ctx ps es) = refl

prepend-low : ∀ e e' result result' → redactEvent e ≡ redactEvent e'
  → publicView result ≡ publicView result'
  → publicView (prepend e result) ≡ publicView (prepend e' result')
prepend-low e e' result result' eventEq resultEq = trans (view-prepend e result)
  (trans (cong₂ prepend eventEq resultEq) (sym (view-prepend e' result')))

continue-low : ∀ k k' result result' → StepLow result result'
  → (∀ ctx ps → publicView (k ctx ps) ≡ publicView (k' ctx ps))
  → publicView (continue k result) ≡ publicView (continue k' result')
continue-low k k' (Rejected e) .(Rejected e) failure rec = refl
continue-low k k' (Applied ctx ps e) (Applied .ctx .ps e') (success eventEq) rec =
  prepend-low e e' (k ctx ps) (k' ctx ps) eventEq (rec ctx ps)

-- Termination-sensitive noninterference of the designated PUBLIC channel.
-- Retains success/failure, errors, branch outcomes, trace length, authority and
-- the entire public post store. Only classified payloads are projected away.
-- The program and all its literal/public inputs are fixed between the runs.
public-noninterference : ∀ tl pl fuel program ctx ps first second
  → publicView (run tl pl fuel program ctx ps first) ≡ publicView (run tl pl fuel program ctx ps second)
public-noninterference tl pl fuel Stop ctx ps first second = refl
public-noninterference tl pl F.Zero (Invoke op rest) ctx ps first second = refl
public-noninterference tl pl F.Zero (Choose expr left right) ctx ps first second = refl
public-noninterference tl pl (F.More fuel) (Invoke op rest) ctx ps first second =
  continue-low (λ next posts → run tl pl fuel rest next posts first)
    (λ next posts → run tl pl fuel rest next posts second)
    (step tl pl ctx op ps first) (step tl pl ctx op ps second)
    (step-low tl pl ctx op ps first second)
    (λ next posts → public-noninterference tl pl fuel rest next posts first second)
public-noninterference tl pl (F.More fuel) (Choose (Literal []) left right) ctx ps first second =
  prepend-low (Tested True) (Tested True) (run tl pl fuel left ctx ps first) (run tl pl fuel left ctx ps second)
    refl (public-noninterference tl pl fuel left ctx ps first second)
public-noninterference tl pl (F.More fuel) (Choose (Literal (_ ∷ _)) left right) ctx ps first second =
  prepend-low (Tested False) (Tested False) (run tl pl fuel right ctx ps first) (run tl pl fuel right ctx ps second)
    refl (public-noninterference tl pl fuel right ctx ps first second)
public-noninterference tl pl (F.More fuel) (Choose (PrivateOf u) left right) (Ctx Nothing p) ps first second = refl
public-noninterference tl pl (F.More fuel) (Choose (PrivateOf u) left right) (Ctx (Just g) p) ps first second
  with F.sameUser (grantUser g) u
... | True = refl
... | False = refl

same-user-sound : ∀ u v → F.sameUser u v ≡ True → u ≡ v
same-user-sound F.Alice F.Alice yes = refl
same-user-sound F.Alice F.Bob ()
same-user-sound F.Bob F.Alice ()
same-user-sound F.Bob F.Bob yes = refl

data OwnAccess : Context → F.User → Type where
  own : ∀ {u rank offer} → OwnAccess (Ctx (Just (GrantC u rank)) offer) u

-- A successfully evaluated private value belongs to the current principal,
-- including for malicious programs requesting a different user's identifier.
private-access-owned : ∀ ctx requested vault who text
  → evaluate ctx (PrivateOf requested) vault ≡ Evaluated (Classified who text)
  → OwnAccess ctx who
private-access-owned (Ctx Nothing p) requested vault who text ()
private-access-owned (Ctx (Just (GrantC u rank)) p) requested vault who text yes
  with F.sameUser u requested in authorized
... | False = impossible yes where
  impossible : Unavailable ≡ Evaluated (Classified who text) → OwnAccess (Ctx (Just (GrantC u rank)) p) who
  impossible ()
... | True rewrite same-user-sound u requested authorized with yes
...   | refl = own

private-sink-denied : ∀ tl pl ctx mutation ps who text
  → writeValue tl pl ctx mutation ps (Evaluated (Classified who text)) ≡ Rejected SecretSink
private-sink-denied tl pl ctx mutation ps who text = refl

private-control-denied : ∀ k who text → choose k (Evaluated (Classified who text)) ≡ Refused SecretControl
private-control-denied k who text = refl

cong : ∀ {a b : Type} (f : a → b) {x y} → x ≡ y → f x ≡ f y
cong f refl = refl

single-source-owner : ∀ g observer → covered g (GrantC observer Editor ∷ []) ≡ True → grantUser g ≡ observer
single-source-owner (GrantC u rank) observer yes with F.sameUser u observer in eq
... | True = same-user-sound u observer eq
... | False = impossible yes where
  impossible : False ≡ True → u ≡ observer
  impossible ()

secret-at : ∀ first second requested observer → requested ≡ observer
  → secret first observer ≡ secret second observer → secret first requested ≡ secret second requested
secret-at first second requested .requested refl eq = eq

evaluate-observer : ∀ ctx expr first second observer
  → confined ctx (GrantC observer Editor ∷ []) ≡ True
  → secret first observer ≡ secret second observer
  → evaluate ctx expr first ≡ evaluate ctx expr second
evaluate-observer ctx (Literal text) first second observer authorized equalPrivate = refl
evaluate-observer (Ctx Nothing p) (PrivateOf requested) first second observer authorized equalPrivate = refl
evaluate-observer (Ctx (Just (GrantC u rank)) p) (PrivateOf requested) first second observer authorized equalPrivate
  with F.sameUser u requested in allowed
... | False = refl
... | True = cong (λ text → Evaluated (Classified requested text))
  (secret-at first second requested observer
    (trans (sym (same-user-sound u requested allowed))
      (single-source-owner (GrantC u rank) observer
        (andL (covered (GrantC u rank) (GrantC observer Editor ∷ []))
          (maybeCovered p (GrantC observer Editor ∷ [])) authorized))) equalPrivate)

step-observer : ∀ tl pl ctx op ps first second observer
  → confined ctx (GrantC observer Editor ∷ []) ≡ True
  → secret first observer ≡ secret second observer
  → step tl pl ctx op ps first ≡ step tl pl ctx op ps second
step-observer tl pl ctx ReadPublic ps first second observer auth eq = refl
step-observer tl pl ctx SignIn ps first second observer auth eq = refl
step-observer tl pl ctx SignOut ps first second observer auth eq = refl
step-observer tl pl ctx ReadOnly ps first second observer auth eq = refl
step-observer tl pl ctx (Publish expr) ps first second observer auth eq =
  cong (writeValue tl pl ctx Add ps) (evaluate-observer ctx expr first second observer auth eq)
step-observer tl pl ctx (Revise i expr) ps first second observer auth eq =
  cong (writeValue tl pl ctx (Change i) ps) (evaluate-observer ctx expr first second observer auth eq)
step-observer tl pl ctx (Inspect expr) ps first second observer auth eq =
  cong (inspectValue ctx ps) (evaluate-observer ctx expr first second observer auth eq)

continue-observer : ∀ allowed k k' result result' → result ≡ result' → StepConfined allowed result
  → (∀ ctx ps → confined ctx allowed ≡ True → k ctx ps ≡ k' ctx ps)
  → continue k result ≡ continue k' result'
continue-observer allowed k k' (Rejected e) .(Rejected e) refl rejected rec = refl
continue-observer allowed k k' (Applied ctx ps e) .(Applied ctx ps e) refl (applied auth) rec =
  cong (prepend e) (rec ctx ps auth)

choose-observer : ∀ k k' value value' → value ≡ value' → (∀ b → k b ≡ k' b) → choose k value ≡ choose k' value'
choose-observer k k' Unavailable .Unavailable refl rec = refl
choose-observer k k' (Evaluated (Classified u text)) .(Evaluated (Classified u text)) refl rec = refl
choose-observer k k' (Evaluated (Public [])) .(Evaluated (Public [])) refl rec = cong (prepend (Tested True)) (rec True)
choose-observer k k' (Evaluated (Public (c ∷ cs))) .(Evaluated (Public (c ∷ cs))) refl rec = cong (prepend (Tested False)) (rec False)

-- Stronger than public projection: an observer holding only THEIR authority
-- cannot distinguish changes to other users' private data in the FULL result,
-- including that observer's private response payloads. Their own secret and
-- the initial public state/program/literal inputs agree in the two runs.
observer-noninterference : ∀ tl pl fuel program ctx ps first second observer
  → confined ctx (GrantC observer Editor ∷ []) ≡ True
  → secret first observer ≡ secret second observer
  → run tl pl fuel program ctx ps first ≡ run tl pl fuel program ctx ps second
observer-noninterference tl pl fuel Stop ctx ps first second observer auth eq = refl
observer-noninterference tl pl F.Zero (Invoke op rest) ctx ps first second observer auth eq = refl
observer-noninterference tl pl F.Zero (Choose expr yes no) ctx ps first second observer auth eq = refl
observer-noninterference tl pl (F.More fuel) (Invoke op rest) ctx ps first second observer auth eq =
  continue-observer (GrantC observer Editor ∷ []) (λ next posts → run tl pl fuel rest next posts first)
    (λ next posts → run tl pl fuel rest next posts second)
    (step tl pl ctx op ps first) (step tl pl ctx op ps second)
    (step-observer tl pl ctx op ps first second observer auth eq)
    (step-confined tl pl ctx op ps first (GrantC observer Editor ∷ []) auth)
    (λ next posts nextAuth → observer-noninterference tl pl fuel rest next posts first second observer nextAuth eq)
observer-noninterference tl pl (F.More fuel) (Choose expr yes no) ctx ps first second observer auth eq =
  choose-observer (λ b → if b then run tl pl fuel yes ctx ps first else run tl pl fuel no ctx ps first)
    (λ b → if b then run tl pl fuel yes ctx ps second else run tl pl fuel no ctx ps second)
    (evaluate ctx expr first) (evaluate ctx expr second) (evaluate-observer ctx expr first second observer auth eq) λ where
      True → observer-noninterference tl pl fuel yes ctx ps first second observer auth eq
      False → observer-noninterference tl pl fuel no ctx ps first second observer auth eq
