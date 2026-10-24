{-# OPTIONS --safe --erasure #-}
module ClientModel where
open import Haskell.Prim
open import Haskell.Prim.Maybe
import ForumCore as F
open import ClientCore

-- A first-order observation adapter for the independent MAlonzo test oracle.
-- No alternate interpreter. Avoids unsafeCoerce of erased polymorphic Maybe
-- values in our Haskell bridge by exposing zero/one-element grant lists.
first : List Grant → Maybe Grant
first [] = Nothing
first (g ∷ _) = Just g

data FlatResult : Type where
  FlatRefused : Error → FlatResult
  FlatFinished : List Grant → List Grant → List F.Post → List Event → FlatResult
flatten : Result → FlatResult
flatten (Refused e) = FlatRefused e
flatten (Finished ctx ps es) = FlatFinished (grantList (current ctx)) (grantList (pending ctx)) ps es

data FlatStep : Type where
  FlatRejected : Error → FlatStep
  FlatApplied : List Grant → List Grant → List F.Post → Event → FlatStep
flattenStep : StepResult → FlatStep
flattenStep (Rejected e) = FlatRejected e
flattenStep (Applied ctx ps e) = FlatApplied (grantList (current ctx)) (grantList (pending ctx)) ps e

runModel : F.Count → F.Count → F.Count → Program → List Grant → List Grant → List F.Post → Vault → FlatResult
runModel tl pl fuel program c p posts vault = flatten (run tl pl fuel program (Ctx (first c) (first p)) posts vault)
stepModel : F.Count → F.Count → Op → List Grant → List Grant → List F.Post → Vault → FlatStep
stepModel tl pl op c p posts vault = flattenStep (step tl pl (Ctx (first c) (first p)) op posts vault)
confinedModel : List Grant → List Grant → List Grant → Bool
confinedModel c p allowed = confined (Ctx (first c) (first p)) allowed

data FlatTransaction : Type where
  FlatRollback : Error → List F.Post → FlatTransaction
  FlatCommit : List Grant → List Grant → List F.Post → List Event → FlatTransaction
flattenTransaction : Transaction → FlatTransaction
flattenTransaction (Rollback err ps) = FlatRollback err ps
flattenTransaction (Commit ctx ps es) = FlatCommit (grantList (current ctx)) (grantList (pending ctx)) ps es
transactionModel : F.Count → F.Count → F.Count → Program → List Grant → List Grant → List F.Post → Vault → FlatTransaction
transactionModel tl pl fuel program c p posts vault = flattenTransaction (transaction tl pl fuel program (Ctx (first c) (first p)) posts vault)
