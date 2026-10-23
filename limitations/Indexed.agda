{-# OPTIONS --erasure #-}
module Indexed where
open import Haskell.Prim
data Phase : Type where Anon Member : Phase
{-# COMPILE AGDA2HS Phase #-}
data Command : Phase → Type where
  Read : ∀ {s} → Command s
  Create : Command Member
{-# COMPILE AGDA2HS Command #-}
