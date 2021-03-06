module Production where
import Control.Monad.State
import Control.Monad.Reader
import qualified Control.Applicative as C
import qualified Data.Acid as A
import Data.Acid.Remote
import Data.SafeCopy
import Data.Typeable
import qualified Data.Map as M
import qualified Data.Tree as Tr
import qualified Data.Aeson as J
import qualified Data.Text.Lazy.Encoding as E
import qualified Data.Text.Lazy as L
import Data.Time.Clock
import GHC.Generics
import qualified Currency as Cu
import Entity(EntityState)
import qualified FiscalYear as Fy
import qualified Company as Co
import qualified Product as Pr
import qualified Stock as St
data Production = 
    Production{ product :: Pr.Product,
                inputs :: [St.Move],
                outputs :: [St.Move],
                productionState :: ProductionState}
    deriving(Show, Typeable, Generic, Eq, Ord)

data ProductionState = Request | Draft | Waiting | Assigned | Running | Done | Cancel
    deriving (Show, Enum, Bounded, Typeable, Generic, Eq, Ord)

data StockProductionRequest = StockProductionRequest {
    sprProduct :: Pr.Product,
    productionRequest :: Production,
    requestDate :: UTCTime
    } deriving (Show, Eq, Ord, Typeable, Generic)

$(deriveSafeCopy 0 'base ''Production)
$(deriveSafeCopy 0 'base ''ProductionState)
$(deriveSafeCopy 0 'base ''StockProductionRequest)
instance J.ToJSON Production
instance J.FromJSON Production
instance J.ToJSON ProductionState
instance J.FromJSON ProductionState
instance J.ToJSON StockProductionRequest
instance J.FromJSON StockProductionRequest
    