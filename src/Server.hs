{-# LANGUAGE OverloadedStrings #-}
module Server (runServer) where
import Adapter
import ProgramAdapter
import Control.Concurrent.MVar
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BSC
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text.Encoding qualified as TE
import ForumCore qualified as F
import ClientCore qualified as C
import Network.HTTP.Types
import Network.Wai hiding (vault)
import Network.Wai.Handler.Warp
import Numeric (showHex)
import System.IO (IOMode(ReadMode), withBinaryFile)

data World = World { sessions :: Map BS.ByteString C.Context, posts :: [F.Post], vault :: C.Vault }
headers :: ResponseHeaders
headers = [("X-Content-Type-Options","nosniff"),("Cache-Control","no-store"),
  ("Content-Security-Policy","default-src 'none'; base-uri 'none'; frame-ancestors 'none'")]
json :: Status -> Value -> Response
json status value = responseLBS status ((hContentType,"application/json; charset=utf-8"):headers) (encode value)
failure :: Status -> String -> Response
failure status message = json status (object ["error" .= message])

newToken :: IO BS.ByteString
newToken = withBinaryFile "/dev/urandom" ReadMode $ \h -> do
  bytes <- BS.hGet h 32
  if BS.length bytes/=32 then ioError (userError "entropy source short read") else
    pure . BSC.pack . concatMap (\b -> let x=showHex b "" in if length x==1 then '0':x else x) $ BS.unpack bytes

readBounded :: Int -> Request -> IO (Either String BS.ByteString)
readBounded limit req = go 0 []
  where
    go size chunks = do
      chunk <- getRequestBodyChunk req
      let size'=size+BS.length chunk
      if size'>limit then pure (Left ("request exceeds "<>show limit<>" bytes")) else
        if BS.null chunk then pure (Right (BS.concat (reverse chunks))) else go size' (chunk:chunks)

resolve :: Request -> World -> Either Response (Maybe BS.ByteString,C.Context)
resolve req world = case lookup hAuthorization (requestHeaders req) of
  Nothing -> Right (Nothing,C.Ctx Nothing Nothing)
  Just raw -> case BS.stripPrefix "Bearer " raw >>= (\t -> (t,) <$> Map.lookup t (sessions world)) of
    Just found -> Right (Just (fst found),snd found)
    Nothing -> Left (failure status401 "invalid or expired session")

-- Both routes enforce the extracted interpreter. No alternate legacy write
-- path can bypass attenuation. Only a Finished program can commit state.
process :: MVar World -> Request -> Bool -> Bundle -> IO Response
process ref req legacy bundle = modifyMVar ref $ \world -> case resolve req world of
  Left response -> pure (world,response)
  Right (token,stored) -> case loginOffer of
    Left response -> pure (world,response)
    Right offer ->
      let ctx=C.Ctx (C.current stored) offer
       in case C.run textLimit postLimit (budget bundle) (program bundle) ctx (posts world) (vault world) of
         C.Refused err -> pure (world,failure (errorStatus ctx err) (show err))
         C.Finished next ps trace
           | not (C.confined next (C.sources ctx)) -> pure (world,failure status500 "capability origin check failed")
           | otherwise -> commit world token stored next ps trace
  where
    loginOffer = case credentials bundle of
      Nothing -> Right Nothing
      Just (username,password) -> case authenticate username password of
        Nothing -> Left (failure status401 "bad credentials")
        Just u -> Right (Just (C.GrantC u C.Editor))
    commit world token stored next ps trace = case (C.current stored,C.current next) of
      (Nothing,Just _) ->
        if Map.size (sessions world)>=64 then pure (world,failure status429 "session capacity reached") else do
          fresh <- uniqueToken (sessions world)
          let clean=C.Ctx (C.current next) Nothing
              world'=world {sessions=Map.insert fresh clean (sessions world),posts=ps}
          pure (world',response next ps trace (Just fresh) False)
      (Just _,Nothing) ->
        let sessions'=maybe (sessions world) (`Map.delete` sessions world) token
         in pure (world {sessions=sessions',posts=ps},response next ps trace Nothing True)
      _ ->
        let clean=C.Ctx (C.current next) Nothing
            sessions'=maybe (sessions world) (\t -> Map.insert t clean (sessions world)) token
         in pure (world {sessions=sessions',posts=ps},response next ps trace Nothing False)
    response next ps trace fresh loggedOut =
      let fields=["posts" .= postsJSON ps] <>
            maybe [] (\token -> ["token" .= TE.decodeUtf8 token]) fresh <>
            (if loggedOut then ["loggedOut" .= True] else []) <>
            (if legacy then [] else ["context" .= contextJSON next,"trace" .= eventsJSON trace,
              "steps" .= length trace,"accepted" .= True])
       in json status200 (object fields)
    uniqueToken table = do
      fresh <- newToken
      if Map.member fresh table then uniqueToken table else pure fresh

errorStatus :: C.Context -> C.Error -> Status
errorStatus ctx C.NoAuthority = case C.current ctx of Nothing -> status401; Just _ -> status403
errorStatus _ C.BadState = status409
errorStatus _ C.NoLoginOffer = status401
errorStatus _ C.NoPrivateAccess = status403
errorStatus _ C.SecretSink = status403
errorStatus _ C.SecretControl = status403
errorStatus _ C.Exhausted = status429
errorStatus _ (C.ForumError F.Unauthorized) = status401
errorStatus _ (C.ForumError F.BadTransition) = status409
errorStatus _ (C.ForumError F.TooLong) = status413
errorStatus _ (C.ForumError F.ForumFull) = status409
errorStatus _ (C.ForumError F.EditDenied) = status403

application :: MVar World -> Application
application ref req respond = case (requestMethod req,pathInfo req) of
  ("GET",[]) -> do
    world <- readMVar ref
    let fragments=["<article><pre>"<>renderFragment (F.body p)<>"</pre></article>" | p <- posts world]
        html="<!doctype html><html><head><meta charset=utf-8><title>Verified forum</title></head><body><h1>Verified forum</h1>"<>
          mconcat fragments<>"</body></html>"
    respond (responseLBS status200 ((hContentType,"text/html; charset=utf-8"):headers) (LBS.fromStrict (TE.encodeUtf8 html)))
  ("GET",["posts"]) -> readMVar ref >>= respond . json status200 . postsJSON . posts
  ("POST",["command"]) -> post 4096 $ \bytes -> case parseWire bytes of
    Left err -> respond (failure status400 err)
    Right wire ->
      let supplied=case wire of Login u p -> Just (u,p); _ -> Nothing
       in process ref req True (Bundle (toCount 1) (legacyProgram wire) supplied) >>= respond
  ("POST",["program"]) -> post 16384 $ \bytes -> case decodeBundle bytes of
    Left err -> respond (failure status400 err)
    Right bundle -> process ref req False bundle >>= respond
  _ -> respond (failure status404 "unsupported endpoint")
  where
    post limit k =
      if lookup hContentType (requestHeaders req)/=Just "application/json" then
        respond (failure status415 "Content-Type must be application/json")
      else readBounded limit req >>= either (respond . failure status413) k

runServer :: Int -> IO ()
runServer port = do
  world <- newMVar (World Map.empty [] demoVault)
  putStrLn ("Verified forum at http://127.0.0.1:"<>show port)
  runSettings (setTimeout 5 (setHost "127.0.0.1" (setPort port defaultSettings))) (application world)
