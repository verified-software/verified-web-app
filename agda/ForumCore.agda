{-# OPTIONS --safe --erasure #-}
module ForumCore where
open import Haskell.Prim
open import Haskell.Prim.Bool
open import Haskell.Prim.Maybe

data User : Type where Alice Bob : User

sameUser : User → User → Bool
sameUser Alice Alice = True
sameUser Bob Bob = True
sameUser _ _ = False

data Count : Type where
  Zero : Count
  More : Count → Count

within : {a : Type} → Count → List a → Bool
within n [] = True
within Zero (_ ∷ _) = False
within (More n) (_ ∷ xs) = within n xs

-- Every printable ASCII character except HTML delimiters, which have separate
-- constructors. There is no RawHtml, JavaScript, SQL, URL or effect constructor.
data SafeChar : Type where
  LA LB LC LD LE LF LG LH LI LJ LK LL LM LN LO LP LQ LR LS LT LU LV LW LX LY LZ : SafeChar
  UA UB UC UD UE UF UG UH UI UJ UK UL UM UN UO UP UQ UR US UT UU UV UW UX UY UZ : SafeChar
  D0 D1 D2 D3 D4 D5 D6 D7 D8 D9 : SafeChar
  Space Bang Hash Dollar Percent LParen RParen Star Plus Comma Dash Dot Slash : SafeChar
  Colon Semicolon Equals Question At LBracket Backslash RBracket Caret Underscore : SafeChar
  Backtick LBrace Pipe RBrace Tilde Newline : SafeChar

data Glyph : Type where
  Plain : SafeChar → Glyph
  Lt Gt Amp DQuote SQuote : Glyph

append : {a : Type} → List a → List a → List a
append [] ys = ys
append (x ∷ xs) ys = x ∷ append xs ys

escape : Glyph → List Glyph
escape (Plain c) = Plain c ∷ []
escape Lt = Amp ∷ Plain LL ∷ Plain LT ∷ Plain Semicolon ∷ []
escape Gt = Amp ∷ Plain LG ∷ Plain LT ∷ Plain Semicolon ∷ []
escape Amp = Amp ∷ Plain LA ∷ Plain LM ∷ Plain LP ∷ Plain Semicolon ∷ []
escape DQuote = Amp ∷ Plain LQ ∷ Plain LU ∷ Plain LO ∷ Plain LT ∷ Plain Semicolon ∷ []
escape SQuote = Amp ∷ Plain Hash ∷ Plain D3 ∷ Plain D9 ∷ Plain Semicolon ∷ []

render : List Glyph → List Glyph
render [] = []
render (c ∷ cs) = append (escape c) (render cs)

data Session : Type where
  Guest : Session
  Logged : User → Session

data Post : Type where
  PostC : User → List Glyph → Post

owner : Post → User
owner (PostC u _) = u

body : Post → List Glyph
body (PostC _ text) = text

snoc : {a : Type} → List a → a → List a
snoc [] x = x ∷ []
snoc (y ∷ ys) x = y ∷ snoc ys x

-- Only an authenticated adapter may construct Authenticate. It is NOT a wire
-- command that trusts a user ID supplied by the client.
data Request : Type where
  ReadPosts : Request
  Authenticate : User → Request
  CreatePost : List Glyph → Request
  EditPost : Count → List Glyph → Request
  Logout : Request

data Error : Type where
  Unauthorized BadTransition TooLong ForumFull EditDenied : Error

data Result : Type where
  Denied : Error → Result
  Accepted : Session → List Post → Result

edit : User → Count → List Glyph → List Post → Maybe (List Post)
edit actor i text [] = Nothing
edit actor Zero text (p ∷ ps) = if sameUser actor (owner p)
  then Just (PostC (owner p) text ∷ ps) else Nothing
edit actor (More i) text (p ∷ ps) = maybe Nothing (λ tail → Just (p ∷ tail)) (edit actor i text ps)

finishEdit : User → Maybe (List Post) → Result
finishEdit u Nothing = Denied EditDenied
finishEdit u (Just ps) = Accepted (Logged u) ps

-- The body and post limits are explicit inputs to the proved executable core.
execute : Count → Count → Session → Request → List Post → Result
execute textLimit postLimit Guest ReadPosts ps = Accepted Guest ps
execute textLimit postLimit Guest (Authenticate u) ps = Accepted (Logged u) ps
execute textLimit postLimit Guest (CreatePost text) ps = Denied Unauthorized
execute textLimit postLimit Guest (EditPost i text) ps = Denied Unauthorized
execute textLimit postLimit Guest Logout ps = Denied BadTransition
execute textLimit postLimit (Logged u) ReadPosts ps = Accepted (Logged u) ps
execute textLimit postLimit (Logged u) (Authenticate _) ps = Denied BadTransition
execute textLimit postLimit (Logged u) (CreatePost text) ps =
  if within textLimit text then
    if within postLimit (snoc ps (PostC u text))
      then Accepted (Logged u) (snoc ps (PostC u text)) else Denied ForumFull
  else Denied TooLong
execute textLimit postLimit (Logged u) (EditPost i text) ps =
  if within textLimit text then finishEdit u (edit u i text ps) else Denied TooLong
execute textLimit postLimit (Logged u) Logout ps = Accepted Guest ps
