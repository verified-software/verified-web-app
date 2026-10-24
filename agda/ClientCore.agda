{-# OPTIONS --safe --erasure #-}
module ClientCore where
open import Haskell.Prim
open import Haskell.Prim.Bool
open import Haskell.Prim.Maybe
import ForumCore as F

data Rank : Type where Viewer Editor : Rank
data Grant : Type where GrantC : F.User → Rank → Grant
data Context : Type where Ctx : Maybe Grant → Maybe Grant → Context

current : Context → Maybe Grant
current (Ctx c _) = c
pending : Context → Maybe Grant
pending (Ctx _ p) = p
grantUser : Grant → F.User
grantUser (GrantC u _) = u

session : Context → F.Session
session (Ctx Nothing _) = F.Guest
session (Ctx (Just (GrantC u _)) _) = F.Logged u
actor : Context → F.User
actor (Ctx Nothing _) = F.Alice -- Never used to authorize an anonymous write.
actor (Ctx (Just (GrantC u _)) _) = u
canWrite : Context → Bool
canWrite (Ctx (Just (GrantC _ Editor)) _) = True
canWrite _ = False

-- Grants are supplied by the server after authenticating a request. They are
-- deliberately absent from the client language. ReadOnly can only attenuate.
data Expr : Type where
  Literal : List F.Glyph → Expr
  PrivateOf : F.User → Expr
data Vault : Type where VaultC : List F.Glyph → List F.Glyph → Vault
secret : Vault → F.User → List F.Glyph
secret (VaultC a b) F.Alice = a
secret (VaultC a b) F.Bob = b
data Value : Type where
  Public : List F.Glyph → Value
  Classified : F.User → List F.Glyph → Value
data Evaluation : Type where
  Unavailable : Evaluation
  Evaluated : Value → Evaluation

evaluate : Context → Expr → Vault → Evaluation
evaluate ctx (Literal text) vault = Evaluated (Public text)
evaluate (Ctx Nothing _) (PrivateOf u) vault = Unavailable
evaluate (Ctx (Just g) _) (PrivateOf u) vault = if F.sameUser (grantUser g) u
  then Evaluated (Classified u (secret vault u)) else Unavailable

data Op : Type where
  ReadPublic SignIn SignOut ReadOnly : Op
  Publish : Expr → Op
  Revise : F.Count → Expr → Op
  Inspect : Expr → Op
data Program : Type where
  Stop : Program
  Invoke : Op → Program → Program
  Choose : Expr → Program → Program → Program

data Error : Type where
  NoAuthority BadState NoLoginOffer NoPrivateAccess SecretSink SecretControl Exhausted : Error
  ForumError : F.Error → Error
data Event : Type where
  SawPublic SessionClosed RightsReduced : Event
  SessionOpened Posted : F.User → Event
  Revised : F.User → F.Count → Event
  Displayed : Value → Event
  Tested : Bool → Event
data StepResult : Type where
  Rejected : Error → StepResult
  Applied : Context → List F.Post → Event → StepResult
data Result : Type where
  Refused : Error → Result
  Finished : Context → List F.Post → List Event → Result

data Mutation : Type where
  Add : Mutation
  Change : F.Count → Mutation
request : Mutation → List F.Glyph → F.Request
request Add text = F.CreatePost text
request (Change i) text = F.EditPost i text
writeEvent : Context → Mutation → Event
writeEvent ctx Add = Posted (actor ctx)
writeEvent ctx (Change i) = Revised (actor ctx) i

commitForum : Context → Event → F.Result → StepResult
commitForum ctx e (F.Denied err) = Rejected (ForumError err)
commitForum ctx e (F.Accepted _ ps) = Applied ctx ps e

writeValue : F.Count → F.Count → Context → Mutation → List F.Post → Evaluation → StepResult
writeValue tl pl ctx mutation ps Unavailable = Rejected NoPrivateAccess
writeValue tl pl ctx mutation ps (Evaluated (Classified _ _)) = Rejected SecretSink
writeValue tl pl ctx mutation ps (Evaluated (Public text)) = if canWrite ctx
  then commitForum ctx (writeEvent ctx mutation) (F.execute tl pl (session ctx) (request mutation text) ps)
  else Rejected NoAuthority

inspectValue : Context → List F.Post → Evaluation → StepResult
inspectValue ctx ps Unavailable = Rejected NoPrivateAccess
inspectValue ctx ps (Evaluated v) = Applied ctx ps (Displayed v)

signIn : Context → List F.Post → StepResult
signIn (Ctx Nothing Nothing) ps = Rejected NoLoginOffer
signIn (Ctx Nothing (Just g)) ps = Applied (Ctx (Just g) Nothing) ps (SessionOpened (grantUser g))
signIn (Ctx (Just _) _) ps = Rejected BadState
signOut : Context → List F.Post → StepResult
signOut (Ctx Nothing _) ps = Rejected BadState
signOut (Ctx (Just _) _) ps = Applied (Ctx Nothing Nothing) ps SessionClosed
readOnly : Context → List F.Post → StepResult
readOnly (Ctx Nothing _) ps = Rejected NoAuthority
readOnly (Ctx (Just (GrantC u _)) _) ps = Applied (Ctx (Just (GrantC u Viewer)) Nothing) ps RightsReduced

step : F.Count → F.Count → Context → Op → List F.Post → Vault → StepResult
step tl pl ctx ReadPublic ps vault = Applied ctx ps SawPublic
step tl pl ctx SignIn ps vault = signIn ctx ps
step tl pl ctx SignOut ps vault = signOut ctx ps
step tl pl ctx ReadOnly ps vault = readOnly ctx ps
step tl pl ctx (Publish expr) ps vault = writeValue tl pl ctx Add ps (evaluate ctx expr vault)
step tl pl ctx (Revise i expr) ps vault = writeValue tl pl ctx (Change i) ps (evaluate ctx expr vault)
step tl pl ctx (Inspect expr) ps vault = inspectValue ctx ps (evaluate ctx expr vault)

prepend : Event → Result → Result
prepend e (Refused err) = Refused err
prepend e (Finished ctx ps es) = Finished ctx ps (e ∷ es)
continue : (Context → List F.Post → Result) → StepResult → Result
continue k (Rejected err) = Refused err
continue k (Applied ctx ps e) = prepend e (k ctx ps)
choose : (Bool → Result) → Evaluation → Result
choose k Unavailable = Refused NoPrivateAccess
choose k (Evaluated (Classified _ _)) = Refused SecretControl
choose k (Evaluated (Public [])) = prepend (Tested True) (k True)
choose k (Evaluated (Public (_ ∷ _))) = prepend (Tested False) (k False)

-- Every Invoke and Choose consumes one fuel unit, including failed attempts.
-- Stop is free. No recursion/loop, arbitrary effects or code evaluation exist.
run : F.Count → F.Count → F.Count → Program → Context → List F.Post → Vault → Result
run tl pl fuel Stop ctx ps vault = Finished ctx ps []
run tl pl F.Zero (Invoke op rest) ctx ps vault = Refused Exhausted
run tl pl F.Zero (Choose expr left right) ctx ps vault = Refused Exhausted
run tl pl (F.More fuel) (Invoke op rest) ctx ps vault =
  continue (λ next posts → run tl pl fuel rest next posts vault) (step tl pl ctx op ps vault)
run tl pl (F.More fuel) (Choose expr left right) ctx ps vault =
  choose (λ empty → if empty then run tl pl fuel left ctx ps vault else run tl pl fuel right ctx ps vault)
    (evaluate ctx expr vault)

-- Public projection removes only classified payloads. It retains outcomes,
-- control decisions, context/authority, post state and trace length.
redactValue : Value → Value
redactValue (Public text) = Public text
redactValue (Classified u _) = Classified u []
redactEvent : Event → Event
redactEvent (Displayed v) = Displayed (redactValue v)
redactEvent e = e
redactEvents : List Event → List Event
redactEvents [] = []
redactEvents (e ∷ es) = redactEvent e ∷ redactEvents es
publicView : Result → Result
publicView (Refused err) = Refused err
publicView (Finished ctx ps es) = Finished ctx ps (redactEvents es)

-- A decidable origin/attenuation relation, also extracted for runtime checks.
rankBelow : Rank → Rank → Bool
rankBelow Viewer _ = True
rankBelow Editor Viewer = False
rankBelow Editor Editor = True
below : Grant → Grant → Bool
below (GrantC u r) (GrantC v s) = F.sameUser u v && rankBelow r s
covered : Grant → List Grant → Bool
covered g [] = False
covered g (source ∷ rest) = below g source || covered g rest
maybeCovered : Maybe Grant → List Grant → Bool
maybeCovered Nothing allowed = True
maybeCovered (Just g) allowed = covered g allowed
confined : Context → List Grant → Bool
confined (Ctx c p) allowed = maybeCovered c allowed && maybeCovered p allowed

grantList : Maybe Grant → List Grant
grantList Nothing = []
grantList (Just g) = g ∷ []
sources : Context → List Grant
sources (Ctx c p) = F.append (grantList c) (grantList p)
