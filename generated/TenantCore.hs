module TenantCore
  (Role(..), Principal(..), Action(..), Scoped(..), sameId, permitted, guarded)
where

import Prelude hiding (LT)

data Role = Reader
          | Writer
              deriving (Eq, Show)

data Principal = Anonymous
               | Member [Bool] Role
                   deriving (Eq, Show)

data Action = Read
            | Write
                deriving (Eq, Show)

data Scoped a = Resource [Bool] a

sameId :: [Bool] -> [Bool] -> Bool
sameId [] [] = True
sameId [] (_ : _) = False
sameId (_ : _) [] = False
sameId (True : xs) (True : ys) = sameId xs ys
sameId (False : xs) (False : ys) = sameId xs ys
sameId _ _ = False

permitted :: Principal -> [Bool] -> Action -> Bool
permitted Anonymous target action = False
permitted (Member source Reader) target Read = sameId source target
permitted (Member source Reader) target Write = False
permitted (Member source Writer) target action
  = sameId source target

guarded :: Principal -> Action -> Scoped a -> Maybe a
guarded principal action (Resource tenant value)
  = if permitted principal tenant action then Just value else Nothing
