{-# OPTIONS --safe #-}
module SafePragma where
open import Agda.Builtin.Bool
identity : Bool → Bool
identity x = x
{-# COMPILE AGDA2HS identity #-}
