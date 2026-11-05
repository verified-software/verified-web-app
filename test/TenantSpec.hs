{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Control.Monad (unless)
import Data.Text qualified as Text
import TenantCore qualified as T
import VerifiedTenant qualified as V
import MAlonzo.Code.TenantCore qualified as Model
import Test.QuickCheck
import Test.QuickCheck.Random (mkQCGen)
import System.Exit (exitFailure)

data Example = Example T.Principal [Bool] T.Action Int deriving Show

instance Arbitrary Example where
  arbitrary = do
    source <- resize 32 arbitrary
    target <- frequency [(1,pure source),(1,resize 32 arbitrary)]
    role <- elements [T.Reader,T.Writer]
    principal <- frequency [(1,pure T.Anonymous),(3,pure (T.Member source role))]
    Example principal target <$> elements [T.Read,T.Write] <*> arbitrary

modelPrincipal :: T.Principal -> Model.T_Principal_8
modelPrincipal T.Anonymous = Model.C_Anonymous_10
modelPrincipal (T.Member key T.Reader) = Model.C_Member_12 key Model.C_Reader_4
modelPrincipal (T.Member key T.Writer) = Model.C_Member_12 key Model.C_Writer_6

modelAction :: T.Action -> Model.T_Action_14
modelAction T.Read = Model.C_Read_16
modelAction T.Write = Model.C_Write_18

expected :: T.Principal -> [Bool] -> T.Action -> Bool
expected T.Anonymous _ _ = False
expected (T.Member _ T.Reader) _ T.Write = False
expected (T.Member source _) target _ = source == target

prop_model :: Example -> Property
prop_model (Example p target action value) = conjoin
  [ T.permitted p target action === expected p target action
  , T.permitted p target action === Model.d_permitted_38 (modelPrincipal p) target (modelAction action)
  , T.guarded p action (T.Resource target value) === if expected p target action then Just value else Nothing
  ]

genTenant :: Gen Text.Text
genTenant = Text.pack <$> resize 32 (listOf1 (elements (['a'..'z'] <> ['0'..'9'] <> "-")))

prop_encoding :: Property
prop_encoding = forAll genTenant $ \first -> forAll (frequency [(1,pure first),(1,genTenant)]) $ \second ->
  case (V.tenantId first,V.tenantId second) of
    (Just a,Just b) -> conjoin [(a == b) === (first == second),
      V.guarded (V.member a V.Writer) V.Write (V.forTenant b (42::Int)) === if a == b then Just 42 else Nothing]
    _ -> counterexample "valid tenant name rejected" False

main :: IO ()
main = do
  let run name p = do
        putStrLn name
        result <- quickCheckWithResult stdArgs {maxSuccess=5000, maxSize=40,
          replay=Just (mkQCGen 20261105,0)} p
        unless (isSuccess result) exitFailure
  run "policy agrees with Agda MAlonzo and denies unauthorized data" (property prop_model)
  run "tenant encoding preserves identity and guarded access" prop_encoding
  unless (V.tenantId "" == Nothing && V.tenantId (Text.replicate 33 "a") == Nothing &&
          V.tenantId "alpha/../beta" == Nothing && V.tenantId "Ą" == Nothing) exitFailure
  putStrLn "All tenant-policy tests passed."
