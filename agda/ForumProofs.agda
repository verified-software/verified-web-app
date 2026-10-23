{-# OPTIONS --safe --erasure #-}
module ForumProofs where
open import Haskell.Prim
open import Haskell.Prim.Bool
open import Haskell.Prim.Maybe
open import ForumCore

-- Indexed protocol relation: no constructor permits an anonymous write,
-- repeated authentication, or logout from Guest.
data Step : Session → Request → Session → Type where
  readGuest : Step Guest ReadPosts Guest
  login : ∀ {u} → Step Guest (Authenticate u) (Logged u)
  readMember : ∀ {u} → Step (Logged u) ReadPosts (Logged u)
  create : ∀ {u text} → Step (Logged u) (CreatePost text) (Logged u)
  change : ∀ {u i text} → Step (Logged u) (EditPost i text) (Logged u)
  logout : ∀ {u} → Step (Logged u) Logout Guest

data Legal (s : Session) (req : Request) : Result → Type where
  rejected : ∀ {e} → Legal s req (Denied e)
  permitted : ∀ {s' ps} → Step s req s' → Legal s req (Accepted s' ps)

finish-legal : ∀ u i text maybePosts → Legal (Logged u) (EditPost i text) (finishEdit u maybePosts)
finish-legal u i text Nothing = rejected
finish-legal u i text (Just ps) = permitted change

protocol-safety : ∀ textLimit postLimit session request posts → Legal session request (execute textLimit postLimit session request posts)
protocol-safety tl pl Guest ReadPosts ps = permitted readGuest
protocol-safety tl pl Guest (Authenticate u) ps = permitted login
protocol-safety tl pl Guest (CreatePost text) ps = rejected
protocol-safety tl pl Guest (EditPost i text) ps = rejected
protocol-safety tl pl Guest Logout ps = rejected
protocol-safety tl pl (Logged u) ReadPosts ps = permitted readMember
protocol-safety tl pl (Logged u) (Authenticate _) ps = rejected
protocol-safety tl pl (Logged u) (CreatePost text) ps with within tl text
... | False = rejected
... | True with within pl (snoc ps (PostC u text))
...   | False = rejected
...   | True = permitted create
protocol-safety tl pl (Logged u) (EditPost i text) ps with within tl text
... | False = rejected
... | True = finish-legal u i text (edit u i text ps)
protocol-safety tl pl (Logged u) Logout ps = permitted logout

guest-create-denied : ∀ tl pl text ps → execute tl pl Guest (CreatePost text) ps ≡ Denied Unauthorized
guest-create-denied tl pl text ps = refl

guest-edit-denied : ∀ tl pl i text ps → execute tl pl Guest (EditPost i text) ps ≡ Denied Unauthorized
guest-edit-denied tl pl i text ps = refl

data OwnedAt (u : User) : Count → List Post → Type where
  atHead : ∀ {p ps} → sameUser u (owner p) ≡ True → OwnedAt u Zero (p ∷ ps)
  inTail : ∀ {i p ps} → OwnedAt u i ps → OwnedAt u (More i) (p ∷ ps)

-- Pointwise old/new relation: each cell is identical or its existing owner
-- authorized replacing only its body. Ownership and list positions are retained.
data Protected (u : User) : Post → Post → Type where
  unchanged : ∀ {p} → Protected u p p
  ownBody : ∀ {p text} → sameUser u (owner p) ≡ True → Protected u p (PostC (owner p) text)

data AllProtected (u : User) : List Post → List Post → Type where
  empty : AllProtected u [] []
  cell : ∀ {p q ps qs} → Protected u p q → AllProtected u ps qs → AllProtected u (p ∷ ps) (q ∷ qs)

unchanged-list : ∀ u ps → AllProtected u ps ps
unchanged-list u [] = empty
unchanged-list u (p ∷ ps) = cell unchanged (unchanged-list u ps)

unowned-unchanged : ∀ {u p q} → sameUser u (owner p) ≡ False → Protected u p q → p ≡ q
unowned-unchanged no unchanged = refl
unowned-unchanged no (ownBody yes) = magic (exFalso yes no)

owner-preserved : ∀ {u p q} → Protected u p q → owner p ≡ owner q
owner-preserved unchanged = refl
owner-preserved (ownBody yes) = refl

edit-owned : ∀ u i text ps out → edit u i text ps ≡ Just out → OwnedAt u i ps
edit-owned u i text [] out ()
edit-owned u Zero text (p ∷ ps) out accepted with sameUser u (owner p) in authorized
... | False = impossible accepted where
  impossible : Nothing ≡ Just out → OwnedAt u Zero (p ∷ ps)
  impossible ()
... | True = atHead authorized
edit-owned u (More i) text (p ∷ ps) out accepted with edit u i text ps in edited
... | Nothing = impossible accepted where
  impossible : Nothing ≡ Just out → OwnedAt u (More i) (p ∷ ps)
  impossible ()
... | Just tail = inTail (edit-owned u i text ps tail edited)

edit-protects : ∀ u i text ps out → edit u i text ps ≡ Just out → AllProtected u ps out
edit-protects u i text [] out ()
edit-protects u Zero text (p ∷ ps) out accepted with sameUser u (owner p) in authorized
... | False = impossible accepted where
  impossible : Nothing ≡ Just out → AllProtected u (p ∷ ps) out
  impossible ()
... | True with accepted
...   | refl = cell (ownBody authorized) (unchanged-list u ps)
edit-protects u (More i) text (p ∷ ps) out accepted with edit u i text ps in edited
... | Nothing = impossible accepted where
  impossible : Nothing ≡ Just out → AllProtected u (p ∷ ps) out
  impossible ()
... | Just tail with accepted
...   | refl = cell unchanged (edit-protects u i text ps tail edited)

finish-sound : ∀ u maybePosts session out → finishEdit u maybePosts ≡ Accepted session out → maybePosts ≡ Just out
finish-sound u Nothing session out ()
finish-sound u (Just ps) .(Logged u) .ps refl = refl

record EditGuarantee (u : User) (i : Count) (before after : List Post) : Type where
  constructor secured
  field
    targetOwned : OwnedAt u i before
    allCellsProtected : AllProtected u before after

-- This theorem is about acceptance by execute, not an isolated helper model.
accepted-edit-secure : ∀ tl pl u i text before session after
  → execute tl pl (Logged u) (EditPost i text) before ≡ Accepted session after
  → EditGuarantee u i before after
accepted-edit-secure tl pl u i text before session after accepted with within tl text
... | False = impossible accepted where
  impossible : Denied TooLong ≡ Accepted session after → EditGuarantee u i before after
  impossible ()
... | True = secured
  (edit-owned u i text before after (finish-sound u (edit u i text before) session after accepted))
  (edit-protects u i text before after (finish-sound u (edit u i text before) session after accepted))

-- No unescaped '<' can occur in any user-rendered fragment.
data NoTag : Glyph → Type where
  plain : ∀ {c} → NoTag (Plain c)
  amp : NoTag Amp

data Every {a : Type} (p : a → Type) : List a → Type where
  nil : Every p []
  cons : ∀ {x xs} → p x → Every p xs → Every p (x ∷ xs)

every-append : ∀ {a : Type} {p : a → Type} {xs ys} → Every p xs → Every p ys → Every p (append xs ys)
every-append nil right = right
every-append (cons p ps) right = cons p (every-append ps right)

escape-no-tag : ∀ c → Every NoTag (escape c)
escape-no-tag (Plain c) = cons plain nil
escape-no-tag Lt = cons amp (cons plain (cons plain (cons plain nil)))
escape-no-tag Gt = cons amp (cons plain (cons plain (cons plain nil)))
escape-no-tag Amp = cons amp (cons plain (cons plain (cons plain (cons plain nil))))
escape-no-tag DQuote = cons amp (cons plain (cons plain (cons plain (cons plain (cons plain nil)))))
escape-no-tag SQuote = cons amp (cons plain (cons plain (cons plain (cons plain nil))))

render-no-tag : ∀ text → Every NoTag (render text)
render-no-tag [] = nil
render-no-tag (c ∷ cs) = every-append (escape-no-tag c) (render-no-tag cs)

data Fits {a : Type} : Count → List a → Type where
  none : ∀ {n} → Fits n []
  one : ∀ {n x xs} → Fits n xs → Fits (More n) (x ∷ xs)

within-sound : ∀ {a : Type} n (xs : List a) → within n xs ≡ True → Fits n xs
within-sound n [] p = none
within-sound Zero (_ ∷ _) ()
within-sound (More n) (x ∷ xs) p = one (within-sound n xs p)

plus : Count → Count → Count
plus Zero m = m
plus (More n) m = More (plus n m)

fits-more : ∀ {a : Type} {xs : List a} {n} → Fits n xs → Fits (More n) xs
fits-more none = none
fits-more (one fit) = one (fits-more fit)

weaken : ∀ {a : Type} {xs : List a} n m → Fits m xs → Fits (plus n m) xs
weaken Zero m fit = fit
weaken (More n) m fit = fits-more (weaken n m fit)

fits-append : ∀ {a : Type} {xs ys : List a} n m → Fits n xs → Fits m ys → Fits (plus n m) (append xs ys)
fits-append n m none right = weaken n m right
fits-append (More n) m (one p) right = one (fits-append n m p right)

six : Count
six = More (More (More (More (More (More Zero)))))

sixTimes : Count → Count
sixTimes Zero = Zero
sixTimes (More n) = plus six (sixTimes n)

escape-bounded : ∀ c → Fits six (escape c)
escape-bounded (Plain c) = one none
escape-bounded Lt = one (one (one (one none)))
escape-bounded Gt = one (one (one (one none)))
escape-bounded Amp = one (one (one (one (one none))))
escape-bounded DQuote = one (one (one (one (one (one none)))))
escape-bounded SQuote = one (one (one (one (one none))))

-- Precise size bound: at most six ASCII output glyphs per input glyph.
render-bounded : ∀ n text → Fits n text → Fits (sixTimes n) (render text)
render-bounded n [] none = none
render-bounded (More n) (c ∷ cs) (one fit) =
  fits-append six (sixTimes n) (escape-bounded c) (render-bounded n cs fit)

accepted-create-bounded : ∀ tl pl u text before session after
  → execute tl pl (Logged u) (CreatePost text) before ≡ Accepted session after
  → Fits tl text
accepted-create-bounded tl pl u text before session after accepted with within tl text in fit
... | False = impossible accepted where
  impossible : Denied TooLong ≡ Accepted session after → Fits tl text
  impossible ()
... | True = within-sound tl text fit

accepted-edit-bounded : ∀ tl pl u i text before session after
  → execute tl pl (Logged u) (EditPost i text) before ≡ Accepted session after
  → Fits tl text
accepted-edit-bounded tl pl u i text before session after accepted with within tl text in fit
... | False = impossible accepted where
  impossible : Denied TooLong ≡ Accepted session after → Fits tl text
  impossible ()
... | True = within-sound tl text fit

edit-size : ∀ u i text before after n → Fits n before → edit u i text before ≡ Just after → Fits n after
edit-size u i text [] after n fit ()
edit-size u Zero text (p ∷ ps) after (More n) (one fit) accepted with sameUser u (owner p)
... | False = impossible accepted where
  impossible : Nothing ≡ Just after → Fits (More n) after
  impossible ()
... | True with accepted
...   | refl = one fit
edit-size u (More i) text (p ∷ ps) after (More n) (one fit) accepted with edit u i text ps in edited
... | Nothing = impossible accepted where
  impossible : Nothing ≡ Just after → Fits (More n) after
  impossible ()
... | Just tail with accepted
...   | refl = one (edit-size u i text ps tail n fit edited)

data StoreBound (n : Count) : Result → Type where
  denied : ∀ {e} → StoreBound n (Denied e)
  bounded : ∀ {s ps} → Fits n ps → StoreBound n (Accepted s ps)

finish-size : ∀ u i text before n → Fits n before → StoreBound n (finishEdit u (edit u i text before))
finish-size u i text before n fit with edit u i text before in edited
... | Nothing = denied
... | Just after = bounded (edit-size u i text before after n fit edited)

-- Starting from a bounded store, EVERY command preserves the post-count bound.
-- This gives an inductive invariant for the server's initially empty store.
store-bound-preserved : ∀ tl pl session req before → Fits pl before
  → StoreBound pl (execute tl pl session req before)
store-bound-preserved tl pl Guest ReadPosts ps fit = bounded fit
store-bound-preserved tl pl Guest (Authenticate u) ps fit = bounded fit
store-bound-preserved tl pl Guest (CreatePost text) ps fit = denied
store-bound-preserved tl pl Guest (EditPost i text) ps fit = denied
store-bound-preserved tl pl Guest Logout ps fit = denied
store-bound-preserved tl pl (Logged u) ReadPosts ps fit = bounded fit
store-bound-preserved tl pl (Logged u) (Authenticate v) ps fit = denied
store-bound-preserved tl pl (Logged u) (CreatePost text) ps fit with within tl text
... | False = denied
... | True with within pl (snoc ps (PostC u text)) in bound
...   | False = denied
...   | True = bounded (within-sound pl (snoc ps (PostC u text)) bound)
store-bound-preserved tl pl (Logged u) (EditPost i text) ps fit with within tl text
... | False = denied
... | True = finish-size u i text ps pl fit
store-bound-preserved tl pl (Logged u) Logout ps fit = bounded fit
