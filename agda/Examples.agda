{-# OPTIONS --safe --erasure #-}
module Examples where
open import Haskell.Prim
open import ForumCore
open import ForumProofs

limit = More (More Zero)
oldText = Plain LA ∷ []
newText = Plain LB ∷ []
oldStore = PostC Alice oldText ∷ []
newStore = PostC Alice newText ∷ []

bob-cannot-steal : execute limit limit (Logged Bob) (EditPost Zero newText) oldStore ≡ Denied EditDenied
bob-cannot-steal = refl

alice-can-edit : execute limit limit (Logged Alice) (EditPost Zero newText) oldStore ≡ Accepted (Logged Alice) newStore
alice-can-edit = refl

alice-edit-secure : EditGuarantee Alice Zero oldStore newStore
alice-edit-secure = accepted-edit-secure limit limit Alice Zero newText oldStore (Logged Alice) newStore refl

escaped-opener : render (Lt ∷ Plain LS ∷ []) ≡ (Amp ∷ Plain LL ∷ Plain LT ∷ Plain Semicolon ∷ Plain LS ∷ [])
escaped-opener = refl
