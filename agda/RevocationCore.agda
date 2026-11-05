{-# OPTIONS --safe --erasure #-}
module RevocationCore where

open import Haskell.Prim
open import Haskell.Prim.Bool
open import Haskell.Prim.Maybe
import ClientCore as C

mentionsRevocation : C.Program → Bool
mentionsRevocation C.Stop = False
mentionsRevocation (C.Invoke C.SignOut rest) = True
mentionsRevocation (C.Invoke C.ReadOnly rest) = True
mentionsRevocation (C.Invoke _ rest) = mentionsRevocation rest
mentionsRevocation (C.Choose expression left right) = mentionsRevocation left || mentionsRevocation right

afterFailure : {a : Type} → C.Program → Maybe a → Maybe a
afterFailure program session = if mentionsRevocation program then Nothing else session
