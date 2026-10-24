module ClientCore
  (Rank(..), Grant(..), Context(..), current, pending, grantUser, session, actor, canWrite, Expr(..), Vault(..), secret, Value(..), Evaluation(..), evaluate, Op(..), Program(..), Error(..), Event(..), StepResult(..), Result(..), Mutation(..), request, writeEvent, commitForum, writeValue, inspectValue, signIn, signOut, readOnly, step, prepend, continue, choose, run, redactValue, redactEvent, redactEvents, publicView, rankBelow, below, covered, maybeCovered, confined, grantList, sources, Transaction(..), settle, transaction)
where

import Prelude hiding (LT)
import qualified ForumCore as F (Count(More, Zero), Error, Glyph, Post, Request(CreatePost, EditPost), Result(Accepted, Denied), Session(Guest, Logged), User(Alice, Bob), append, execute, sameUser)

data Rank = Viewer
          | Editor
              deriving (Eq, Show)

data Grant = GrantC F.User Rank
               deriving (Eq, Show)

data Context = Ctx (Maybe Grant) (Maybe Grant)
                 deriving (Eq, Show)

current :: Context -> Maybe Grant
current (Ctx c _) = c

pending :: Context -> Maybe Grant
pending (Ctx _ p) = p

grantUser :: Grant -> F.User
grantUser (GrantC u _) = u

session :: Context -> F.Session
session (Ctx Nothing _) = F.Guest
session (Ctx (Just (GrantC u _)) _) = F.Logged u

actor :: Context -> F.User
actor (Ctx Nothing _) = F.Alice
actor (Ctx (Just (GrantC u _)) _) = u

canWrite :: Context -> Bool
canWrite (Ctx (Just (GrantC _ Editor)) _) = True
canWrite _ = False

data Expr = Literal [F.Glyph]
          | PrivateOf F.User
              deriving (Eq, Show)

data Vault = VaultC [F.Glyph] [F.Glyph]
               deriving (Eq, Show)

secret :: Vault -> F.User -> [F.Glyph]
secret (VaultC a b) F.Alice = a
secret (VaultC a b) F.Bob = b

data Value = Public [F.Glyph]
           | Classified F.User [F.Glyph]
               deriving (Eq, Show)

data Evaluation = Unavailable
                | Evaluated Value
                    deriving (Eq, Show)

evaluate :: Context -> Expr -> Vault -> Evaluation
evaluate ctx (Literal text) vault = Evaluated (Public text)
evaluate (Ctx Nothing _) (PrivateOf u) vault = Unavailable
evaluate (Ctx (Just g) _) (PrivateOf u) vault
  = if F.sameUser (grantUser g) u then
      Evaluated (Classified u (secret vault u)) else Unavailable

data Op = ReadPublic
        | SignIn
        | SignOut
        | ReadOnly
        | Publish Expr
        | Revise F.Count Expr
        | Inspect Expr
            deriving (Eq, Show)

data Program = Stop
             | Invoke Op Program
             | Choose Expr Program Program
                 deriving (Eq, Show)

data Error = NoAuthority
           | BadState
           | NoLoginOffer
           | NoPrivateAccess
           | SecretSink
           | SecretControl
           | Exhausted
           | ForumError F.Error
               deriving (Eq, Show)

data Event = SawPublic
           | SessionClosed
           | RightsReduced
           | SessionOpened F.User
           | Posted F.User
           | Revised F.User F.Count
           | Displayed Value
           | Tested Bool
               deriving (Eq, Show)

data StepResult = Rejected Error
                | Applied Context [F.Post] Event
                    deriving (Eq, Show)

data Result = Refused Error
            | Finished Context [F.Post] [Event]
                deriving (Eq, Show)

data Mutation = Add
              | Change F.Count
                  deriving (Eq, Show)

request :: Mutation -> [F.Glyph] -> F.Request
request Add text = F.CreatePost text
request (Change i) text = F.EditPost i text

writeEvent :: Context -> Mutation -> Event
writeEvent ctx Add = Posted (actor ctx)
writeEvent ctx (Change i) = Revised (actor ctx) i

commitForum :: Context -> Event -> F.Result -> StepResult
commitForum ctx e (F.Denied err) = Rejected (ForumError err)
commitForum ctx e (F.Accepted _ ps) = Applied ctx ps e

writeValue ::
           F.Count ->
             F.Count ->
               Context -> Mutation -> [F.Post] -> Evaluation -> StepResult
writeValue tl pl ctx mutation ps Unavailable
  = Rejected NoPrivateAccess
writeValue tl pl ctx mutation ps (Evaluated (Classified _ _))
  = Rejected SecretSink
writeValue tl pl ctx mutation ps (Evaluated (Public text))
  = if canWrite ctx then
      commitForum ctx (writeEvent ctx mutation)
        (F.execute tl pl (session ctx) (request mutation text) ps)
      else Rejected NoAuthority

inspectValue :: Context -> [F.Post] -> Evaluation -> StepResult
inspectValue ctx ps Unavailable = Rejected NoPrivateAccess
inspectValue ctx ps (Evaluated v) = Applied ctx ps (Displayed v)

signIn :: Context -> [F.Post] -> StepResult
signIn (Ctx Nothing Nothing) ps = Rejected NoLoginOffer
signIn (Ctx Nothing (Just g)) ps
  = Applied (Ctx (Just g) Nothing) ps (SessionOpened (grantUser g))
signIn (Ctx (Just _) _) ps = Rejected BadState

signOut :: Context -> [F.Post] -> StepResult
signOut (Ctx Nothing _) ps = Rejected BadState
signOut (Ctx (Just _) _) ps
  = Applied (Ctx Nothing Nothing) ps SessionClosed

readOnly :: Context -> [F.Post] -> StepResult
readOnly (Ctx Nothing _) ps = Rejected NoAuthority
readOnly (Ctx (Just (GrantC u _)) _) ps
  = Applied (Ctx (Just (GrantC u Viewer)) Nothing) ps RightsReduced

step ::
     F.Count ->
       F.Count -> Context -> Op -> [F.Post] -> Vault -> StepResult
step tl pl ctx ReadPublic ps vault = Applied ctx ps SawPublic
step tl pl ctx SignIn ps vault = signIn ctx ps
step tl pl ctx SignOut ps vault = signOut ctx ps
step tl pl ctx ReadOnly ps vault = readOnly ctx ps
step tl pl ctx (Publish expr) ps vault
  = writeValue tl pl ctx Add ps (evaluate ctx expr vault)
step tl pl ctx (Revise i expr) ps vault
  = writeValue tl pl ctx (Change i) ps (evaluate ctx expr vault)
step tl pl ctx (Inspect expr) ps vault
  = inspectValue ctx ps (evaluate ctx expr vault)

prepend :: Event -> Result -> Result
prepend e (Refused err) = Refused err
prepend e (Finished ctx ps es) = Finished ctx ps (e : es)

continue :: (Context -> [F.Post] -> Result) -> StepResult -> Result
continue k (Rejected err) = Refused err
continue k (Applied ctx ps e) = prepend e (k ctx ps)

choose :: (Bool -> Result) -> Evaluation -> Result
choose k Unavailable = Refused NoPrivateAccess
choose k (Evaluated (Classified _ _)) = Refused SecretControl
choose k (Evaluated (Public [])) = prepend (Tested True) (k True)
choose k (Evaluated (Public (_ : _)))
  = prepend (Tested False) (k False)

run ::
    F.Count ->
      F.Count ->
        F.Count -> Program -> Context -> [F.Post] -> Vault -> Result
run tl pl fuel Stop ctx ps vault = Finished ctx ps []
run tl pl F.Zero (Invoke op rest) ctx ps vault = Refused Exhausted
run tl pl F.Zero (Choose expr left right) ctx ps vault
  = Refused Exhausted
run tl pl (F.More fuel) (Invoke op rest) ctx ps vault
  = continue (\ next posts -> run tl pl fuel rest next posts vault)
      (step tl pl ctx op ps vault)
run tl pl (F.More fuel) (Choose expr left right) ctx ps vault
  = choose
      (\ empty ->
         if empty then run tl pl fuel left ctx ps vault else
           run tl pl fuel right ctx ps vault)
      (evaluate ctx expr vault)

redactValue :: Value -> Value
redactValue (Public text) = Public text
redactValue (Classified u _) = Classified u []

redactEvent :: Event -> Event
redactEvent (Displayed v) = Displayed (redactValue v)
redactEvent e = e

redactEvents :: [Event] -> [Event]
redactEvents [] = []
redactEvents (e : es) = redactEvent e : redactEvents es

publicView :: Result -> Result
publicView (Refused err) = Refused err
publicView (Finished ctx ps es) = Finished ctx ps (redactEvents es)

rankBelow :: Rank -> Rank -> Bool
rankBelow Viewer _ = True
rankBelow Editor Viewer = False
rankBelow Editor Editor = True

below :: Grant -> Grant -> Bool
below (GrantC u r) (GrantC v s) = F.sameUser u v && rankBelow r s

covered :: Grant -> [Grant] -> Bool
covered g [] = False
covered g (source : rest) = below g source || covered g rest

maybeCovered :: Maybe Grant -> [Grant] -> Bool
maybeCovered Nothing allowed = True
maybeCovered (Just g) allowed = covered g allowed

confined :: Context -> [Grant] -> Bool
confined (Ctx c p) allowed
  = maybeCovered c allowed && maybeCovered p allowed

grantList :: Maybe Grant -> [Grant]
grantList Nothing = []
grantList (Just g) = [g]

sources :: Context -> [Grant]
sources (Ctx c p) = F.append (grantList c) (grantList p)

data Transaction = Rollback Error [F.Post]
                 | Commit Context [F.Post] [Event]
                     deriving (Eq, Show)

settle :: [F.Post] -> Result -> Transaction
settle before (Refused err) = Rollback err before
settle before (Finished ctx after es) = Commit ctx after es

transaction ::
            F.Count ->
              F.Count ->
                F.Count -> Program -> Context -> [F.Post] -> Vault -> Transaction
transaction tl pl fuel program ctx before vault
  = settle before (run tl pl fuel program ctx before vault)

