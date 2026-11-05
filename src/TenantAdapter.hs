{-# LANGUAGE OverloadedStrings #-}
module TenantAdapter (principal) where

import ClientCore qualified as C
import ForumCore qualified as F
import VerifiedTenant qualified as V

principal :: C.Context -> V.Principal
principal ctx = case C.current ctx of
  Nothing -> V.anonymous
  Just (C.GrantC user role) -> maybe V.anonymous (\tenant -> V.member tenant (toRole role)) (V.tenantId (tenantOf user))
  where
    tenantOf F.Alice = "alpha"
    tenantOf F.Bob = "beta"
    toRole C.Viewer = V.Reader
    toRole C.Editor = V.Writer
