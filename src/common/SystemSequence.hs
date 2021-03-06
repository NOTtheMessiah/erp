{-- 
A place to manage sequence numbers for the system.
The protocol is to manage sequence numbers from clients and
each client will have a sequence number for the corresponding
model.
--}

module SystemSequence(ID, nextID, errorID)
where

import Data.SafeCopy
import Data.Typeable
import qualified Data.Map as M
import qualified Data.Tree as Tr
import qualified Data.Aeson as J
import qualified Data.Text.Lazy.Encoding as E
import qualified Data.Text.Lazy as L
import Data.Time.Clock
import Data.Data
import GHC.Generics
import qualified Login as Lo


type ID = Integer

-- Simple integer should suffice for now.
nextID :: ID -> ID
nextID  x =  x + 1

-- Any message with this id is an error id.
errorID :: ID
errorID = -1

