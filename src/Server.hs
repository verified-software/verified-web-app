{-# LANGUAGE OverloadedStrings #-}
module Server (runServer) where
import Adapter
import Control.Concurrent.MVar
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BSC
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text.Encoding qualified as TE
import ForumCore qualified as C
import Network.HTTP.Types
import Network.Wai
import Network.Wai.Handler.Warp
import Numeric (showHex)
import System.IO (IOMode(ReadMode), withBinaryFile)

data World = World { sessions :: Map BS.ByteString C.Session, posts :: [C.Post] }

headers :: ResponseHeaders
headers = [("X-Content-Type-Options","nosniff"), ("Cache-Control","no-store"),
  ("Content-Security-Policy","default-src 'none'; base-uri 'none'; frame-ancestors 'none'")]

json :: Status -> Value -> Response
json status value = responseLBS status ((hContentType,"application/json; charset=utf-8"):headers) (encode value)

failure :: Status -> String -> Response
failure status message = json status (object ["error" .= message])

newToken :: IO BS.ByteString
newToken = withBinaryFile "/dev/urandom" ReadMode $ \h -> do
  bytes <- BS.hGet h 32
  if BS.length bytes /= 32 then ioError (userError "entropy source short read") else
    pure . BSC.pack . concatMap (\b -> let x=showHex b "" in if length x==1 then '0':x else x) $ BS.unpack bytes

readBounded :: Request -> IO (Either String BS.ByteString)
readBounded req = go 0 []
  where
    go size chunks = do
      chunk <- getRequestBodyChunk req
      let size' = size + BS.length chunk
      if size' > 4096 then pure (Left "request exceeds 4096 bytes") else
        if BS.null chunk then pure (Right (BS.concat (reverse chunks))) else go size' (chunk:chunks)

resolve :: Request -> World -> Either Response (Maybe BS.ByteString, C.Session)
resolve req world = case lookup hAuthorization (requestHeaders req) of
  Nothing -> Right (Nothing,C.Guest)
  Just raw -> case BS.stripPrefix "Bearer " raw >>= (\t -> (t,) <$> Map.lookup t (sessions world)) of
    Just (token,session) -> Right (Just token,session)
    Nothing -> Left (failure status401 "invalid or expired session")

process :: MVar World -> Request -> Wire -> IO Response
process ref req wire = modifyMVar ref $ \world -> case resolve req world of
  Left response -> pure (world,response)
  Right (token,session) -> case wire of
    Login username password -> case authenticate username password of
      Nothing -> pure (world,failure status401 "bad credentials")
      Just user -> apply world token session (C.Authenticate user)
    Action action -> apply world token session action
  where
    apply world token session action = case C.execute textLimit postLimit session action (posts world) of
      C.Denied err -> pure (world,failure (errorStatus err) (show err))
      C.Accepted next ps -> case (session,next) of
        (C.Guest,C.Logged _) -> do
          if Map.size (sessions world) >= 64 then pure (world,failure status429 "session capacity reached") else do
            fresh <- uniqueToken (sessions world)
            let world' = world {sessions=Map.insert fresh next (sessions world),posts=ps}
            pure (world',json status200 (object ["token" .= TE.decodeUtf8 fresh,"posts" .= postsJSON ps]))
        (C.Logged _,C.Guest) ->
          let sessions' = maybe (sessions world) (`Map.delete` sessions world) token
           in pure (world {sessions=sessions',posts=ps},json status200 (object ["loggedOut" .= True]))
        _ -> pure (world {posts=ps},json status200 (object ["posts" .= postsJSON ps]))
    uniqueToken table = do
      token <- newToken
      if Map.member token table then uniqueToken table else pure token
    errorStatus C.Unauthorized = status401
    errorStatus C.BadTransition = status409
    errorStatus C.TooLong = status413
    errorStatus C.ForumFull = status409
    errorStatus C.EditDenied = status403

application :: MVar World -> Application
application ref req respond = case (requestMethod req,pathInfo req) of
  ("GET",[]) -> do
    world <- readMVar ref
    let fragments = ["<article><pre>" <> renderFragment (C.body p) <> "</pre></article>" | p <- posts world]
        html = "<!doctype html><html><head><meta charset=utf-8><title>Verified forum</title></head><body><h1>Verified forum</h1>" <>
          mconcat fragments <> "</body></html>"
    respond (responseLBS status200 ((hContentType,"text/html; charset=utf-8"):headers) (LBS.fromStrict (TE.encodeUtf8 html)))
  ("GET",["posts"]) -> do
    world <- readMVar ref
    respond (json status200 (postsJSON (posts world)))
  ("POST",["command"]) ->
    if lookup hContentType (requestHeaders req) /= Just "application/json" then
      respond (failure status415 "Content-Type must be application/json")
    else do
      body <- readBounded req
      case body of
        Left err -> respond (failure status413 err)
        Right bytes -> case parseWire bytes of
          Left err -> respond (failure status400 err)
          Right wire -> process ref req wire >>= respond
  _ -> respond (failure status404 "unsupported endpoint")

runServer :: Int -> IO ()
runServer port = do
  world <- newMVar (World Map.empty [])
  putStrLn ("Verified forum at http://127.0.0.1:" <> show port)
  runSettings (setTimeout 5 (setHost "127.0.0.1" (setPort port defaultSettings))) (application world)
