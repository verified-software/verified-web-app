{-# OPTIONS --safe --erasure #-}
module ClientTransactions where
open import Haskell.Prim
import ForumCore as F
open import ClientCore
open import ClientProofs
open import ClientFlow using (cong; observer-noninterference)

settle-rollback : ∀ before result err after → settle before result ≡ Rollback err after → before ≡ after
settle-rollback before (Refused err) .err .before refl = refl
settle-rollback before (Finished ctx ps es) err after ()

transaction-rollback : ∀ tl pl fuel program ctx before vault err after
  → transaction tl pl fuel program ctx before vault ≡ Rollback err after → before ≡ after
transaction-rollback tl pl fuel program ctx before vault =
  settle-rollback before (run tl pl fuel program ctx before vault)

settle-commit : ∀ before result ctx after es
  → settle before result ≡ Commit ctx after es → result ≡ Finished ctx after es
settle-commit before (Refused err) ctx after es ()
settle-commit before (Finished ctx ps es) .ctx .ps .es refl = refl

transaction-authorized : ∀ tl pl fuel program ctx before vault final after es
  → transaction tl pl fuel program ctx before vault ≡ Commit final after es
  → AuthorizedTrace tl pl vault ctx before program final after es
transaction-authorized tl pl fuel program ctx before vault final after es committed =
  program-authorized tl pl fuel program ctx before vault final after es
    (settle-commit before (run tl pl fuel program ctx before vault) final after es committed)

transaction-observer : ∀ tl pl fuel program ctx ps first second observer
  → confined ctx (GrantC observer Editor ∷ []) ≡ True
  → secret first observer ≡ secret second observer
  → transaction tl pl fuel program ctx ps first ≡ transaction tl pl fuel program ctx ps second
transaction-observer tl pl fuel program ctx ps first second observer confined own =
  cong (settle ps) (observer-noninterference tl pl fuel program ctx ps first second observer confined own)
