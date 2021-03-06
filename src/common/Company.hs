module Company (createCompany, validCurrencies,
    Company
    , createCompanyNM
    , Employee
    , Category(..),
    SupplierReference,
    InternalReference,
    CompanyNotFound(..),
    findCompany,
    DuplicateCompaniesFound,
    Percent,
    Day,
    PaymentTerm,
    CompanyReport,
    Degrees, Minutes, Seconds,
    LatDirection(..),
    LongDirection(..),
    Latitude, createLatitude, createLatitudeNM,
    Longitude, createLongitude, createLongitudeNM,
    Coordinate, createCoordinate, createCoordinateNM, 
    GeoLocation, createGeoLocation, createGeoLocationNM,
    VCard,
    Address,
    Party
    , createParty
    , createPartyNM
    , validContacts
    , validCategories
    ,findParty,
    PartyNotFound,
    Contact(..),
    ContactType(..),
    CompanyWorkTime
    , createCompanyWorkTime
    , createCompanyWorkTimeNM 
    , validHours,
    invalidHoursPerDay, invalidDaysPerWeek, invalidWeeksPerMonth, invalidMonthsPerYear
    ) where
import Control.Monad.State
import Control.Monad.Reader
import Control.Exception
import Control.Applicative    
import qualified Data.Acid as A
import Data.Acid.Remote
import Data.SafeCopy
import Data.Typeable
import Data.Data
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
import qualified Data.Set as S
import ErpError


type SupplierReference = String
type InternalReference = String
data CompanyNotFound = CompanyNotFound deriving (Show, Generic, Data, Typeable, Eq, Ord)
data PartyNotFound = PartyNotFound
    deriving (Show, Generic, Data, Typeable, Eq, Ord)
data DuplicateCompaniesFound = DuplicateCompaniesFound deriving
    (Show, Generic, Data, Typeable, Eq, Ord)
data DuplicatePartiesFound = DuplicatePartiesFound deriving
    (Show, Generic, Data, Typeable, Eq, Ord)
instance Exception CompanyNotFound
instance Exception PartyNotFound
instance Exception DuplicateCompaniesFound
instance Exception DuplicatePartiesFound

type Percent = Float
data Day = CalendarDays Int | BusinessDays Int
    deriving(Show, Data, Typeable, Generic, Eq, Ord)
data PaymentTerm = NetDays (Day, Percent)
    deriving (Show, Data, Typeable, Generic, Eq, Ord)

data Category = Category {category :: String}
    deriving(Show, Data, Typeable, Generic, Eq, Ord)
data Header = Header String
     deriving(Show, Data, Typeable, Generic)
data Footer = Footer String
    deriving(Show, Typeable, Data, Generic)


data Company = Company {party :: Party,
                        currency :: Cu.Currency,
                        alternateCurrencies :: S.Set Cu.Currency,
                        productSet :: S.Set Pr.Product,
                        -- The current sequence number for
                        -- the product batch.
                        productBatchId :: M.Map String Integer}
                        deriving (Show, Data, Typeable,Generic, Ord)
instance Eq Company where
    a == b = party a == party b

createCompany :: Party -> Cu.Currency ->
    S.Set Cu.Currency -> S.Set Pr.Product
    -> ErpM Company
createCompany aParty aCurrency alternateCurrencies products =
    pure $ createCompanyNM aParty aCurrency alternateCurrencies products

createCompanyNM aParty aCurrency alternateCurrencies products =
    Company aParty aCurrency alternateCurrencies products M.empty

setPrimaryCurrency aCurrency aCompany =
        if currencyExists aCurrency aCompany then
            aCompany
        else
            aCompany {currency = aCurrency}

addAlternateCurrencies :: Cu.Currency -> Company -> Company
addAlternateCurrencies aCurrency aCompany =
    if aCurrency == currency aCompany then
        aCompany
    else
        aCompany {alternateCurrencies = S.insert aCurrency (alternateCurrencies aCompany)}

removeAlternateCurrency aCurrency aCompany = 
        aCompany {alternateCurrencies = S.filter ( /= aCurrency) (alternateCurrencies aCompany) }

currencyExists :: Cu.Currency -> Company -> Bool
currencyExists aCurrency aCompany = (aCurrency == currency aCompany)
                        || (S.member aCurrency $ alternateCurrencies aCompany)

validCurrencies aCom = S.notMember (currency aCom)
             (alternateCurrencies aCom)

addProduct :: Company -> Pr.Product -> Company
addProduct aCompany aProduct = aCompany {productSet = S.insert aProduct (productSet aCompany)}

resetCounter aCompany aProduct  =
    aCompany {productBatchId = M.insert (show aProduct) 0 (productBatchId aCompany)}
incrementCounter aCompany aProduct = M.adjust ( + 1) (show aProduct) (productBatchId aCompany)


data CompanyReport = CompanyReport {fiscalYear :: Fy.FiscalYear,
                                    company :: Company,
                                    header :: Header,
                                    footer :: Footer,
                                    publishDate :: UTCTime}
                        deriving (Show, Data, Typeable,Generic)

type URI = String


findCompany :: Party -> S.Set Company -> ErpError [ModuleError] Company
findCompany aParty aCompanySet =
    let
        result = S.filter (\x -> party x == aParty) aCompanySet
    in
        if S.null result then
            erpErrorNM "Company" "C0002" "Company Not found"
        else
            case elems result of
                [h] -> createSuccess h
                -- This should never happen? 
                -- What does it mean, when this happens?
                h:t -> erpErrorNM "Company" "C0003" 
                    (L.pack("Duplicate companies " ++ (show h) ++ " and " ++ (show t)))
             where
                elems aSet = S.elems aSet


type Degrees = Integer
type Minutes = Integer
type Seconds = Integer
data LatDirection = North | South deriving (Show, Data, Typeable, Generic, Eq, Ord)
data LongDirection = East | West deriving (Show, Data, Typeable, Generic, Eq, Ord)
data CoordinateUnit = CoordinateUnit {degrees :: Degrees,
                        minutes :: Minutes,
                        seconds :: Seconds}
                    deriving (Show, Data, Typeable, Generic, Eq, Ord)

data Latitude = Latitude { lat :: CoordinateUnit,
                           latDirection :: LatDirection}
                deriving (Show, Typeable, Data, Generic, Eq, Ord)

invalid :: Degrees -> Bool
invalid a = a < 0 || a > 60



createLatitudeNM :: Degrees -> Minutes -> Seconds -> LatDirection -> Latitude
createLatitudeNM d m s dir = Latitude (CoordinateUnit d m s) dir

createLatitude :: Degrees -> Minutes -> Seconds -> LatDirection -> ErpM Latitude
createLatitude d m s dir = pure $ createLatitudeNM d m s dir


data Longitude = Longitude { longitude :: CoordinateUnit,
                            longDirection :: LongDirection}
    deriving (Show, Data, Typeable, Generic, Eq, Ord)

createLongitudeNM :: Degrees -> Minutes -> Seconds -> LongDirection -> Longitude
createLongitudeNM d m s dir = Longitude (CoordinateUnit d m s) dir

createLongitude :: Degrees -> Minutes -> Seconds -> LongDirection ->
       ErpM Longitude
createLongitude d m s dir = pure $ createLongitudeNM d m s dir
data Coordinate = Coordinate { x :: Latitude, y :: Longitude}
    deriving (Show, Typeable, Data, Generic, Eq, Ord)
createCoordinate :: Latitude ->
                    Longitude ->
                    ErpM Coordinate
createCoordinate la lo = pure $ createCoordinateNM la lo


createCoordinateNM :: Latitude -> Longitude -> Coordinate
createCoordinateNM la lo = Coordinate la lo
data GeoLocation = GeoLocation{ uri :: URI,
                                position :: Coordinate}
                        deriving (Show, Data, Typeable, Generic, Eq, Ord)
createGeoLocation :: URI -> Coordinate -> ErpM GeoLocation
createGeoLocation a b = pure $ createGeoLocationNM a b 

createGeoLocationNM :: URI -> Coordinate -> GeoLocation
createGeoLocationNM a b = GeoLocation a b

type VCard = String
type Address = String

data Party = Party {name :: String,
                    address :: Address,
                    maplocation :: GeoLocation,
                    poc        :: Contact,
                    primaryCategory :: Category,
                    vcard :: VCard,
                    alternateCategories :: S.Set Category,
                    alternatePocs :: S.Set Contact
                    }
                    deriving (Show, Data, Typeable,Generic, Eq, Ord)
type Name = String


-- A query data type that the client uses to query a party 

data QueryParty = QueryParty {
    qName :: String,
    qMapLocation :: GeoLocation
} deriving (Show, Data, Typeable, Generic, Eq, Ord)

{-- |
    Create a party or return an error.
--}



createParty :: Name -> Address -> GeoLocation -> Contact -> Category
                    -> VCard -> S.Set Category -> S.Set Contact ->
                    ErpM Party
createParty name address loc contact cat vc categories contacts = pure $ 
        createPartyNM name address loc contact cat vc categories contacts
createPartyNM :: Name -> Address -> GeoLocation -> Contact -> Category
        -> VCard -> S.Set Category -> S.Set Contact -> Party
createPartyNM  = Party


findParty :: (Name, GeoLocation) -> S.Set Party -> ErpError [ModuleError] Party
findParty a@(aName,aLocation) aSet =
     let
        result = S.filter (\x -> name x == aName && maplocation x == aLocation) aSet
     in
        if S.null result then
            erpErrorNM "Company" "C002" $ L.pack $ "Party not found " ++ show a
        else
            case elems result of
                h:[] -> createSuccess h
                h:t -> erpErrorNM "Company" "C0003" $ L.pack $ "Duplicate parties found " ++ show h ++ "->" ++ show t
            where
                elems aSet = S.elems aSet



{-- |

For example, if the main category is say Vendor,
but the vendor is also a potential customer for the current product because
of the employees of the vendor, then the alternate category
could be "Potential Customer". Other classification could be its
SIC classification: target industry, sub industry etc.
Alternate categories are probably better represented as minor categories
in this context.

--}
addAlternateCategories :: Category -> Party -> Party
addAlternateCategories aCategory aParty =
    if categoryExists aParty aCategory then
        aParty
    else
        aParty {alternateCategories = S.insert aCategory (alternateCategories aParty)}

{--|
    This is the primary category
--}
setPrimaryCategory :: Party -> Category -> Party
setPrimaryCategory aParty aCat =
    if categoryExists aParty aCat then
        aParty
    else
        aParty {primaryCategory = aCat}

categoryExists :: Party -> Category -> Bool
categoryExists aParty aCat =
    (aCat == primaryCategory aParty)
    || (S.member aCat(alternateCategories aParty))

addAlternatePocs :: Contact -> Party -> Party
addAlternatePocs aContact aParty =
    if contactExists aParty aContact then
        aParty
    else
        aParty {alternatePocs = S.insert aContact (alternatePocs aParty)}

setPOC:: Party -> Contact -> Party
setPOC aParty aContact =
    if contactExists aParty aContact then
        aParty
    else
        aParty {poc = aContact}
contactExists :: Party -> Contact -> Bool
contactExists aParty aContact =
    (aContact == (poc aParty))
    || (S.member aContact (alternatePocs aParty))

validContacts :: Party -> Bool
validContacts aParty = S.notMember (poc aParty) (alternatePocs aParty)
validCategories :: Party -> Bool
validCategories aParty = S.notMember (primaryCategory aParty) (alternateCategories aParty)

data ContactType = Phone | Mobile | Fax | Email | Website |
                    Skype |
                    SIP |
                    IRC |
                    Jabber
                    deriving (Enum, Bounded, Show, Typeable,Data, Generic, Eq, Ord)


data Contact = Contact {contactType :: ContactType,
                        value :: String}
                    deriving(Show, Data, Typeable,Generic, Eq, Ord)
data Employee = Employee {employeeDetails :: Party, employeeCompany :: Company}
                    deriving (Show, Typeable, Generic, Eq, Data, Ord)
data User = User {mainCompany :: Company,
                  userCompany :: Company,
                  userEmployee :: Employee}
                  deriving (Show, Typeable, Generic, Eq, Ord, Data)

type HoursPerDay = Int
type DaysPerWeek = Int
type WeeksPerMonth = Int
type MonthsPerYear = Int


data CompanyWorkTime = CompanyWorkTime {
            workTime:: Company,
            hoursPerDay :: HoursPerDay,
            daysPerWeek :: DaysPerWeek,
            weeksPerMonth :: WeeksPerMonth,
            monthsPerYear :: MonthsPerYear}
                deriving (Show, Typeable, Generic, Eq, Ord)


data InvalidWorkTime = InvalidWorkTime {h :: HoursPerDay, d :: DaysPerWeek, w :: WeeksPerMonth, m :: MonthsPerYear}
        deriving (Show, Typeable, Generic, Eq, Ord)
instance Exception InvalidWorkTime

createCompanyWorkTime :: ErpM Company
    -> HoursPerDay -> (HoursPerDay, HoursPerDay)
    ->DaysPerWeek -> (DaysPerWeek, DaysPerWeek)
    -> WeeksPerMonth -> (WeeksPerMonth, WeeksPerMonth)
    -> MonthsPerYear -> (MonthsPerYear, MonthsPerYear)
    -> ErpM CompanyWorkTime
createCompanyWorkTime aCompany hpd (minHpd, maxHpd) 
    dpw (minDpw, maxDpw) wpm (minWpm, maxWpm) 
    mpy (minMpy, maxMpy) = 
    CompanyWorkTime <$> aCompany
        <*> chkHpd  
        <*> pure dpw 
        <*> pure wpm 
        <*> pure mpy 
    where
        chkHpd = if hpd >= minHpd && hpd < maxHpd 
                    then pure hpd 
                    else 
                        erpError "Company" "COWT001" "Cant work too less or too much!" 



createCompanyWorkTimeNM ::Company 
    -> HoursPerDay -> (HoursPerDay, HoursPerDay)
    -> DaysPerWeek -> (DaysPerWeek, DaysPerWeek)
    -> WeeksPerMonth -> (WeeksPerMonth, WeeksPerMonth)
    -> MonthsPerYear -> (MonthsPerYear, MonthsPerYear) 
    -> CompanyWorkTime
createCompanyWorkTimeNM aCompany hpd (minHpd, maxHpd)
    dpw (minDpw, maxDpw)
    wpm (minWpm, maxWpm)
    mpy (minMpy, maxMpy) = 
        CompanyWorkTime aCompany hpd dpw wpm mpy

invalidHoursPerDay :: Int -> (Int, Int) -> Bool
invalidHoursPerDay aNumber (min, max) = aNumber < min || aNumber > max

invalidDaysPerWeek :: Int -> (Int, Int) -> Bool
invalidDaysPerWeek aNumber (min, max) = aNumber < min || aNumber > max

invalidWeeksPerMonth :: Int -> (Int, Int) -> Bool
invalidWeeksPerMonth aNumber (min, max) = aNumber < min || aNumber > max

invalidMonthsPerYear :: Int -> (Int, Int) -> Bool
invalidMonthsPerYear aNumber (min, max) =
        aNumber < min || aNumber > max

type Hours = Int
totalDays :: CompanyWorkTime -> Hours
totalDays aCompanyWorkTime = (hoursPerDay aCompanyWorkTime) * (daysPerWeek aCompanyWorkTime) *(weeksPerMonth  aCompanyWorkTime) * (monthsPerYear  aCompanyWorkTime)

validHours :: CompanyWorkTime -> Hours -> Bool
validHours aCompanyWorkTime maxHours =  (totalDays aCompanyWorkTime) < maxHours


getContactTypes = map(\x -> (L.pack $ show x,x)) 
    ([minBound..maxBound]::[ContactType])




instance J.ToJSON GeoLocation
instance J.FromJSON GeoLocation
instance J.ToJSON Latitude
instance J.FromJSON Latitude
instance J.FromJSON Longitude
instance J.ToJSON Longitude
instance J.ToJSON LatDirection
instance J.FromJSON LatDirection
instance J.ToJSON LongDirection
instance J.FromJSON LongDirection
instance J.ToJSON Coordinate
instance J.FromJSON Coordinate
instance J.ToJSON CoordinateUnit
instance J.FromJSON CoordinateUnit
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
instance J.ToJSON QueryParty
instance J.FromJSON QueryParty


$(deriveSafeCopy 0 'base ''Category)
$(deriveSafeCopy 0 'base ''Company)
$(deriveSafeCopy 0 'base ''Contact)
$(deriveSafeCopy 0 'base ''ContactType)
$(deriveSafeCopy 0 'base ''Party)
$(deriveSafeCopy 0 'base ''GeoLocation)
$(deriveSafeCopy 0 'base ''CompanyWorkTime)
$(deriveSafeCopy 0 'base ''Latitude)
$(deriveSafeCopy 0 'base ''Longitude)
$(deriveSafeCopy 0 'base ''LongDirection)
$(deriveSafeCopy 0 'base ''LatDirection)
$(deriveSafeCopy 0 'base ''CoordinateUnit)
$(deriveSafeCopy 0 'base ''Employee)
$(deriveSafeCopy 0 'base ''Header)
$(deriveSafeCopy 0 'base ''Footer)
$(deriveSafeCopy 0 'base ''CompanyReport)
$(deriveSafeCopy 0 'base ''Coordinate)
$(deriveSafeCopy 0 'base ''PaymentTerm)
$(deriveSafeCopy 0 'base ''Day)
$(deriveSafeCopy 0 'base ''QueryParty)

