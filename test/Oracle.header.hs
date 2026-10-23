-- TEST ONLY. Generated explicit datatype bridge to independent MAlonzo code.
module Oracle (execute, render) where
import ForumCore qualified as C
import MAlonzo.Code.ForumCore qualified as M
toSafe :: C.SafeChar -> M.T_SafeChar_26
