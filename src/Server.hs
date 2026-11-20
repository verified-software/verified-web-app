{-# LANGUAGE OverloadedStrings #-}
module Server (runServer) where
import Adapter
import ProgramAdapter
import TenantAdapter (principal)
import Control.Concurrent.MVar
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BSC
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text.Encoding qualified as TE
import Data.Text qualified as Text
import ForumCore qualified as F
import ClientCore qualified as C
import RevocationCore qualified as R
import VerifiedTenant qualified as T
import Network.HTTP.Types
import Network.Wai hiding (vault)
import Network.Wai.Handler.Warp
import Numeric (showHex)
import System.IO (IOMode(ReadMode), withBinaryFile)
import System.Environment (lookupEnv)

data World = World { sessions :: Map BS.ByteString C.Context, posts :: [F.Post],
  tenantPosts :: Map T.TenantId [F.Post], vault :: C.Vault }
data Scope = Public | Tenant T.TenantId

scopePosts :: World -> Scope -> [F.Post]
scopePosts world Public = posts world
scopePosts world (Tenant key) = Map.findWithDefault [] key (tenantPosts world)

putScopePosts :: Scope -> [F.Post] -> World -> World
putScopePosts Public ps world = world {posts=ps}
putScopePosts (Tenant key) ps world = world {tenantPosts=Map.insert key ps (tenantPosts world)}

accessPosts :: C.Context -> T.Action -> Scope -> World -> Maybe [F.Post]
accessPosts _ _ Public world = Just (posts world)
accessPosts ctx action scope@(Tenant key) world =
  T.guarded (principal ctx) action (T.forTenant key (scopePosts world scope))

accessDenied :: C.Context -> Response
accessDenied ctx = case C.current ctx of
  Nothing -> failure status401 "authentication required"
  Just _ -> failure status403 "tenant access denied"
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
process :: MVar World -> Request -> Scope -> Bool -> Bundle -> IO Response
process ref req scope legacy bundle = modifyMVar ref $ \world -> case resolve req world of
  Left response -> pure (world,response)
  Right (token,stored) -> case accessPosts stored T.Write scope world of
    Nothing -> pure (world,accessDenied stored)
    Just before -> case loginOffer of
      Left response -> pure (world,response)
      Right offer ->
        let ctx=C.Ctx (C.current stored) offer
         in case C.transaction textLimit postLimit (budget bundle) (program bundle) ctx before (vault world) of
           C.Rollback err _ ->
             let remaining = R.afterFailure (program bundle) token
                 sessionMap = case (token,remaining) of
                   (Just old,Nothing) -> Map.delete old (sessions world)
                   _ -> sessions world
              in pure (world {sessions=sessionMap},failure (errorStatus ctx err) (show err))
           C.Commit next ps trace
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
              world'=(putScopePosts scope ps world) {sessions=Map.insert fresh clean (sessions world)}
          pure (world',successResponse next ps trace (Just fresh) False)
      (Just _,Nothing) ->
        let sessions'=maybe (sessions world) (`Map.delete` sessions world) token
         in pure ((putScopePosts scope ps world) {sessions=sessions'},successResponse next ps trace Nothing True)
      _ ->
        let clean=C.Ctx (C.current next) Nothing
            sessions'=maybe (sessions world) (\t -> Map.insert t clean (sessions world)) token
         in pure ((putScopePosts scope ps world) {sessions=sessions'},successResponse next ps trace Nothing False)
    successResponse next ps trace fresh loggedOut =
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
  ("GET",["tenants",name,"posts"]) -> withTenant name $ \scope -> do
    world <- readMVar ref
    case resolve req world of
      Left response -> respond response
      Right (_,ctx) -> case accessPosts ctx T.Read scope world of
        Nothing -> respond (accessDenied ctx)
        Just ps -> respond (json status200 (postsJSON ps))
  ("POST",["command"]) -> command Public
  ("POST",["program"]) -> programRoute Public
  ("POST",["tenants",name,"command"]) -> withTenant name command
  ("POST",["tenants",name,"program"]) -> withTenant name programRoute
  _ -> respond (failure status404 "unsupported endpoint")
  where
    withTenant name k = case T.tenantId name of
      Nothing -> respond (failure status400 "invalid tenant id")
      Just key -> k (Tenant key)
    command scope = post 4096 $ \bytes -> case parseWire bytes of
      Left err -> respond (failure status400 err)
      Right wire ->
        let supplied=case wire of Login u p -> Just (u,p); _ -> Nothing
         in process ref req scope True (Bundle (toCount 1) (legacyProgram wire) supplied) >>= respond
    programRoute scope = post 16384 $ \bytes -> case decodeBundle bytes of
      Left err -> respond (failure status400 err)
      Right bundle -> process ref req scope False bundle >>= respond
    post limit k =
      if lookup hContentType (requestHeaders req)/=Just "application/json" then
        respond (failure status415 "Content-Type must be application/json")
      else readBounded limit req >>= either (respond . failure status413) k

runServer :: Int -> IO ()
runServer port = do
  privateVault <- fixtureVault
  world <- newMVar (World Map.empty [] Map.empty privateVault)
  putStrLn ("Verified forum at http://127.0.0.1:"<>show port)
  runSettings (setTimeout 5 (setHost "127.0.0.1" (setPort port defaultSettings))) (application world)

-- Trusted test configuration, never read from a client request. Allows paired
-- HTTP runs with different Alice secrets and otherwise identical state.
fixtureVault :: IO C.Vault
fixtureVault = do
  let C.VaultC defaultAlice defaultBob=demoVault
      load name fallback = lookupEnv name >>= maybe (pure fallback) (either (ioError . userError) pure . encodeText . Text.pack)
  C.VaultC <$> load "FORUM_ALICE_DRAFT" defaultAlice <*> load "FORUM_BOB_DRAFT" defaultBob
