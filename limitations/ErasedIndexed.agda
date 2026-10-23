{-# OPTIONS --erasure #-}
module ErasedIndexed where
open import Haskell.Prim
data Phase : Type where Anon Member : Phase
data Command : @0 Phase → Type where
  Read : ∀ {@0 s} → Command s
  Create : Command Member
{-# COMPILE AGDA2HS Command deriving (Eq, Show) #-}
