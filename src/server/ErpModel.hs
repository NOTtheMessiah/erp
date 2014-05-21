module ErpModel where
import System.Log.Logger
import Data.Maybe
import Control.Monad.State
import Control.Monad.Reader
import Control.Exception

import qualified Control.Applicative as C
import qualified Data.Acid as A
import Data.Acid.Remote
import Data.SafeCopy
import Data.Typeable
import qualified Data.Map as M
import qualified Data.Set as S
import qualified Data.Aeson as J
import qualified Data.Text.Lazy.Encoding as E
import qualified Data.Text as T
import qualified Data.Text.Lazy as L
import qualified Data.Text.IO as TIO
import qualified Network.WebSockets.Connection as WS
import Data.Dynamic
import Data.Time.Clock
import GHC.Generics
import qualified Login as Lo
import qualified Company as Co
import qualified Product as Pr
import qualified Production as Prod
import qualified Project as Proj
import qualified Stock as St
import qualified Shipment as Sh
import qualified Purchase as Pu
import qualified Sale as Sa
import qualified Forecast as Fo
import qualified Timesheet as Ts
data LoginExists = LoginExists deriving (Show, Generic, Typeable, Eq, Ord)
data LoginStaleException = LoginStaleException deriving (Show, Generic, Typeable, Eq, Ord)
data CategoryExists = CategoryExists deriving (Show, Generic, Typeable, Eq, Ord)
data LoginNotFound = LoginNotFound deriving (Show, Generic, Typeable, Eq, Ord)
instance Exception CategoryExists
instance Exception LoginExists
instance Exception LoginStaleException
instance Exception LoginNotFound

loginConstant = "Login"
categoryConstant = "Category"
queryDatabaseConstant = "QueryDatabase"
closeConnection = "CloseConnection"
type Deleted = Bool
data ErpModel = ErpModel
                {
                    login :: Lo.Login,
                    partySet :: S.Set Co.Party,
                    companySet :: S.Set Co.Company,
                    categorySet :: S.Set Co.Category,
                    deleted :: Deleted
                } deriving (Show, Generic, Typeable, Eq, Ord)

delete anErpModel = anErpModel {deleted = True}
{-- A given email id can be tied to only a single erp model,
 though a given model can be associated with multiple email ids--}
data Database = Database ! (M.Map String ErpModel)
     deriving (Show, Generic, Typeable, Eq, Ord)
data RequestType = Create | Modify | Retrieve | Delete deriving (Show, Generic, Typeable, Eq, Ord)
type RequestEntity = String
data Request = Request {
                        requestEntity :: RequestEntity,
                        emailId :: String,
                        payload :: L.Text} deriving(Show, Generic, Typeable, Eq, Ord)
data InvalidRequest = InvalidRequest deriving (Show, Generic, Typeable, Eq, Ord)
data InvalidLogin = InvalidLogin deriving (Show, Generic, Typeable, Eq, Ord)
data InvalidCategory = InvalidCategory deriving (Show, Generic, Typeable, Eq, Ord)

instance J.ToJSON ErpModel
instance J.FromJSON ErpModel


$(deriveSafeCopy 0 'base ''Database)
$(deriveSafeCopy 0 'base ''ErpModel)

emptyModel = ErpModel{partySet = S.empty,
              categorySet = S.empty,
              companySet = S.empty,
              login = Lo.empty,
              deleted = False
              }
updateModel aModel aCategory = aModel{ categorySet = S.insert aCategory (categorySet aModel)}

lookupParty :: String -> String -> Co.GeoLocation -> A.Query Database (Maybe Co.Party)
lookupParty aLogin aName aLocation  =
    do
        Database db <- ask
        let erp = M.lookup aLogin db
        case erp of
            Nothing -> throw Co.CompanyNotFound
            Just x -> return $ Co.findParty (aName, aLocation) (partySet x)

lookupCompany :: String -> Co.Party -> A.Query Database (Maybe Co.Company)
lookupCompany aLogin aParty =
    do
        Database db <- ask
        let erp = M.lookup aLogin db
        case erp of
            Nothing -> throw Co.CompanyNotFound
            Just x -> return $ Co.findCompany aParty (companySet x)

insertLogin :: String -> Lo.Login -> A.Update Database ()
insertLogin aString aLogin =
    do
        Database db <- get
        let loginErp = emptyModel {login = aLogin}
        put (Database (M.insert aString loginErp db))

deleteLoginI :: String -> A.Update Database ()
deleteLoginI aString  =
    do
        Database db <- get
        let loginErp = M.lookup aString db
        case loginErp of
            Nothing -> throw LoginNotFound
            Just x -> put (Database (M.insert aString (delete x) db))



lookupLogin :: String -> A.Query  Database (Maybe Lo.Login)
lookupLogin aLogin =
    do
        Database db <- ask
        let erp = M.lookup aLogin db
        case erp of
            Just erp -> return $ Just $ login erp
            _   -> return Nothing


lookupCategory :: String -> Co.Category -> A.Query  Database(Maybe Co.Category)
-- qbe -> query by example
lookupCategory aLogin qbe =
    do
       Database db <- ask
       let erp = M.lookup aLogin db
       return (if exists erp then Just qbe else Nothing)
       where
        exists erp =
            case erp of
            Just e -> S.member qbe (categorySet e)
            _      -> False

insertCategory :: String -> Co.Category -> A.Update Database ()
insertCategory aLogin c@(Co.Category aCatName) =
    do
        Database db <- get
        let erp = M.lookup aLogin db
        case erp of
            Just exists -> put(Database (M.insert aLogin (updateModel exists c) db))
            _       -> return()

getDatabase :: String -> A.Query Database (Maybe ErpModel)
getDatabase userEmail = do
        Database db <- ask
        let loginErp = M.lookup userEmail db
        return loginErp

$(A.makeAcidic ''Database ['lookupLogin, 'insertLogin, 'deleteLoginI, 'lookupCategory, 'insertCategory
            , 'getDatabase])

instance Exception InvalidCategory
instance Exception InvalidLogin
instance Exception InvalidRequest
instance J.ToJSON InvalidLogin
instance J.FromJSON InvalidLogin
instance J.ToJSON RequestType
instance J.FromJSON RequestType
instance J.ToJSON Request
instance J.FromJSON Request

initializeDatabase  dbLocation = A.openLocalStateFrom dbLocation $ Database M.empty
disconnect = A.closeAcidState

pJSON = J.decode . E.encodeUtf8 . L.fromStrict
updateDatabase connection acid aMessage =
    let
        r = J.decode $ E.encodeUtf8 $ L.fromStrict aMessage
    in
        case r of
        Just aRequest -> processRequest connection acid aRequest
        _ -> throw InvalidRequest


processRequest connection acid r@(Request entity emailId payload)  =
    case entity of
    "Login" -> updateLogin acid $ L.toStrict payload
    "DeleteLogin" -> deleteLogin acid emailId
    "Category" -> updateCategory acid emailId $ L.toStrict payload
    "QueryDatabase" -> do
            model <- queryDatabase acid emailId $ L.toStrict payload
            TIO.putStrLn $ T.pack $ show model
    "CloseConnection" -> do
                TIO.putStrLn (T.pack "Closing connection for " `T.append` (T.pack emailId))
                WS.sendTextData connection $ J.encode r
    _ -> throw InvalidRequest


deleteLogin acid anEmailId = A.update acid (DeleteLoginI anEmailId)

--Authentication is probably done using an oauth provider
--such as persona or google. This method simply logs
--in the user as valid.
updateLogin acid payload =
     let
        pObject = J.decode $ E.encodeUtf8 $ L.fromStrict payload
     in
        case pObject of
            Just l@(Lo.Login name email) -> do
                    loginLookup <- A.query acid (LookupLogin name)
                    case loginLookup of
                        Nothing -> A.update acid (InsertLogin name l)
                        Just l2@(Lo.Login name email) -> TIO.putStrLn "Exception?"
            Nothing -> throw InvalidLogin


updateCategory acid emailId payload =
    let
        pObject = pJSON payload
    in
        case pObject of
            Just c@(Co.Category aCat) -> do
                infoM "ErpModel" "Processing update category"
                lookup <- A.query acid (LookupCategory emailId c)
                case lookup of
                    Nothing -> A.update acid (InsertCategory emailId c)
                    Just c@(Co.Category aCat) -> throw CategoryExists
            Nothing -> throw InvalidCategory


displayText = T.pack . show

queryDatabase acid emailId payload = do
    lookup <- A.query acid (GetDatabase emailId)
    TIO.putStrLn(displayText lookup)
    return lookup

