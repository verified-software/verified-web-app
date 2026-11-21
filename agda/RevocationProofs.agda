{-# OPTIONS --safe --erasure #-}
module RevocationProofs where

open import Haskell.Prim
open import Haskell.Prim.Bool
open import Haskell.Prim.Maybe
import ClientCore as C
open import RevocationCore

data Mentions : C.Program → Type where
  sign-out : ∀ rest → Mentions (C.Invoke C.SignOut rest)
  restrict : ∀ rest → Mentions (C.Invoke C.ReadOnly rest)
  later : ∀ op rest → Mentions rest → Mentions (C.Invoke op rest)
  left : ∀ expression yes no → Mentions yes → Mentions (C.Choose expression yes no)
  right : ∀ expression yes no → Mentions no → Mentions (C.Choose expression yes no)

or-left : ∀ x y → x ≡ True → (x || y) ≡ True
or-left True y refl = refl
or-left False y ()

or-right : ∀ x y → y ≡ True → (x || y) ≡ True
or-right True y equal = refl
or-right False True refl = refl
or-right False False ()

mentions-complete : ∀ program → Mentions program → mentionsRevocation program ≡ True
mentions-complete .(C.Invoke C.SignOut rest) (sign-out rest) = refl
mentions-complete .(C.Invoke C.ReadOnly rest) (restrict rest) = refl
mentions-complete .(C.Invoke op rest) (later op rest laterMention) with op
... | C.SignOut = refl
... | C.ReadOnly = refl
... | C.ReadPublic = mentions-complete rest laterMention
... | C.SignIn = mentions-complete rest laterMention
... | C.Publish text = mentions-complete rest laterMention
... | C.Revise index text = mentions-complete rest laterMention
... | C.Inspect text = mentions-complete rest laterMention
mentions-complete .(C.Choose expression yes no) (left expression yes no occurrence) =
  or-left (mentionsRevocation yes) (mentionsRevocation no) (mentions-complete yes occurrence)
mentions-complete .(C.Choose expression yes no) (right expression yes no occurrence) =
  or-right (mentionsRevocation yes) (mentionsRevocation no) (mentions-complete no occurrence)

mentions-sound : ∀ program → mentionsRevocation program ≡ True → Mentions program
mentions-sound C.Stop ()
mentions-sound (C.Invoke op rest) found with op
... | C.SignOut = sign-out rest
... | C.ReadOnly = restrict rest
... | C.ReadPublic = later C.ReadPublic rest (mentions-sound rest found)
... | C.SignIn = later C.SignIn rest (mentions-sound rest found)
... | C.Publish text = later (C.Publish text) rest (mentions-sound rest found)
... | C.Revise index text = later (C.Revise index text) rest (mentions-sound rest found)
... | C.Inspect text = later (C.Inspect text) rest (mentions-sound rest found)
mentions-sound (C.Choose expression yes no) found with mentionsRevocation yes in yes-eq
... | True = left expression yes no (mentions-sound yes yes-eq)
... | False = right expression yes no (mentions-sound no found)

failure-revokes : ∀ {a : Type} program (session : Maybe a) →
  Mentions program → afterFailure program session ≡ Nothing
failure-revokes program session occurrence rewrite mentions-complete program occurrence = refl

failure-preserves : ∀ {a : Type} program (session : Maybe a) →
  mentionsRevocation program ≡ False → afterFailure program session ≡ session
failure-preserves program session absent rewrite absent = refl
