{-# OPTIONS --safe --erasure #-}
module ClientSyntax where
open import Haskell.Prim
open import Haskell.Prim.Bool
open import Haskell.Prim.Maybe
import ForumCore as F
import ForumProofs as FP
open import ClientCore
open import ClientProofs using (AuthorizedTrace; stopped; invoked; choseLeft; choseRight; program-authorized)

data Matches : Op → Event → Type where
  read : Matches ReadPublic SawPublic
  login : ∀ {u} → Matches SignIn (SessionOpened u)
  logout : Matches SignOut SessionClosed
  restrict : Matches ReadOnly RightsReduced
  create : ∀ {expr u} → Matches (Publish expr) (Posted u)
  edit : ∀ {expr u i} → Matches (Revise i expr) (Revised u i)
  inspect : ∀ {expr value} → Matches (Inspect expr) (Displayed value)

data Emits (op : Op) : StepResult → Type where
  denial : ∀ {e} → Emits op (Rejected e)
  emission : ∀ {ctx ps e} → Matches op e → Emits op (Applied ctx ps e)

writeMatches : Mutation → Expr → Op
writeMatches Add expr = Publish expr
writeMatches (Change i) expr = Revise i expr

commit-emits : ∀ ctx mutation expr result → Emits (writeMatches mutation expr) (commitForum ctx (writeEvent ctx mutation) result)
commit-emits ctx mutation expr (F.Denied err) = denial
commit-emits ctx Add expr (F.Accepted s ps) = emission create
commit-emits ctx (Change i) expr (F.Accepted s ps) = emission edit

write-emits : ∀ tl pl ctx mutation expr ps value → Emits (writeMatches mutation expr) (writeValue tl pl ctx mutation ps value)
write-emits tl pl ctx mutation expr ps Unavailable = denial
write-emits tl pl ctx mutation expr ps (Evaluated (Classified u text)) = denial
write-emits tl pl ctx mutation expr ps (Evaluated (Public text)) with canWrite ctx
... | False = denial
... | True = commit-emits ctx mutation expr (F.execute tl pl (session ctx) (request mutation text) ps)

step-emits : ∀ tl pl ctx op ps vault → Emits op (step tl pl ctx op ps vault)
step-emits tl pl ctx ReadPublic ps vault = emission read
step-emits tl pl (Ctx Nothing Nothing) SignIn ps vault = denial
step-emits tl pl (Ctx Nothing (Just g)) SignIn ps vault = emission login
step-emits tl pl (Ctx (Just g) p) SignIn ps vault = denial
step-emits tl pl (Ctx Nothing p) SignOut ps vault = denial
step-emits tl pl (Ctx (Just g) p) SignOut ps vault = emission logout
step-emits tl pl (Ctx Nothing p) ReadOnly ps vault = denial
step-emits tl pl (Ctx (Just (GrantC u r)) p) ReadOnly ps vault = emission restrict
step-emits tl pl ctx (Publish expr) ps vault = write-emits tl pl ctx Add expr ps (evaluate ctx expr vault)
step-emits tl pl ctx (Revise i expr) ps vault = write-emits tl pl ctx (Change i) expr ps (evaluate ctx expr vault)
step-emits tl pl ctx (Inspect expr) ps vault with evaluate ctx expr vault
... | Unavailable = denial
... | Evaluated v = emission inspect

get-match : ∀ op result ctx ps e → Emits op result → result ≡ Applied ctx ps e → Matches op e
get-match op .(Applied ctx ps e) ctx ps e (emission match) refl = match

-- Event origins refer ONLY to the original Program spine, never to any Glyph
-- in Literal post content. Branches can select existing syntax, not create it.
data FromSyntax : Program → Event → Type where
  callHead : ∀ {op rest e} → Matches op e → FromSyntax (Invoke op rest) e
  callTail : ∀ {op rest e} → FromSyntax rest e → FromSyntax (Invoke op rest) e
  left : ∀ {expr yes no e} → FromSyntax yes e → FromSyntax (Choose expr yes no) e
  right : ∀ {expr yes no e} → FromSyntax no e → FromSyntax (Choose expr yes no) e
  branch : ∀ {expr yes no b} → FromSyntax (Choose expr yes no) (Tested b)

map-every : ∀ {a : Type} {p q : a → Type} {xs} → (∀ {x} → p x → q x) → FP.Every p xs → FP.Every q xs
map-every f FP.nil = FP.nil
map-every f (FP.cons p ps) = FP.cons (f p) (map-every f ps)

trace-syntax : ∀ {tl pl vault ctx ps program final after trace}
  → AuthorizedTrace tl pl vault ctx ps program final after trace → FP.Every (FromSyntax program) trace
trace-syntax stopped = FP.nil
trace-syntax {tl} {pl} {vault} {ctx} {ps} (invoked {op = op} {next = next} {middle = middle} {e = e} stepped auth rest) =
  FP.cons (callHead (get-match op (step tl pl ctx op ps vault) next middle e (step-emits tl pl ctx op ps vault) stepped))
    (map-every callTail (trace-syntax rest))
trace-syntax (choseLeft condition rest) = FP.cons branch (map-every left (trace-syntax rest))
trace-syntax (choseRight condition rest) = FP.cons branch (map-every right (trace-syntax rest))

program-no-injection : ∀ tl pl fuel program ctx ps vault final after trace
  → run tl pl fuel program ctx ps vault ≡ Finished final after trace
  → FP.Every (FromSyntax program) trace
program-no-injection tl pl fuel program ctx ps vault final after trace accepted =
  trace-syntax (program-authorized tl pl fuel program ctx ps vault final after trace accepted)
