module Account (
    Name, Code,
    Lot,
    TimeSpent,
    DaysOfWeek,
    Account,
    createAccount,
    CreditAccount,
    DebitAccount,
    JournalType(..),
    Journal, createJournal,validJournal,
    DisplayView,
    Move,
    MoveLine,
    MoveState,
    MoveLineState,
    Sign(..),
    Tax, createTax, validAccount,
    TaxCode, createTaxCode,
    TaxType(..),
    TaxAmount(..),
    Quantity,
    Amount,
    AccountKind(..),
    AccountType(..),
    AccountError(..),
    Batch, createBatch
)where
import Control.Monad.State
import Control.Monad.Reader
import Control.Exception
import qualified Control.Applicative as C
import qualified Data.Acid as A
import Data.Acid.Remote
import Data.SafeCopy
import Data.Typeable
import Data.Data
import qualified Data.Set as S
import qualified Data.Map as M
import qualified Data.Tree as Tr
import qualified Data.Aeson as J
import qualified Data.Text.Lazy.Encoding as E
import qualified Data.Text.Lazy as L
import Data.Time.Clock
import GHC.Generics
import ErpError
import qualified Currency as Cu
import Entity(EntityState)
import qualified FiscalYear as Fy
import qualified Company as Co
import qualified Data.Ratio as R
data InvalidAccountException = InvalidAccountException
    deriving (Show, Typeable, Generic, Data, Eq, Ord)
data AccountError = AccountError {msg :: String}
    deriving (Show, Typeable, Generic, Data, Eq, Ord)
type Name = String
type Code = String
type Boolean = Bool
type Lot = String
type TimeSpent = Float
data DaysOfWeek = Sunday | Monday | Tuesday | Wednesday | Thursday | Friday | Saturday
    deriving (Show, Enum, Bounded, Data, Typeable, Generic, Eq, Ord)
data AccountType = IncomeStatement | BalanceSheet | DisplayBalance
    deriving(Show, Enum, Bounded, Data, Typeable, Generic, Eq, Ord)
data AccountKind = Payable | Receivable | AkExpense | AkRevenue | View | Other
    deriving (Show, Enum, Bounded, Data,Typeable, Generic, Eq, Ord)
data Account = Account {
        name :: Name,
        code :: Code,
        aCompany :: Co.Company,
        currency :: Cu.Currency,
        acKind :: AccountKind,
        acType :: AccountType,
        deferral :: Boolean,
        altCurrency :: Cu.Currency,
        reconcile :: Boolean,
        note :: String}
        deriving(Show,Typeable, Data, Generic, Eq, Ord)
type DebitAccount = Account
type CreditAccount = Account
type DisplayView = String
debit :: Account -> Bool
debit anAccount =
    let accType = acKind anAccount in
    case accType of
        Payable -> True
        AkExpense -> True
        Receivable -> False
        AkRevenue -> False
        _ -> False
credit anAccount =
    let
        accType = acKind anAccount in
        case accType of
            Receivable -> True
            AkRevenue -> True
            _         -> False

createAccount :: Name -> Code -> Co.Company -> Cu.Currency -> AccountKind
            -> AccountType -> Boolean -> Cu.Currency
            -> Boolean -> String -> ErpError AccountError Account
createAccount aName aCode aCompany aCurrency aKind
    aType deferral altCurrency
    reconcile note =
        if altCurrency /= aCurrency then
            Success $ Account aName aCode aCompany aCurrency aKind aType deferral altCurrency reconcile note
        else
            Error $ AccountError "Invalid Account"
validAccount :: Account -> Bool
validAccount  = (\x -> currency x /= altCurrency x)

data JournalType = General | Revenue | Situation | Expense
        | Cash
        deriving (Show, Typeable, Generic, Eq, Ord)
data Journal = Journal {
    jName :: Name,
    jCode :: Code,
    jActive :: Boolean,
    view   :: DisplayView,
    updatePosted :: Boolean,
    -- A list of tax auto complete move with
    -- new moves lines corresponding to those taxes
    -- if the user create a line linked to the current account
    -- and if the journal type is Expense or Revenue
    -- The above requirement is a bit too complicated
    -- Note: Need to refactor the requirement to make
    -- it clearer.
    taxes :: Maybe (Tr.Tree Tax),
    journalType :: JournalType,
    defaultDebitAccount :: DebitAccount,
    defaultCreditAccount :: CreditAccount,
    moves :: S.Set Move}
    deriving (Show, Typeable, Generic, Eq, Ord)

instance Ord (Tr.Tree Tax) where
    compare  t y = compare (Tr.rootLabel t) (Tr.rootLabel y)
    (<=) t y = (Tr.rootLabel t) <= (Tr.rootLabel y)
createJournal :: Name -> Code -> Bool -> DisplayView -> Bool -> Maybe (Tr.Tree Tax) -> JournalType -> DebitAccount -> CreditAccount -> Journal
createJournal aName aCode active view updatePosted taxes jType defaultDebitAccount defaultCreditAccount =
    case jType of
        Expense -> jObject
        Revenue -> jObject
        _ ->
            Journal aName aCode active view updatePosted Nothing jType
                defaultDebitAccount defaultCreditAccount S.empty
        where
            jObject = Journal
                aName aCode active view updatePosted taxes jType
                defaultDebitAccount
                defaultCreditAccount S.empty
validJournal :: Journal -> Bool
validJournal aJournal =
    case journalType aJournal of
        Expense -> taxes aJournal /= Nothing
        Revenue -> taxes aJournal /= Nothing
        _       -> taxes aJournal == Nothing


type ReferenceNumber = String
data MoveState  = Draft | Posted
    deriving (Show, Typeable, Generic, Eq, Ord)
data Move = Move {
    mName :: Name,
    mReference :: String,
    period :: Fy.FiscalYearPeriod,
    journal :: Journal,
    effectiveDate :: UTCTime,
    postDate ::  UTCTime,
    mState :: MoveState,
    moveRefNumber :: ReferenceNumber,
    moveLines :: S.Set MoveLine}
    deriving (Show, Typeable, Generic, Eq, Ord)

post :: Move -> UTCTime -> ReferenceNumber -> Move
post aMove aDate aRef =
    if balancedMove aMove aDate then
        aMove {postDate = aDate, mState = Posted, moveRefNumber = aRef}
    else
        aMove
creditMoves :: Move -> UTCTime -> S.Set MoveLine
creditMoves aMove aDate =
    let
        lines = moveLines aMove
        datedLines = S.filter (\y -> moveLineEffectiveDate y <= aDate) lines
    in
        S.filter (\x -> credit $ account x) datedLines
debitMoves :: Move -> UTCTime -> S.Set MoveLine
debitMoves aMove aDate =
    let
        lines = moveLines aMove
        datedLines = S.filter (\y -> moveLineEffectiveDate y  <= aDate) lines
    in
        S.filter (\x -> debit $ account x) datedLines

balancedMove :: Move -> UTCTime -> Bool
balancedMove aMove postDate =
    let
        creds = creditMoves aMove postDate
        debits = debitMoves aMove postDate
        creditSum = S.foldr' (\m acc -> acc + (mlAmount m)) 0 creds
        debitSum = S.foldr' (\m acc -> acc + (mlAmount m)) 0 debits
    in
        debitSum - creditSum == 0
data MoveLineState = MlDraft | MlPosted | MlValid
    deriving (Show, Typeable, Generic, Eq, Ord, Enum, Bounded)
data MoveLine = MoveLine {
    mlName :: Name,
    mlReference :: String,
    mlAmount :: Amount,
    account :: Account,
    move :: Move,
    mlState :: MoveLineState,
    secondCurrency :: (Cu.Currency, Amount),
    moveLineEffectiveDate :: UTCTime,
    -- Maturity date is the limit date for the payment
    maturityDate :: UTCTime,
    reconciliation :: Maybe Integer,
    taxLines :: [Distribution]}
    deriving (Show, Typeable, Generic, Eq, Ord)

{-- XXX: This distribution is a list of amount lines on the account chart ??--}
{-- This is the list of amounts for all the auto-complete taxes for the account --}
type Distribution = [(Tax, Amount)]
data Sign = Positive | Negative
        deriving (Show, Typeable, Generic, Eq , Ord, Enum, Bounded)
type Amount = R.Ratio Integer
type Quantity = R.Ratio Integer
data TaxCode = TaxCode {
    tcName :: Name,
    tcCode :: Code,
    tcActive  :: Boolean,
    tcCompany :: Co.Company,
    sum :: Amount} deriving (Show, Typeable, Generic, Eq, Ord)
createTaxCode :: Name -> Code -> Boolean -> Co.Company -> Amount -> TaxCode
createTaxCode = TaxCode


addChild :: (Tr.Tree TaxCode) -> TaxCode -> TaxCode -> Tr.Tree TaxCode
addChild aTree child parent = undefined

type Sequence = String
data TaxType = PercentTaxType Float | FixedTaxType Float
    deriving (Show, Typeable, Generic, Eq, Ord)
{--
Refactoring note: credit note account
and invoice account repeat fields.
--}
type AccountCode = (ErpError AccountError Account, Sign)
data Tax = Tax {
 tName :: Name,
 tCode :: Code,
 description :: String,
 tActive :: Boolean,
 sequence ::Sequence,
 taxType :: TaxType,
 taxCompany :: Co.Company,
 invoiceAccount :: Account,
 creditNoteAccount :: Account,
 invoiceBaseCode :: AccountCode,
 invoiceTaxCode :: AccountCode,
 creditNoteBaseCode :: AccountCode,
 creditNoteTaxCode :: AccountCode
 } deriving(Show, Typeable, Generic, Eq, Ord)

createTax :: Name -> Code -> String -> Boolean -> Sequence -> TaxType -> Co.Company
            -> ErpError AccountError Account
            -> ErpError AccountError Account
            -> AccountCode
            -> AccountCode
            -> AccountCode
            -> AccountCode -> ErpError AccountError Tax
createTax n c s b se tt co acc1 acc2 a1 a2 a3 a4 =
    case (acc1, acc2) of
    (Success a11, Success a21) -> Success $ Tax n c s b se tt co a11 a21 a1 a2 a3 a4
    _               -> Error $ AccountError "Invalid accounts"


validTax :: Tax -> Bool
validTax aTax = validTaxType (taxType aTax)
           && (invoiceAccount aTax /= creditNoteAccount aTax)



validTaxType :: TaxType -> Bool
validTaxType = \taxType ->
    case taxType of
        PercentTaxType anAmount -> anAmount > 0.0 && anAmount < 100.00
        FixedTaxType anAmount -> True


type TaxTree = Tr.Tree Tax

{--
What does a fixed tax amount mean: Would it be possible for
a fixed tax amount to ever be greater than the amount the
tax is being applied on?
This tax is sort of regressive.
--}
data TaxAmount = Fixed (R.Ratio Integer) | Percentage (R.Ratio Integer)
        | BasisPoints (R.Ratio Integer)
    deriving(Show, Typeable, Generic, Eq, Ord)

computeTaxAmount:: Amount -> TaxAmount -> Amount
computeTaxAmount a t =
    case t of
    Fixed aNumber -> a + aNumber
    Percentage pct -> a *  (1 + pct/100)
    BasisPoints bps -> a * (1 + bps/ 10000)

data Procedure = Procedure String deriving (Show, Typeable, Generic, Eq, Ord)
type Day = Int
data Level = Level Day deriving (Show, Typeable, Generic, Eq, Ord)
data DunningState = DDraft | DDone deriving (Show, Typeable, Generic, Eq, Ord, Enum, Bounded)
type BatchID = String
data Batch = Batch {
                batchDate :: UTCTime,
                batchID :: BatchID }
                deriving (Show, Typeable, Generic, Eq, Ord)

createBatch :: UTCTime -> BatchID -> Batch
createBatch = Batch

createNewBatch anId = do
    c <- getCurrentTime
    return $ createBatch c anId

data Dunning = Dunning {
        line :: MoveLine,
        procedure :: Procedure,
        level :: Level,
        -- If true, the dunning is blocked..
        blocked :: Bool,
        dunningState :: DunningState
        } deriving (Show, Typeable, Generic, Eq, Ord)

printDunningLetter :: Dunning -> L.Text
printDunningLetter = L.pack . show

getAccountTypes = map(\x -> (L.pack (show x),x)) ([minBound..maxBound]::[AccountType])
{--
computing inventory costs by FIFO method,
apparently LIFO is a US tax haven.
The FIFO works as follows:
Date No. Units Price
d1 100          1
d2 200          10
d3 300          11

Number of units sold:
d4 20
d5 140
d6 100

cost of d4 is 20 * 1
cost d5 is (80 * 1 + 60 * 10)
cost d6 is (100 * 10)
inventory cost between a period needs to adjust the journal accordingly

The above algorithm is a general information, to keep the audits simple,
purchases and sales are part of a batch and the inventory
is the difference between sales for a batch and purchases for the same
batch.
--}



instance J.ToJSON Dunning
instance J.FromJSON Dunning
instance J.ToJSON DunningState
instance J.FromJSON DunningState
instance J.ToJSON Procedure
instance J.FromJSON Procedure
instance J.ToJSON Level
instance J.FromJSON Level
instance J.ToJSON JournalType
instance J.FromJSON JournalType
instance J.ToJSON Journal
instance J.FromJSON Journal
instance J.ToJSON Account
instance J.FromJSON Account
instance J.ToJSON Tax
instance J.FromJSON Tax
instance J.ToJSON AccountType
instance J.FromJSON AccountType
instance J.ToJSON AccountKind
instance J.FromJSON AccountKind
instance J.ToJSON Move
instance J.FromJSON Move
instance J.ToJSON MoveState
instance J.FromJSON MoveState
instance J.ToJSON MoveLine
instance J.FromJSON MoveLine
instance J.ToJSON MoveLineState
instance J.FromJSON MoveLineState
instance J.ToJSON Sign
instance J.FromJSON Sign
instance J.ToJSON TaxCode
instance J.FromJSON TaxCode
instance J.ToJSON TaxAmount
instance J.FromJSON TaxAmount
instance J.ToJSON TaxType
instance J.FromJSON TaxType
instance J.ToJSON Batch
instance J.FromJSON Batch
instance J.ToJSON AccountError
instance J.FromJSON AccountError
$(deriveSafeCopy 0 'base ''Dunning)
$(deriveSafeCopy 0 'base ''DunningState)
$(deriveSafeCopy 0 'base ''Procedure)
$(deriveSafeCopy 0 'base ''Level)
$(deriveSafeCopy 0 'base ''JournalType)
$(deriveSafeCopy 0 'base ''Journal)
$(deriveSafeCopy 0 'base ''Account)
$(deriveSafeCopy 0 'base ''Tax)
$(deriveSafeCopy 0 'base ''AccountType)
$(deriveSafeCopy 0 'base ''AccountKind)
$(deriveSafeCopy 0 'base ''Sign)
$(deriveSafeCopy 0 'base ''TaxCode)
$(deriveSafeCopy 0 'base ''TaxAmount)
$(deriveSafeCopy 0 'base ''TaxType)

$(deriveSafeCopy 0 'base ''Move)
$(deriveSafeCopy 0 'base ''MoveState)
$(deriveSafeCopy 0 'base ''MoveLine)
$(deriveSafeCopy 0 'base ''MoveLineState)
$(deriveSafeCopy 0 'base ''Batch)
$(deriveSafeCopy 0 'base ''AccountError)






