{-# OPTIONS --safe --erasure #-}
module ClientExamples where
open import Haskell.Prim
open import Haskell.Prim.Maybe
import ForumCore as F
open import ClientCore
open import ClientProofs
open import ClientFlow
open import ClientSyntax

limit = F.More (F.More (F.More F.Zero))
alice = GrantC F.Alice Editor
aliceCtx = Ctx (Just alice) Nothing
guest = Ctx Nothing Nothing
vault = VaultC (F.Plain F.LA ∷ []) (F.Plain F.LB ∷ [])
bodyText = F.Plain F.LX ∷ []

legitimate = Invoke SignIn (Invoke (Publish (Literal bodyText)) (Invoke SignOut Stop))
legitimate-result : run limit limit limit legitimate (Ctx Nothing (Just alice)) [] vault
  ≡ Finished guest (F.PostC F.Alice bodyText ∷ []) (SessionOpened F.Alice ∷ Posted F.Alice ∷ SessionClosed ∷ [])
legitimate-result = refl

legitimate-authorized : AuthorizedTrace limit limit vault (Ctx Nothing (Just alice)) [] legitimate guest
  (F.PostC F.Alice bodyText ∷ []) (SessionOpened F.Alice ∷ Posted F.Alice ∷ SessionClosed ∷ [])
legitimate-authorized = program-authorized limit limit limit legitimate (Ctx Nothing (Just alice)) [] vault guest
  (F.PostC F.Alice bodyText ∷ []) (SessionOpened F.Alice ∷ Posted F.Alice ∷ SessionClosed ∷ []) refl

secret-exfiltration-denied : run limit limit limit (Invoke (Publish (PrivateOf F.Alice)) Stop) aliceCtx [] vault ≡ Refused SecretSink
secret-exfiltration-denied = refl

implicit-flow-denied : run limit limit limit (Choose (PrivateOf F.Alice) Stop Stop) aliceCtx [] vault ≡ Refused SecretControl
implicit-flow-denied = refl

revoked-offer-denied : run limit limit limit (Invoke SignIn (Invoke SignOut (Invoke SignIn Stop)))
  (Ctx Nothing (Just alice)) [] vault ≡ Refused NoLoginOffer
revoked-offer-denied = refl

attenuation-denied : run limit limit limit (Invoke ReadOnly (Invoke (Publish (Literal bodyText)) Stop)) aliceCtx [] vault ≡ Refused NoAuthority
attenuation-denied = refl

exhaustion-denied : run limit limit F.Zero (Invoke ReadPublic Stop) guest [] vault ≡ Refused Exhausted
exhaustion-denied = refl
