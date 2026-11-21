{-# OPTIONS --safe --erasure #-}
module TenantProofs where

open import Haskell.Prim
open import Haskell.Prim.Bool
open import Haskell.Prim.Maybe
open import TenantCore

sameId-refl : ∀ id → sameId id id ≡ True
sameId-refl [] = refl
sameId-refl (True ∷ xs) = sameId-refl xs
sameId-refl (False ∷ xs) = sameId-refl xs

sameId-sound : ∀ first second → sameId first second ≡ True → first ≡ second
sameId-sound [] [] _ = refl
sameId-sound [] (_ ∷ _) ()
sameId-sound (_ ∷ _) [] ()
sameId-sound (True ∷ xs) (True ∷ ys) equal rewrite sameId-sound xs ys equal = refl
sameId-sound (False ∷ xs) (False ∷ ys) equal rewrite sameId-sound xs ys equal = refl
sameId-sound (True ∷ _) (False ∷ _) ()
sameId-sound (False ∷ _) (True ∷ _) ()

anonymous-denied : ∀ tenant action → permitted Anonymous tenant action ≡ False
anonymous-denied tenant action = refl

reader-write-denied : ∀ source tenant → permitted (Member source Reader) tenant Write ≡ False
reader-write-denied source tenant = refl

member-can-read : ∀ tenant role → permitted (Member tenant role) tenant Read ≡ True
member-can-read tenant Reader = sameId-refl tenant
member-can-read tenant Writer = sameId-refl tenant

writer-can-write : ∀ tenant → permitted (Member tenant Writer) tenant Write ≡ True
writer-can-write tenant = sameId-refl tenant

tenant-isolation : ∀ source tenant role action →
  permitted (Member source role) tenant action ≡ True → source ≡ tenant
tenant-isolation source tenant Reader Read allowed = sameId-sound source tenant allowed
tenant-isolation source tenant Reader Write ()
tenant-isolation source tenant Writer action allowed = sameId-sound source tenant allowed

guarded-denied : ∀ {a : Type} principal tenant action (first second : a) →
  permitted principal tenant action ≡ False →
  guarded principal action (Resource tenant first) ≡ guarded principal action (Resource tenant second)
guarded-denied principal tenant action first second denied rewrite denied = refl

guarded-allowed : ∀ {a : Type} principal tenant action (value result : a) →
  guarded principal action (Resource tenant value) ≡ Just result →
  permitted principal tenant action ≡ True
guarded-allowed principal tenant action value result accepted with permitted principal tenant action in eq
... | True = refl
... | False = absurd accepted
  where
  absurd : ∀ {a : Type} {x : a} → Nothing ≡ Just x → False ≡ True
  absurd ()

guarded-isolation : ∀ {a : Type} source tenant role action (value result : a) →
  guarded (Member source role) action (Resource tenant value) ≡ Just result → source ≡ tenant
guarded-isolation source tenant role action value result accepted =
  tenant-isolation source tenant role action
    (guarded-allowed (Member source role) tenant action value result accepted)
