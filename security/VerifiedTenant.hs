{-# LANGUAGE OverloadedStrings #-}
module VerifiedTenant
  ( TenantId, Principal, Scoped, Role(..), Action(..), tenantId, anonymous, member, forTenant, guarded ) where

import Data.Bits (testBit)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TE
import TenantCore (Role(..), Action(..))
import TenantCore qualified as Core

newtype TenantId = TenantId [Bool] deriving (Eq, Ord, Show)
newtype Principal = Principal Core.Principal
newtype Scoped a = Scoped (Core.Scoped a)

tenantId :: Text -> Maybe TenantId
tenantId name
  | Text.null name || Text.length name > 32 || not (Text.all allowed name) = Nothing
  | otherwise = Just (TenantId [testBit byte n | byte <- BS.unpack (TE.encodeUtf8 name), n <- [7,6..0]])
  where
    allowed c = ('a' <= c && c <= 'z') || ('0' <= c && c <= '9') || c == '-'

anonymous :: Principal
anonymous = Principal Core.Anonymous

member :: TenantId -> Role -> Principal
member (TenantId key) role = Principal (Core.Member key role)

forTenant :: TenantId -> a -> Scoped a
forTenant (TenantId key) value = Scoped (Core.Resource key value)

guarded :: Principal -> Action -> Scoped a -> Maybe a
guarded (Principal p) action (Scoped resource) = Core.guarded p action resource
