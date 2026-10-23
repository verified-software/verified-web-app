{-# LANGUAGE OverloadedStrings #-}
module Main (main) where
import Adapter
import Control.Monad (unless, forM_)
import Data.Aeson (encode, object, (.=))
import Data.ByteString.Char8 qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.List (nub)
import Data.Text qualified as Text
import ForumCore qualified as C
import Oracle qualified
import System.Exit (exitFailure)
import Test.QuickCheck
import Test.QuickCheck.Random (mkQCGen)

genUser :: Gen C.User
genUser = elements [C.Alice,C.Bob]
genGlyph :: Gen C.Glyph
genGlyph = frequency [(3,C.Plain <$> elements [minBound..maxBound]),
  (2,elements [C.Lt,C.Gt,C.Amp,C.DQuote,C.SQuote])]
genBody :: Gen [C.Glyph]
genBody = resize 30 (listOf genGlyph)
genPost :: Gen C.Post
genPost = C.PostC <$> genUser <*> genBody
genRequest :: Gen C.Request
genRequest = oneof [pure C.ReadPosts, C.Authenticate <$> genUser,
  C.CreatePost <$> genBody, C.EditPost <$> (toCount <$> chooseInt (0,12)) <*> genBody, pure C.Logout]
genSession :: Gen C.Session
genSession = oneof [pure C.Guest,C.Logged <$> genUser]

prop_oracle :: Property
prop_oracle = forAll genSession $ \s -> forAll genRequest $ \req ->
  forAll (resize 10 (listOf genPost)) $ \ps -> forAll (chooseInt (0,30)) $ \tl ->
  forAll (chooseInt (0,12)) $ \pl ->
    C.execute (toCount tl) (toCount pl) s req ps === Oracle.execute (toCount tl) (toCount pl) s req ps

prop_render :: Property
prop_render = forAll genBody $ \text -> conjoin
  [ C.render text === Oracle.render text
  , counterexample "raw HTML tag opener" (property ('<' `notElem` Text.unpack (renderFragment text)))
  , counterexample "sixfold output bound" (property (length (C.render text) <= 6*length text)) ]

prop_ownership :: Property
prop_ownership = forAll genUser $ \actor -> forAll (resize 12 (listOf genPost)) $ \before ->
  forAll (chooseInt (0,15)) $ \i -> forAll genBody $ \text ->
  case C.execute textLimit postLimit (C.Logged actor) (C.EditPost (toCount i) text) before of
    C.Denied _ -> property True
    C.Accepted s after -> conjoin
      [s === C.Logged actor, length after === length before, map C.owner after === map C.owner before,
       counterexample "unowned cell changed" (property (all (\(p,q) -> C.owner p == actor || p == q) (zip before after))),
       counterexample "nontarget changed" (property (and [p==q | (j,(p,q)) <- zip [0..] (zip before after),j/=i])),
       C.owner (before!!i) === actor, C.body (after!!i) === text]

prop_guest :: Property
prop_guest = forAll (resize 10 (listOf genPost)) $ \ps -> forAll genBody $ \text ->
  conjoin [C.execute textLimit postLimit C.Guest (C.CreatePost text) ps === C.Denied C.Unauthorized,
    C.execute textLimit postLimit C.Guest (C.EditPost C.Zero text) ps === C.Denied C.Unauthorized]

prop_trace :: Property
prop_trace = forAll (resize 60 (listOf genRequest)) $ \requests ->
  let go _ _ [] = True
      go s ps (req:rest) =
        let result=C.execute (toCount 12) (toCount 8) s req ps
            same=result==Oracle.execute (toCount 12) (toCount 8) s req ps
         in same && case result of
           C.Denied _ -> go s ps rest
           C.Accepted next after -> length after<=8 && all ((<=12) . length . C.body) after &&
             allowed s req next && go next after rest
   in property (go C.Guest [] requests)
  where
    allowed C.Guest C.ReadPosts C.Guest = True
    allowed C.Guest (C.Authenticate u) (C.Logged v) = u==v
    allowed (C.Logged u) C.ReadPosts (C.Logged v) = u==v
    allowed (C.Logged u) (C.CreatePost _) (C.Logged v) = u==v
    allowed (C.Logged u) (C.EditPost _ _) (C.Logged v) = u==v
    allowed (C.Logged _) C.Logout C.Guest = True
    allowed _ _ _ = False

prop_wire :: Property
prop_wire = forAll genBody $ \text -> let bytes=LBS.toStrict (encode (object ["op" .= ("create"::String),"body" .= decodeText text]))
  in parseWire bytes === Right (Action (C.CreatePost text))

check :: String -> Bool -> IO ()
check message passed = do
  putStrLn ((if passed then "PASS " else "FAIL ") <> message)
  unless passed exitFailure

main :: IO ()
main = do
  let run name p = do
        putStrLn name
        r <- quickCheckWithResult stdArgs {maxSuccess=2000,maxSize=50,replay=Just (mkQCGen 20261024,0)} p
        unless (isSuccess r) exitFailure
  run "extracted execute vs independent Agda model" prop_oracle
  run "extracted renderer vs Agda, no tag openers, sixfold bound" prop_render
  run "accepted edits protect every other user and preserve owners" prop_ownership
  run "anonymous writes are rejected" prop_guest
  run "random protocol traces preserve authorization and resource limits" prop_trace
  run "wire-to-core body roundtrip for entire glyph alphabet" prop_wire
  check "all 91 safe constructors map bijectively without delimiters"
    (length safeAlphabet == 91 && length (nub safeAlphabet)==91 && all (`notElem` safeAlphabet) ("<>&\"'" :: String))
  let alphabet=[' '..'~']<>"\n"
  check "all supported ASCII characters roundtrip" ((encodeText (Text.pack alphabet) >>= (Right . decodeText)) == Right (Text.pack alphabet))
  check "all safe glyphs agree with Agda renderer" (let xs=map C.Plain [minBound..maxBound] in C.render xs==Oracle.render xs)
  let valid=replicate 256 (C.Plain C.LA); oversized=replicate 257 (C.Plain C.LA)
  check "body at 256 accepted" (case C.execute textLimit postLimit (C.Logged C.Alice) (C.CreatePost valid) [] of C.Accepted _ _ -> True; _ -> False)
  check "body at 257 rejected by extracted core" (C.execute textLimit postLimit (C.Logged C.Alice) (C.CreatePost oversized) [] == C.Denied C.TooLong)
  check "33rd post rejected by extracted core" (C.execute textLimit postLimit (C.Logged C.Alice) (C.CreatePost []) (replicate 32 (C.PostC C.Alice [])) == C.Denied C.ForumFull)
  forM_ ["{", "{}", "{\"op\":\"fetch\",\"url\":\"http://127.0.0.1\"}",
    "{\"op\":\"create\",\"body\":\"ok\",\"owner\":\"bob\"}",
    "{\"op\":\"edit\",\"id\":-1,\"body\":\"x\"}",
    "{\"op\":\"edit\",\"id\":1.5,\"body\":\"x\"}",
    "{\"op\":\"create\",\"body\":{\"nested\":{\"too\":\"deep\"}}}",
    "{\"op\":\"create\",\"body\":\"\\u0000\"}"] $ \input ->
      check ("malformed/unsupported wire input rejected: "<>BS.unpack input) (case parseWire input of Left _ -> True; _ -> False)
  check "wire request >4096 bytes rejected before JSON" (case parseWire (BS.replicate 4097 'x') of Left _ -> True; _ -> False)
  let attack="<script>fetch('https://attacker.invalid')</script><img src=x onerror=alert(1)>"
  text <- either error pure (encodeText attack)
  check "attack is data, escaped by extracted renderer" (not ("<script>" `Text.isInfixOf` renderFragment text) && "&lt;script&gt;" `Text.isInfixOf` renderFragment text)
  putStrLn "All core and adapter tests passed."
