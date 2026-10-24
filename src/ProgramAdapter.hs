{-# LANGUAGE OverloadedStrings #-}
module ProgramAdapter
  ( Bundle(..), decodeBundle, legacyProgram, eventsJSON, contextJSON, demoVault ) where
import Adapter (Wire(..), encodeText, decodeText, toCount)
import Control.Monad (unless)
import Data.Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.Aeson.Types (Parser, parseEither)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BSC
import Data.Text (Text)
import ForumCore qualified as F
import ClientCore qualified as C

data Bundle = Bundle { budget :: F.Count, program :: C.Program,
  credentials :: Maybe (Text,Text) } deriving Show

decodeBundle :: BS.ByteString -> Either String Bundle
decodeBundle bytes = do
  unless (BS.length bytes <= 16384) (Left "program request exceeds 16384 bytes")
  unless (depthWithin 24 bytes) (Left "program JSON nesting exceeds 24")
  raw <- eitherDecodeStrict' bytes
  parseEither parseBundle raw
  where
    parseBundle = withObject "Program request" $ \o -> do
      exact o ["budget","program","credentials"]
      fuel <- o .: "budget" :: Parser Integer
      unless (fuel >= 0 && fuel <= 32) (fail "budget must be an integer from 0 to 32")
      syntax <- o .: "program"
      (p,nodes) <- parseProgram syntax
      unless (nodes <= 128) (fail "program exceeds 128 nodes")
      supplied <- o .:? "credentials" >>= traverse (withObject "Credentials" $ \c -> do
        exact c ["user","password"]
        (,) <$> c .: "user" <*> c .: "password")
      pure (Bundle (toCount (fromInteger fuel)) p supplied)

exact :: Object -> [Text] -> Parser ()
exact obj allowed = unless (all ((`elem` allowed) . Key.toText) (KM.keys obj)) (fail "unsupported field")

parseExpr :: Value -> Parser C.Expr
parseExpr = withObject "Expression" $ \o -> case KM.keys o of
  ["text"] -> C.Literal <$> (o .: "text" >>= either fail pure . encodeText)
  ["private"] -> C.PrivateOf <$> (o .: "private" >>= parseUser)
  _ -> fail "expression must contain exactly text or private"
  where
    parseUser :: Text -> Parser F.User
    parseUser "alice" = pure F.Alice
    parseUser "bob" = pure F.Bob
    parseUser _ = fail "unknown private-data owner"

parseProgram :: Value -> Parser (C.Program, Int)
parseProgram = withObject "Program" $ \o ->
  if KM.member "done" o then do
    exact o ["done"]
    done <- o .: "done"
    unless done (fail "done must be true")
    pure (C.Stop,1)
  else if KM.member "if" o then do
    exact o ["if","then","else"]
    expr <- o .: "if" >>= parseExpr
    (yes,n) <- o .: "then" >>= parseProgram
    (no,m) <- o .: "else" >>= parseProgram
    pure (C.Choose expr yes no,1+n+m)
  else do
    op <- o .: "op" :: Parser Text
    let fields more = exact o (["op","next"]<>more)
        value = o .: "value" >>= parseExpr
    action <- case op of
      "read" -> fields [] >> pure C.ReadPublic
      "login" -> fields [] >> pure C.SignIn
      "logout" -> fields [] >> pure C.SignOut
      "restrict" -> fields [] >> pure C.ReadOnly
      "inspect" -> fields ["value"] >> (C.Inspect <$> value)
      "create" -> fields ["value"] >> (C.Publish <$> value)
      "edit" -> do
        fields ["id","value"]
        i <- o .: "id" :: Parser Integer
        unless (i >= 0 && i < 32) (fail "post id must be an integer from 0 to 31")
        C.Revise (toCount (fromInteger i)) <$> value
      _ -> fail "unsupported program operation"
    (rest,n) <- maybe (pure (C.Stop,0)) parseProgram (KM.lookup "next" o)
    pure (C.Invoke action rest,1+n)

-- Original command endpoint is lowered to the SAME interpreter, so a token
-- attenuated by /program cannot regain authority through the legacy endpoint.
legacyProgram :: Wire -> C.Program
legacyProgram (Login _ _) = C.Invoke C.SignIn C.Stop
legacyProgram (Action F.ReadPosts) = C.Invoke C.ReadPublic C.Stop
legacyProgram (Action (F.CreatePost body)) = C.Invoke (C.Publish (C.Literal body)) C.Stop
legacyProgram (Action (F.EditPost i body)) = C.Invoke (C.Revise i (C.Literal body)) C.Stop
legacyProgram (Action F.Logout) = C.Invoke C.SignOut C.Stop
legacyProgram (Action (F.Authenticate _)) = C.Invoke C.SignIn C.Stop

contextJSON :: C.Context -> Value
contextJSON (C.Ctx Nothing _) = object ["authenticated" .= False]
contextJSON (C.Ctx (Just (C.GrantC u rank)) _) = object
  ["authenticated" .= True,"user" .= userText u,"writeOwn" .= (rank==C.Editor)]

userText :: F.User -> Text
userText F.Alice = "alice"
userText F.Bob = "bob"

eventsJSON :: [C.Event] -> Value
eventsJSON = toJSON . map event
  where
    event C.SawPublic = object ["kind" .= ("read"::Text)]
    event C.SessionClosed = object ["kind" .= ("logout"::Text)]
    event C.RightsReduced = object ["kind" .= ("restricted"::Text)]
    event (C.SessionOpened u) = object ["kind" .= ("login"::Text),"user" .= userText u]
    event (C.Posted u) = object ["kind" .= ("created"::Text),"user" .= userText u]
    event (C.Revised u _) = object ["kind" .= ("edited"::Text),"user" .= userText u]
    event (C.Tested b) = object ["kind" .= ("branch"::Text),"empty" .= b]
    event (C.Displayed (C.Public text)) = object ["kind" .= ("public"::Text),"body" .= decodeText text]
    event (C.Displayed (C.Classified u text)) = object ["kind" .= ("private"::Text),"owner" .= userText u,"body" .= decodeText text]

demoVault :: C.Vault
demoVault = C.VaultC (text "Alice private draft: alpha") (text "Bob private draft: beta")
  where text = either error id . encodeText

-- Bound the byte-level JSON pre-scan before invoking the unverified parser.
depthWithin :: Int -> BS.ByteString -> Bool
depthWithin limit = scan (0::Int) False False . BSC.unpack
  where
    scan depth quoted escaped [] = depth==0 && not quoted && not escaped
    scan depth True True (_:xs) = scan depth True False xs
    scan depth True False ('\\':xs) = scan depth True True xs
    scan depth True False ('"':xs) = scan depth False False xs
    scan depth True False (_:xs) = scan depth True False xs
    scan depth False _ ('"':xs) = scan depth True False xs
    scan depth False _ (x:xs)
      | x=='{' || x=='[' = depth<limit && scan (depth+1) False False xs
      | x=='}' || x==']' = depth>0 && scan (depth-1) False False xs
      | otherwise = scan depth False False xs
