module RevocationCore
  (mentionsRevocation, afterFailure)
where

import Prelude hiding (LT)
import qualified ClientCore as C (Op(ReadOnly, SignOut), Program(Choose, Invoke, Stop))

mentionsRevocation :: C.Program -> Bool
mentionsRevocation C.Stop = False
mentionsRevocation (C.Invoke C.SignOut rest) = True
mentionsRevocation (C.Invoke C.ReadOnly rest) = True
mentionsRevocation (C.Invoke _ rest) = mentionsRevocation rest
mentionsRevocation (C.Choose expression left right)
  = mentionsRevocation left || mentionsRevocation right

afterFailure :: C.Program -> Maybe a -> Maybe a
afterFailure program session
  = if mentionsRevocation program then Nothing else session
