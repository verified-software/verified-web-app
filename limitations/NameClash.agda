module NameClash where
open import Haskell.Prim
data OrderingLetter : Type where LT : OrderingLetter
letter : OrderingLetter
letter = LT
{-# COMPILE AGDA2HS OrderingLetter #-}
{-# COMPILE AGDA2HS letter #-}
