{-# LANGUAGE OverloadedStrings #-}
module Adapter
  ( Wire(..), parseWire, encodeText, decodeText, safeAlphabet, toCount, textLimit,
    postLimit, authenticate, renderFragment, postsJSON, depthOK ) where

import Control.Monad (unless)
import Data.Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.Aeson.Types (Parser, parseEither)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BSC
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import ForumCore qualified as C

data Wire = Login Text Text | Action C.Request deriving (Eq, Show)

safeAlphabet :: String
safeAlphabet = ['a'..'z'] <> ['A'..'Z'] <> ['0'..'9'] <> " !#$%()*+,-./:;=?@[\\]^_`{|}~\n"

toCount :: Int -> C.Count
toCount n = iterate C.More C.Zero !! max 0 n

textLimit, postLimit :: C.Count
textLimit = toCount 256
postLimit = toCount 32

encodeText :: Text -> Either String [C.Glyph]
encodeText = traverse convert . Text.unpack
  where
    table = Map.fromList (zip safeAlphabet (map C.Plain [minBound..maxBound]) <>
      [('<',C.Lt),('>',C.Gt),('&',C.Amp),('"',C.DQuote),('\'',C.SQuote)])
    convert c = maybe (Left "Only printable ASCII and newline are supported") Right (Map.lookup c table)

decodeText :: [C.Glyph] -> Text
decodeText = Text.pack . map convert
  where
    convert (C.Plain c) = safeAlphabet !! fromEnum c
    convert C.Lt = '<'
    convert C.Gt = '>'
    convert C.Amp = '&'
    convert C.DQuote = '"'
    convert C.SQuote = '\''

renderFragment :: [C.Glyph] -> Text
renderFragment = decodeText . C.render

-- Demo credentials. Authentication and session-token handling are outside the
-- proof; only this adapter creates the core's Authenticate capability.
authenticate :: Text -> Text -> Maybe C.User
authenticate "alice" "alice-demo" = Just C.Alice
authenticate "bob" "bob-demo" = Just C.Bob
authenticate _ _ = Nothing

parseWire :: BS.ByteString -> Either String Wire
parseWire bytes = do
  unless (BS.length bytes <= 4096) (Left "request exceeds 4096 bytes")
  unless (depthOK bytes) (Left "message nesting exceeds 2")
  value <- eitherDecodeStrict' bytes
  parseEither parseCommand value
  where
    parseCommand = withObject "Command" $ \o -> do
      op <- o .: "op" :: Parser Text
      let exact allowed = unless (all ((`elem` allowed) . Key.toText) (KM.keys o)) (fail "unsupported field")
          body = (o .: "body") >>= either fail pure . encodeText
      case op of
        "read" -> exact ["op"] >> pure (Action C.ReadPosts)
        "login" -> exact ["op","user","password"] >> (Login <$> o .: "user" <*> o .: "password")
        "logout" -> exact ["op"] >> pure (Action C.Logout)
        "create" -> exact ["op","body"] >> (Action . C.CreatePost <$> body)
        "edit" -> do
          exact ["op","id","body"]
          i <- o .: "id" :: Parser Integer
          unless (i >= 0 && i < 32) (fail "post id must be an integer from 0 to 31")
          Action . C.EditPost (toCount (fromInteger i)) <$> body
        _ -> fail "unsupported command"

-- Linear pre-scan before JSON decoding; brackets inside quoted strings do not
-- increase nesting. Full syntax validation remains Aeson's job.
depthOK :: BS.ByteString -> Bool
depthOK = scan (0 :: Int) False False . BSC.unpack
  where
    scan depth quoted escaped [] = depth == 0 && not quoted && not escaped
    scan depth True True (_:xs) = scan depth True False xs
    scan depth True False ('\\':xs) = scan depth True True xs
    scan depth True False ('"':xs) = scan depth False False xs
    scan depth True False (_:xs) = scan depth True False xs
    scan depth False _ ('"':xs) = scan depth True False xs
    scan depth False _ (x:xs)
      | x == '{' || x == '[' = depth < 2 && scan (depth+1) False False xs
      | x == '}' || x == ']' = depth > 0 && scan (depth-1) False False xs
      | otherwise = scan depth False False xs

postsJSON :: [C.Post] -> Value
postsJSON ps = toJSON [object ["id" .= i, "owner" .= userText (C.owner p),
  "body" .= decodeText (C.body p)] | (i,p) <- zip [0::Int ..] ps]
  where userText C.Alice = "alice" :: Text
        userText C.Bob = "bob"
