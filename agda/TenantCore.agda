{-# OPTIONS --safe --erasure #-}
module TenantCore where

open import Haskell.Prim
open import Haskell.Prim.Bool
open import Haskell.Prim.Maybe

data Role : Type where
  Reader Writer : Role

data Principal : Type where
  Anonymous : Principal
  Member : List Bool → Role → Principal

data Action : Type where
  Read Write : Action

data Scoped (a : Type) : Type where
  Resource : List Bool → a → Scoped a

sameId : List Bool → List Bool → Bool
sameId [] [] = True
sameId [] (_ ∷ _) = False
sameId (_ ∷ _) [] = False
sameId (True ∷ xs) (True ∷ ys) = sameId xs ys
sameId (False ∷ xs) (False ∷ ys) = sameId xs ys
sameId _ _ = False

permitted : Principal → List Bool → Action → Bool
permitted Anonymous target action = False
permitted (Member source Reader) target Read = sameId source target
permitted (Member source Reader) target Write = False
permitted (Member source Writer) target action = sameId source target

guarded : {a : Type} → Principal → Action → Scoped a → Maybe a
guarded principal action (Resource tenant value) =
  if permitted principal tenant action then Just value else Nothing
