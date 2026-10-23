module ForumCore
  (User(..), sameUser, Count(..), within, SafeChar(..), Glyph(..), append, escape, render, Session(..), Post(..), owner, body, snoc, Request(..), Error(..), Result(..), edit, finishEdit, execute)
where

import Prelude hiding (LT)

data User = Alice
          | Bob
              deriving (Eq, Show)

sameUser :: User -> User -> Bool
sameUser Alice Alice = True
sameUser Bob Bob = True
sameUser _ _ = False

data Count = Zero
           | More Count
               deriving (Eq, Show)

within :: Count -> [a] -> Bool
within n [] = True
within Zero (_ : _) = False
within (More n) (_ : xs) = within n xs

data SafeChar = LA
              | LB
              | LC
              | LD
              | LE
              | LF
              | LG
              | LH
              | LI
              | LJ
              | LK
              | LL
              | LM
              | LN
              | LO
              | LP
              | LQ
              | LR
              | LS
              | LT
              | LU
              | LV
              | LW
              | LX
              | LY
              | LZ
              | UA
              | UB
              | UC
              | UD
              | UE
              | UF
              | UG
              | UH
              | UI
              | UJ
              | UK
              | UL
              | UM
              | UN
              | UO
              | UP
              | UQ
              | UR
              | US
              | UT
              | UU
              | UV
              | UW
              | UX
              | UY
              | UZ
              | D0
              | D1
              | D2
              | D3
              | D4
              | D5
              | D6
              | D7
              | D8
              | D9
              | Space
              | Bang
              | Hash
              | Dollar
              | Percent
              | LParen
              | RParen
              | Star
              | Plus
              | Comma
              | Dash
              | Dot
              | Slash
              | Colon
              | Semicolon
              | Equals
              | Question
              | At
              | LBracket
              | Backslash
              | RBracket
              | Caret
              | Underscore
              | Backtick
              | LBrace
              | Pipe
              | RBrace
              | Tilde
              | Newline
                  deriving (Eq, Show, Enum, Bounded)

data Glyph = Plain SafeChar
           | Lt
           | Gt
           | Amp
           | DQuote
           | SQuote
               deriving (Eq, Show)

append :: [a] -> [a] -> [a]
append [] ys = ys
append (x : xs) ys = x : append xs ys

escape :: Glyph -> [Glyph]
escape (Plain c) = [Plain c]
escape Lt = [Amp, Plain LL, Plain LT, Plain Semicolon]
escape Gt = [Amp, Plain LG, Plain LT, Plain Semicolon]
escape Amp = [Amp, Plain LA, Plain LM, Plain LP, Plain Semicolon]
escape DQuote
  = [Amp, Plain LQ, Plain LU, Plain LO, Plain LT, Plain Semicolon]
escape SQuote
  = [Amp, Plain Hash, Plain D3, Plain D9, Plain Semicolon]

render :: [Glyph] -> [Glyph]
render [] = []
render (c : cs) = append (escape c) (render cs)

data Session = Guest
             | Logged User
                 deriving (Eq, Show)

data Post = PostC User [Glyph]
              deriving (Eq, Show)

owner :: Post -> User
owner (PostC u _) = u

body :: Post -> [Glyph]
body (PostC _ text) = text

snoc :: [a] -> a -> [a]
snoc [] x = [x]
snoc (y : ys) x = y : snoc ys x

data Request = ReadPosts
             | Authenticate User
             | CreatePost [Glyph]
             | EditPost Count [Glyph]
             | Logout
                 deriving (Eq, Show)

data Error = Unauthorized
           | BadTransition
           | TooLong
           | ForumFull
           | EditDenied
               deriving (Eq, Show)

data Result = Denied Error
            | Accepted Session [Post]
                deriving (Eq, Show)

edit :: User -> Count -> [Glyph] -> [Post] -> Maybe [Post]
edit actor i text [] = Nothing
edit actor Zero text (p : ps)
  = if sameUser actor (owner p) then Just (PostC (owner p) text : ps)
      else Nothing
edit actor (More i) text (p : ps)
  = maybe Nothing (\ tail -> Just (p : tail)) (edit actor i text ps)

finishEdit :: User -> Maybe [Post] -> Result
finishEdit u Nothing = Denied EditDenied
finishEdit u (Just ps) = Accepted (Logged u) ps

execute :: Count -> Count -> Session -> Request -> [Post] -> Result
execute textLimit postLimit Guest ReadPosts ps = Accepted Guest ps
execute textLimit postLimit Guest (Authenticate u) ps
  = Accepted (Logged u) ps
execute textLimit postLimit Guest (CreatePost text) ps
  = Denied Unauthorized
execute textLimit postLimit Guest (EditPost i text) ps
  = Denied Unauthorized
execute textLimit postLimit Guest Logout ps = Denied BadTransition
execute textLimit postLimit (Logged u) ReadPosts ps
  = Accepted (Logged u) ps
execute textLimit postLimit (Logged u) (Authenticate _) ps
  = Denied BadTransition
execute textLimit postLimit (Logged u) (CreatePost text) ps
  = if within textLimit text then
      if within postLimit (snoc ps (PostC u text)) then
        Accepted (Logged u) (snoc ps (PostC u text)) else Denied ForumFull
      else Denied TooLong
execute textLimit postLimit (Logged u) (EditPost i text) ps
  = if within textLimit text then finishEdit u (edit u i text ps)
      else Denied TooLong
execute textLimit postLimit (Logged u) Logout ps
  = Accepted Guest ps

