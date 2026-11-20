{-# LANGUAGE OverloadedStrings #-}
module Main (main) where
import Adapter
import ProgramAdapter
import ClientCore qualified as C
import ClientOracle qualified as Model
import ForumCore qualified as F
import Control.Monad (unless,forM_)
import Data.Aeson (Value,encode,object,(.=))
import Data.ByteString.Lazy qualified as LBS
import System.Exit (exitFailure)
import Test.QuickCheck
import Test.QuickCheck.Random (mkQCGen)

genUser :: Gen F.User
genUser = elements [F.Alice,F.Bob]
genBody :: Gen [F.Glyph]
genBody = resize 20 (listOf (frequency [(4,F.Plain <$> elements [minBound..maxBound]),
  (1,elements [F.Lt,F.Gt,F.Amp,F.DQuote,F.SQuote])]))
genGrant :: Gen C.Grant
genGrant = C.GrantC <$> genUser <*> elements [C.Viewer,C.Editor]
genContext :: Gen C.Context
genContext = C.Ctx <$> frequency [(1,pure Nothing),(3,Just <$> genGrant)]
  <*> frequency [(3,pure Nothing),(1,Just <$> genGrant)]
genExpr :: Gen C.Expr
genExpr = frequency [(3,C.Literal <$> genBody),(1,C.PrivateOf <$> genUser)]
genOp :: Gen C.Op
genOp = frequency [(2,elements [C.ReadPublic,C.SignIn,C.SignOut,C.ReadOnly]),
  (3,C.Publish <$> genExpr),(3,C.Revise <$> (toCount <$> chooseInt (0,8)) <*> genExpr),
  (3,C.Inspect <$> genExpr)]
genProgram :: Int -> Gen C.Program
genProgram 0 = pure C.Stop
genProgram n = frequency [(1,pure C.Stop),(5,C.Invoke <$> genOp <*> genProgram (n-1)),
  (2,C.Choose <$> genExpr <*> genProgram (n `div` 2) <*> genProgram (n `div` 2))]
genPosts :: Gen [F.Post]
genPosts = resize 6 (listOf (F.PostC <$> genUser <*> genBody))
genVault :: Gen C.Vault
genVault = C.VaultC <$> genBody <*> genBody

data Trial = Trial Int C.Program C.Context [F.Post] C.Vault deriving Show
instance Arbitrary Trial where
  arbitrary = Trial <$> chooseInt (0,24) <*> genProgram 14 <*> genContext <*> genPosts <*> genVault
  shrink (Trial gas p ctx ps v) = [Trial gas q ctx ps v | q <- shrinkProgram p] <>
    [Trial gas p ctx [] v | not (null ps)]
    where
      shrinkProgram C.Stop = []
      shrinkProgram (C.Invoke _ rest) = [C.Stop,rest]
      shrinkProgram (C.Choose _ yes no) = [C.Stop,yes,no]

runTrial :: Trial -> C.Result
runTrial (Trial gas p ctx ps v) = C.run textLimit postLimit (toCount gas) p ctx ps v

prop_model :: Trial -> Property
prop_model t@(Trial gas p ctx ps v) = runTrial t === Model.run textLimit postLimit (toCount gas) p ctx ps v

prop_transaction :: Trial -> Property
prop_transaction (Trial gas p ctx ps v) =
  let result=C.transaction textLimit postLimit (toCount gas) p ctx ps v
   in conjoin [result === Model.transaction textLimit postLimit (toCount gas) p ctx ps v,
      case result of
        C.Rollback _ after -> after === ps
        C.Commit next after trace -> C.run textLimit postLimit (toCount gas) p ctx ps v === C.Finished next after trace]

prop_stepModel :: Property
prop_stepModel = forAll genContext $ \ctx -> forAll genOp $ \op -> forAll genPosts $ \ps ->
  forAll genVault $ \v -> C.step textLimit postLimit ctx op ps v === Model.step textLimit postLimit ctx op ps v

prop_confinement :: Trial -> Property
prop_confinement t@(Trial _ _ ctx _ _) = conjoin
  [C.confined ctx (C.sources ctx) === True,
   C.confined ctx (C.sources ctx) === Model.confined ctx (C.sources ctx),
   case runTrial t of
     C.Refused _ -> property True
     C.Finished next _ _ -> C.confined next (C.sources ctx) === True]

prop_publicNI :: Trial -> Property
prop_publicNI t@(Trial gas p ctx ps _) = forAll genVault $ \second ->
  C.publicView (runTrial t) === C.publicView (C.run textLimit postLimit (toCount gas) p ctx ps second)

prop_otherUser :: Trial -> Property
prop_otherUser (Trial gas p _ ps (C.VaultC alice bob)) = forAll genBody $ \changedAlice ->
  let ctx=C.Ctx (Just (C.GrantC F.Bob C.Editor)) Nothing
   in C.run textLimit postLimit (toCount gas) p ctx ps (C.VaultC alice bob) ===
      C.run textLimit postLimit (toCount gas) p ctx ps (C.VaultC changedAlice bob)

prop_budget :: Trial -> Property
prop_budget t@(Trial gas _ _ _ _) = case runTrial t of
  C.Refused _ -> property True
  C.Finished _ _ trace -> counterexample "trace exceeds primitive/branch budget" (property (length trace <= gas))

prop_stepAuthorization :: Property
prop_stepAuthorization = forAll genContext $ \ctx -> forAll genExpr $ \e -> forAll genPosts $ \before ->
  forAll genVault $ \v -> forAll (chooseInt (0,9)) $ \i ->
  let check action = case C.step textLimit postLimit ctx action before v of
        C.Rejected _ -> property True
        C.Applied _ after _ -> conjoin [C.canWrite ctx === True,
          case action of
            C.Revise _ _ -> conjoin [length before===length after,map F.owner before===map F.owner after,
              counterexample "other owner's post changed" (property (and [x==y | (x,y) <- zip before after,F.owner x/=C.actor ctx])),
              counterexample "other position changed" (property (and [x==y | (j,(x,y)) <- zip [0..] (zip before after),j/=i])),
              F.owner (before!!i) === C.actor ctx]
            _ -> property True]
   in conjoin [check (C.Publish e),check (C.Revise (toCount i) e)]

prop_privateChannels :: Property
prop_privateChannels = forAll genUser $ \u -> forAll genVault $ \v ->
  let ctx=C.Ctx (Just (C.GrantC u C.Editor)) Nothing
      other=if u==F.Alice then F.Bob else F.Alice
      branch=C.Choose (C.PrivateOf u) C.Stop C.Stop
   in conjoin [C.step textLimit postLimit ctx (C.Publish (C.PrivateOf u)) [] v === C.Rejected C.SecretSink,
      C.run textLimit postLimit (toCount 1) branch ctx [] v === C.Refused C.SecretControl,
      C.step textLimit postLimit ctx (C.Inspect (C.PrivateOf other)) [] v === C.Rejected C.NoPrivateAccess]

prop_payload :: Property
prop_payload = forAll genBody $ \body ->
  let ctx=C.Ctx (Just (C.GrantC F.Alice C.Editor)) Nothing
   in C.run textLimit postLimit (toCount 1) (C.Invoke (C.Publish (C.Literal body)) C.Stop) ctx [] demoVault ===
      C.Finished ctx [F.PostC F.Alice body] [C.Posted F.Alice]

exprJSON :: C.Expr -> Value
exprJSON (C.Literal text) = object ["text" .= decodeText text]
exprJSON (C.PrivateOf u) = object ["private" .= (if u==F.Alice then "alice" else "bob" :: String)]
programJSON :: C.Program -> Value
programJSON C.Stop = object ["done" .= True]
programJSON (C.Invoke op rest) = object (["next" .= programJSON rest] <> fields op)
  where
    fields C.ReadPublic = ["op" .= ("read"::String)]
    fields C.SignIn = ["op" .= ("login"::String)]
    fields C.SignOut = ["op" .= ("logout"::String)]
    fields C.ReadOnly = ["op" .= ("restrict"::String)]
    fields (C.Publish e) = ["op" .= ("create"::String),"value" .= exprJSON e]
    fields (C.Revise i e) = ["op" .= ("edit"::String),"id" .= number i,"value" .= exprJSON e]
    fields (C.Inspect e) = ["op" .= ("inspect"::String),"value" .= exprJSON e]
    number :: F.Count -> Int
    number F.Zero = 0
    number (F.More n) = 1+number n
programJSON (C.Choose e yes no) = object ["if" .= exprJSON e,"then" .= programJSON yes,"else" .= programJSON no]

prop_wireRoundtrip :: Property
prop_wireRoundtrip = forAll (genProgram 5) $ \p ->
  let bytes=LBS.toStrict (encode (object ["budget" .= (32::Int),"program" .= programJSON p]))
   in case decodeBundle bytes of
     Left err -> counterexample err False
     Right decoded -> program decoded === p

check :: String -> Bool -> IO ()
check name passed = do
  putStrLn ((if passed then "PASS " else "FAIL ")<>name)
  unless passed exitFailure

main :: IO ()
main = do
  let run name p = do
        putStrLn name
        result <- quickCheckWithResult stdArgs {maxSuccess=2000,maxSize=40,
          replay=Just (mkQCGen 20261024,0)} p
        unless (isSuccess result) exitFailure
  run "program interpreter agrees with independent Agda/MAlonzo" (property prop_model)
  run "transaction matches Agda and refused batches preserve original store" (property prop_transaction)
  run "primitive interpreter agrees with independent Agda/MAlonzo" prop_stepModel
  run "capability source confinement and oracle agreement" (property prop_confinement)
  run "public noninterference under arbitrary private-vault changes" (property prop_publicNI)
  run "Bob's full observation ignores changes to Alice private data" (property prop_otherUser)
  run "accepted trace length is bounded by fuel" (property prop_budget)
  run "accepted writes require permission and protect ownership" prop_stepAuthorization
  run "private sources cannot reach public sinks or private-dependent branches" prop_privateChannels
  run "post payload remains data and cannot execute new commands" prop_payload
  run "JSON program representation roundtrips" prop_wireRoundtrip
  let ctx=C.Ctx (Just (C.GrantC F.Alice C.Editor)) Nothing
      viewer=C.Ctx (Just (C.GrantC F.Alice C.Viewer)) Nothing
      guest=C.Ctx Nothing Nothing
  check "attenuation changes current capability without granting an offer"
    (C.run textLimit postLimit (toCount 1) (C.Invoke C.ReadOnly C.Stop) ctx [] demoVault == C.Finished viewer [] [C.RightsReduced])
  check "logout revokes current and pending grants"
    (C.step textLimit postLimit (C.Ctx (C.current ctx) (C.current ctx)) C.SignOut [] demoVault == C.Applied guest [] C.SessionClosed)
  check "logout cannot reuse pending login authority"
    (C.run textLimit postLimit (toCount 3) (C.Invoke C.SignIn (C.Invoke C.SignOut (C.Invoke C.SignIn C.Stop)))
      (C.Ctx Nothing (C.current ctx)) [] demoVault == C.Refused C.NoLoginOffer)
  check "empty program fits zero budget" (C.run textLimit postLimit F.Zero C.Stop ctx [] demoVault == C.Finished ctx [] [])
  check "nonempty program exhausts zero budget" (C.run textLimit postLimit F.Zero (C.Invoke C.ReadPublic C.Stop) ctx [] demoVault == C.Refused C.Exhausted)
  forM_ [object ["budget" .= (1::Int),"program" .= object ["op" .= ("shell"::String)]],
    object ["budget" .= (1::Int),"program" .= object ["op" .= ("create"::String),"value" .= exprJSON (C.Literal []),"grant" .= ("Editor"::String)]],
    object ["budget" .= (33::Int),"program" .= programJSON C.Stop],
    object ["budget" .= (1::Int),"program" .= programJSON C.Stop,"authority" .= ("alice"::String)]] $ \bad ->
      check "malformed/forged program envelope rejected" (case decodeBundle (LBS.toStrict (encode bad)) of Left _ -> True; Right _ -> False)
  putStrLn "All restricted-program tests passed."
