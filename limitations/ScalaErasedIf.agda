{-# OPTIONS --safe --erasure #-}
module ScalaErasedIf where
open import Haskell.Prim

-- Haskell.Prim.if_then_else_ introduces erased equality-proof lambdas.
ifChoice : Bool → Bool
ifChoice b = if b then True else False

caseChoice : Bool → Bool
caseChoice True = True
caseChoice False = False

equivalent : ∀ b → ifChoice b ≡ caseChoice b
equivalent True = refl
equivalent False = refl
