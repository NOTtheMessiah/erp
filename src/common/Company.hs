module Company where
import Control.Monad.State
import Control.Monad.Reader
import Control.Exception
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
import FiscalYear as Fy
import qualified Currency as Cu
import qualified Login as Lo
import qualified Product as Pr
import qualified Data.Map as M
import qualified Data.Set as S
import qualified Data.Set as S

type SupplierReference = String
type InternalReference = String
data CompanyNotFound = CompanyNotFound deriving (Show, Generic, Typeable, Eq, Ord)
data DuplicateCompaniesFound = DuplicateCompaniesFound deriving (Show, Generic, Typeable, Eq, Ord)
instance Exception CompanyNotFound
instance Exception DuplicateCompaniesFound
type Percent = Float
data Day = CalendarDays Int | BusinessDays Int 
    deriving(Show, Typeable, Generic, Eq, Ord)
data PaymentTerm = Net_Days (Day, Percent)
    deriving (Show, Typeable, Generic, Eq, Ord)
    
data Category = Category {category :: String}
    deriving(Show, Typeable, Generic, Eq, Ord)
data Header = Header String
     deriving(Show, Typeable, Generic)
data Footer = Footer String
    deriving(Show, Typeable, Generic)

data Company = Company {party :: Party,
                        currency :: Cu.Currency,
                        alternateCurrencies :: S.Set Cu.Currency,
                        productSet :: S.Set Pr.Product}
                        deriving (Show, Typeable,Generic, Ord)
instance Eq Company where
    a == b = (party a == party b)

assignParty aParty aCompany = aCompany {party = aParty} 
assignCurrency aCurrency aCompany = 
        if currencyExists aCurrency aCompany then
            aCompany
        else
            aCompany {currency = aCurrency}
            
addAlternateCurrencies aCurrency aCompany = 
    if aCurrency == (currency aCompany) then
        aCompany
    else
        aCompany {alternateCurrencies = S.insert aCurrency (alternateCurrencies aCompany)}  
currencyExists :: Cu.Currency -> Company -> Bool        
currencyExists aCurrency aCompany = (aCurrency == (currency aCompany))
                        || (S.member aCurrency (alternateCurrencies aCompany))
addProduct :: Company -> Pr.Product -> Company
addProduct aCompany aProduct = aCompany {productSet = S.insert aProduct (productSet aCompany)}
removeAlternateCurrency aCurrency aCompany = aCompany {alternateCurrencies = S.filter (\x -> x /= aCurrency) (alternateCurrencies aCompany) }
data CompanyReport = CompanyReport {fiscalYear :: Fy.FiscalYear,
                                    company :: Company,
                                    header :: Header,
                                    footer :: Footer,
                                    publishDate :: UTCTime}
                        deriving (Show, Typeable,Generic)
                        
type URI = String
findCompany :: Party -> S.Set Company -> Maybe Company
findCompany aParty aCompanySet = 
    let 
        result = S.filter (\x -> party x == aParty) aCompanySet
    in
        if (S.null result) then
            Nothing
        else
            case (elems result) of
                h:[] -> Just h
                h:[t] -> throw DuplicateCompaniesFound
             where
                elems aSet = S.elems aSet
            

            
data Latitude = Latitude {xpos :: Float} 
    deriving (Show, Typeable, Generic, Eq, Ord)
data Longitude = Longitude {ypos :: Float}
    deriving (Show, Typeable, Generic, Eq, Ord)
data Coordinate = Coordinate { x :: Latitude, y :: Longitude} 
    deriving (Show, Typeable, Generic, Eq, Ord)
    
data GeoLocation = GeoLocation{ uri :: URI, 
                                position :: Coordinate}
                        deriving (Show, Typeable, Generic, Eq, Ord)
                        
type VCard = String  
type Address = String                      
data Party = Party {name :: String,
                    address :: Address,
                    maplocation :: GeoLocation,
                    poc        :: Contact,
                    primaryCategory :: Category,
                    vcard :: VCard, 
                    alternateCategories :: [Category],
                    alternatePocs :: [Contact]
                    }
                    deriving (Show, Typeable,Generic, Eq, Ord)


data ContactType = Phone | Mobile | Fax | Email | Website | 
                    Skype |
                    SIP |
                    IRC |
                    Jabber
                    deriving (Enum, Bounded, Show, Typeable,Generic, Eq, Ord)
                    
                    
data Contact = Contact {contactType :: ContactType, 
                        value :: String}
                    deriving(Show, Typeable,Generic, Eq, Ord)
data Employee = Employee {employeeDetails :: Party, employeeCompany :: Company}                    
                    deriving (Show, Typeable, Generic, Eq, Ord)
data User = User {mainCompany :: Company, 
                  userCompany :: Company,
                  userEmployee :: Employee}
                  deriving (Show, Typeable, Generic, Eq, Ord)
type HoursPerDay = Int
type HoursPerWeek = Int
type HoursPerMonth = Int
type HoursPerYear = Int                  
data CompanyWorkTime = CompanyWorkTime {
            workTime:: Company,
            hoursPerDay :: HoursPerDay,
            hoursPerWeek :: HoursPerWeek,
            hoursPerMonth :: HoursPerMonth,
            hoursPerYear :: HoursPerYear}
                deriving (Show, Typeable, Generic, Eq, Ord)
instance J.ToJSON GeoLocation
instance J.FromJSON GeoLocation
instance J.ToJSON Latitude
instance J.FromJSON Latitude
instance J.FromJSON Longitude
instance J.ToJSON Longitude

instance J.ToJSON Coordinate
instance J.FromJSON Coordinate                

instance J.ToJSON CompanyWorkTime
instance J.FromJSON CompanyWorkTime            
instance J.ToJSON User
instance J.FromJSON User                  
instance J.ToJSON Employee
instance J.FromJSON Employee                        
instance J.ToJSON Company
instance J.FromJSON Company
instance J.ToJSON Contact
instance J.FromJSON Contact
instance J.ToJSON ContactType
instance J.FromJSON ContactType
instance J.ToJSON Party
instance J.FromJSON Party
instance J.ToJSON Category
instance J.FromJSON Category
instance J.ToJSON Header
instance J.FromJSON Header
instance J.ToJSON Footer
instance J.FromJSON Footer
instance J.ToJSON CompanyReport
instance J.FromJSON CompanyReport
instance J.ToJSON PaymentTerm
instance J.FromJSON  PaymentTerm
instance J.ToJSON Day
instance J.FromJSON Day

$(deriveSafeCopy 0 'base ''Category)
$(deriveSafeCopy 0 'base ''Company)
$(deriveSafeCopy 0 'base ''Contact)
$(deriveSafeCopy 0 'base ''ContactType)
$(deriveSafeCopy 0 'base ''Party)
$(deriveSafeCopy 0 'base ''GeoLocation)
$(deriveSafeCopy 0 'base ''CompanyWorkTime)
$(deriveSafeCopy 0 'base ''Latitude)
$(deriveSafeCopy 0 'base ''Longitude)
$(deriveSafeCopy 0 'base ''Employee)
$(deriveSafeCopy 0 'base ''Header)
$(deriveSafeCopy 0 'base ''Footer)
$(deriveSafeCopy 0 'base ''CompanyReport)
$(deriveSafeCopy 0 'base ''Coordinate)
$(deriveSafeCopy 0 'base ''PaymentTerm)
$(deriveSafeCopy 0 'base ''Day)

getContactTypes = map(\x -> (L.pack (show x),x)) ([minBound..maxBound]::[ContactType])

                