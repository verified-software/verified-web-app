-- TEST ONLY. Explicit typed bridge to independently generated MAlonzo code.
module ClientOracle (run, step, confined, transaction) where
import ClientCore qualified as C
import ForumCore qualified as F
import Oracle qualified as O
import MAlonzo.Code.ClientCore qualified as M
import MAlonzo.Code.ClientModel qualified as W

rank :: C.Rank -> M.@Type.Rank@
rank C.Viewer = M.@Ctor.Viewer@
rank C.Editor = M.@Ctor.Editor@
backRank :: M.@Type.Rank@ -> C.Rank
backRank M.@Ctor.Viewer@ = C.Viewer
backRank M.@Ctor.Editor@ = C.Editor
grant :: C.Grant -> M.@Type.Grant@
grant (C.GrantC u r) = M.@Ctor.GrantC@ (O.user u) (rank r)
backGrant :: M.@Type.Grant@ -> C.Grant
backGrant (M.@Ctor.GrantC@ u r) = C.GrantC (O.backUser u) (backRank r)
grantList :: Maybe C.Grant -> [M.@Type.Grant@]
grantList = maybe [] ((:[]) . grant)
context :: [M.@Type.Grant@] -> [M.@Type.Grant@] -> C.Context
context c p = C.Ctx (first c) (first p)
  where first [] = Nothing
        first [g] = Just (backGrant g)
        first _ = error "Oracle exposed a non-Maybe context"
expr :: C.Expr -> M.@Type.Expr@
expr (C.Literal text) = M.@Ctor.Literal@ (map O.glyph text)
expr (C.PrivateOf u) = M.@Ctor.PrivateOf@ (O.user u)
vault :: C.Vault -> M.@Type.Vault@
vault (C.VaultC a b) = M.@Ctor.VaultC@ (map O.glyph a) (map O.glyph b)
op :: C.Op -> M.@Type.Op@
op C.ReadPublic = M.@Ctor.ReadPublic@
op C.SignIn = M.@Ctor.SignIn@
op C.SignOut = M.@Ctor.SignOut@
op C.ReadOnly = M.@Ctor.ReadOnly@
op (C.Publish e) = M.@Ctor.Publish@ (expr e)
op (C.Revise i e) = M.@Ctor.Revise@ (O.count i) (expr e)
op (C.Inspect e) = M.@Ctor.Inspect@ (expr e)
program :: C.Program -> M.@Type.Program@
program C.Stop = M.@Ctor.Stop@
program (C.Invoke action rest) = M.@Ctor.Invoke@ (op action) (program rest)
program (C.Choose e yes no) = M.@Ctor.Choose@ (expr e) (program yes) (program no)
backValue :: M.@Type.Value@ -> C.Value
backValue (M.@Ctor.Public@ text) = C.Public (map O.backGlyph text)
backValue (M.@Ctor.Classified@ u text) = C.Classified (O.backUser u) (map O.backGlyph text)
backError :: M.@Type.Error@ -> C.Error
backError M.@Ctor.NoAuthority@ = C.NoAuthority
backError M.@Ctor.BadState@ = C.BadState
backError M.@Ctor.NoLoginOffer@ = C.NoLoginOffer
backError M.@Ctor.NoPrivateAccess@ = C.NoPrivateAccess
backError M.@Ctor.SecretSink@ = C.SecretSink
backError M.@Ctor.SecretControl@ = C.SecretControl
backError M.@Ctor.Exhausted@ = C.Exhausted
backError (M.@Ctor.ForumError@ e) = C.ForumError (O.backError e)
backEvent :: M.@Type.Event@ -> C.Event
backEvent M.@Ctor.SawPublic@ = C.SawPublic
backEvent M.@Ctor.SessionClosed@ = C.SessionClosed
backEvent M.@Ctor.RightsReduced@ = C.RightsReduced
backEvent (M.@Ctor.SessionOpened@ u) = C.SessionOpened (O.backUser u)
backEvent (M.@Ctor.Posted@ u) = C.Posted (O.backUser u)
backEvent (M.@Ctor.Revised@ u i) = C.Revised (O.backUser u) (O.backCount i)
backEvent (M.@Ctor.Displayed@ v) = C.Displayed (backValue v)
backEvent (M.@Ctor.Tested@ b) = C.Tested b
backResult (W.@Model.FlatRefused@ e) = C.Refused (backError e)
backResult (W.@Model.FlatFinished@ c p ps es) = C.Finished (context c p) (map O.backPost ps) (map backEvent es)
backStep (W.@Model.FlatRejected@ e) = C.Rejected (backError e)
backStep (W.@Model.FlatApplied@ c p ps e) = C.Applied (context c p) (map O.backPost ps) (backEvent e)
backTransaction (W.@Model.FlatRollback@ e ps) = C.Rollback (backError e) (map O.backPost ps)
backTransaction (W.@Model.FlatCommit@ c p ps es) = C.Commit (context c p) (map O.backPost ps) (map backEvent es)
run :: F.Count -> F.Count -> F.Count -> C.Program -> C.Context -> [F.Post] -> C.Vault -> C.Result
run tl pl fuel p ctx ps v = backResult (W.@Fun.runModel@ (O.count tl) (O.count pl) (O.count fuel)
  (program p) (grantList (C.current ctx)) (grantList (C.pending ctx)) (map O.post ps) (vault v))
step :: F.Count -> F.Count -> C.Context -> C.Op -> [F.Post] -> C.Vault -> C.StepResult
step tl pl ctx action ps v = backStep (W.@Fun.stepModel@ (O.count tl) (O.count pl) (op action)
  (grantList (C.current ctx)) (grantList (C.pending ctx)) (map O.post ps) (vault v))
confined :: C.Context -> [C.Grant] -> Bool
confined ctx allowed = W.@Fun.confinedModel@ (grantList (C.current ctx)) (grantList (C.pending ctx)) (map grant allowed)
transaction :: F.Count -> F.Count -> F.Count -> C.Program -> C.Context -> [F.Post] -> C.Vault -> C.Transaction
transaction tl pl fuel p ctx ps v = backTransaction (W.@Fun.transactionModel@ (O.count tl) (O.count pl) (O.count fuel)
  (program p) (grantList (C.current ctx)) (grantList (C.pending ctx)) (map O.post ps) (vault v))
