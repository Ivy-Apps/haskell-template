{- | Judges a run against the Reference.

Comparisons are made on ratios rather than on absolute times. Cases can differ
in cost by orders of magnitude, so an arithmetic mean of their durations is in
practice the largest case's duration alone - a regression confined to a cheap
case would not move it. Each case's own new-over-old ratio, averaged
geometrically, gives every case equal say regardless of size.
-}
module Bench.Compare (
    Run (..),
    Row (..),
    rowName,
    rowMeasurement,
    rowShift,
    Shift (..),
    Outcome (..),
    Regression (..),
    Metric (..),
    Scope (..),
    Factor (..),
    Limits (..),
    Thresholds (..),
    limits,
    compareRun,
    asPercent,
) where

import Bench.Cases (CaseName)
import Bench.Measurement (Bytes (..), Measurement (..), Seconds (..))
import Bench.Reference (RecordedCase (..), Reference (..), ReferenceState (..), lookupCase)
import Data.List.NonEmpty qualified as NE
import GHC.Float (log)

-- | A measurement over its Reference counterpart. @1.0@ is unchanged.
newtype Factor = Factor Double
    deriving stock (Show, Eq)
    deriving newtype (Ord)

-- | How time and allocations moved. Used per case and for the geomean.
data Shift = Shift
    { time :: Factor
    , alloc :: Factor
    }
    deriving stock (Show, Eq)

{- | One measured case, and what the Reference holds for it if it holds anything.

Something the Reference has never seen cannot be judged, and must be kept out
of the geomean rather than silently folded in at a ratio of 1.
-}
data Row
    = -- | Measured now, and present in the Reference.
      Referenced CaseName Measurement Measurement
    | -- | Measured now, absent from the Reference.
      Unreferenced CaseName Measurement
    deriving stock (Show, Eq)

rowName :: Row -> CaseName
rowName (Referenced name _ _) = name
rowName (Unreferenced name _) = name

rowMeasurement :: Row -> Measurement
rowMeasurement (Referenced _ current _) = current
rowMeasurement (Unreferenced _ current) = current

rowShift :: Row -> Maybe Shift
rowShift (Referenced _ current reference) = Just $ shiftOf current reference
rowShift (Unreferenced _ _) = Nothing

data Run = Run
    { rows :: [Row]
    , aggregate :: Maybe Shift
    -- ^ Absent when no row had a Reference counterpart.
    , retired :: [RecordedCase]
    -- ^ Cases the Reference holds that this run did not measure.
    , outcome :: Outcome
    }
    deriving stock (Show, Eq)

data Outcome
    = -- | No Reference existed. There is nothing to judge.
      Ungated
    | Passed
    | Regressed (NonEmpty Regression)
    deriving stock (Show, Eq)

data Regression = Regression
    { metric :: Metric
    , scope :: Scope
    , observed :: Factor
    , limit :: Factor
    }
    deriving stock (Show, Eq)

data Metric = TimeMetric | AllocMetric
    deriving stock (Show, Eq)

data Scope
    = SuiteGeomean
    | SingleCase CaseName
    deriving stock (Show, Eq)

data Thresholds = Thresholds
    { geomean :: Factor
    , perCase :: Factor
    }
    deriving stock (Show, Eq)

data Limits = Limits
    { time :: Thresholds
    , alloc :: Thresholds
    }
    deriving stock (Show, Eq)

{- | What counts as a regression.

Time is allowed more room than allocations because it deserves less trust:
wall-clock measurement carries the machine's noise, whereas the same work
allocates the same bytes run after run. The pair also diagnoses rather than
just alarms - time up with allocations flat is a constant-factor or contention
problem, allocations up with time flat is a regression that got lucky with the
collector and will bite later.

These are starting points. Calibrate them by running the suite twice against
identical code and reading the spread: the limits should sit comfortably above
that noise floor, or the gate flaps.
-}
limits :: Limits
limits =
    Limits
        { time = Thresholds {geomean = Factor 1.05, perCase = Factor 1.20}
        , alloc = Thresholds {geomean = Factor 1.01, perCase = Factor 1.02}
        }

compareRun :: ReferenceState -> [(CaseName, Measurement)] -> Run
compareRun state measured =
    Run
        { rows = rows
        , aggregate = aggregateOf rows
        , retired = retiredCases state measured
        , outcome = verdict state rows
        }
  where
    rows = uncurry (rowFor state) <$> measured

rowFor :: ReferenceState -> CaseName -> Measurement -> Row
rowFor state name current = case state of
    Recorded reference | Just recorded <- lookupCase reference name -> Referenced name current recorded
    _ -> Unreferenced name current

verdict :: ReferenceState -> [Row] -> Outcome
verdict Unrecorded _ = Ungated
verdict (Recorded _) rows =
    maybe Passed Regressed
        . nonEmpty
        . concatMap (uncurry $ regressionsIn rows)
        $ [(TimeMetric, limits.time), (AllocMetric, limits.alloc)]

{- | Every way the run broke one metric's limits, over both scopes.

Both scopes are checked because either alone lets something through: a geomean
absorbs one case blowing up among several that held steady, and a per-case
limit loose enough not to flap on noise cannot see a small drift across the
whole suite.
-}
regressionsIn :: [Row] -> Metric -> Thresholds -> [Regression]
regressionsIn rows metric thresholds = geomeanBreach <> caseBreaches
  where
    geomeanBreach =
        [ Regression metric SuiteGeomean observed thresholds.geomean
        | Just shift <- [aggregateOf rows]
        , let observed = metricOf metric shift
        , observed > thresholds.geomean
        ]

    caseBreaches =
        [ Regression metric (SingleCase $ rowName row) observed thresholds.perCase
        | row <- rows
        , Just shift <- [rowShift row]
        , let observed = metricOf metric shift
        , observed > thresholds.perCase
        ]

metricOf :: Metric -> Shift -> Factor
metricOf TimeMetric = (.time)
metricOf AllocMetric = (.alloc)

shiftOf :: Measurement -> Measurement -> Shift
shiftOf current reference =
    Shift
        { time = factorOf (secondsOf current.time) (secondsOf reference.time)
        , alloc = factorOf (bytesOf current.allocated) (bytesOf reference.allocated)
        }
  where
    secondsOf (Seconds s) = s
    bytesOf (Bytes b) = b

aggregateOf :: [Row] -> Maybe Shift
aggregateOf rows = do
    shifts <- nonEmpty $ mapMaybe rowShift rows
    pure
        Shift
            { time = geometricMean $ (.time) <$> shifts
            , alloc = geometricMean $ (.alloc) <$> shifts
            }

{- | The geometric mean, which is the right average for ratios: a halving and a
doubling cancel to 1, where an arithmetic mean would call the pair a 25% loss.
-}
geometricMean :: NonEmpty Factor -> Factor
geometricMean fs =
    Factor . exp $ sum (log . unFactor <$> fs) / fromIntegral (NE.length fs)
  where
    unFactor (Factor f) = f

{- | Neither side is ever zero in practice - every case does real work - but a
zero would otherwise divide or take a logarithm of nothing further down. Such a
pair is reported as unchanged rather than as an infinite regression.
-}
factorOf :: Double -> Double -> Factor
factorOf current reference
    | reference <= 0 || current <= 0 = Factor 1
    | otherwise = Factor $ current / reference

retiredCases :: ReferenceState -> [(CaseName, Measurement)] -> [RecordedCase]
retiredCases Unrecorded _ = []
retiredCases (Recorded reference) measured =
    filter ((`notElem` fmap fst measured) . (.name)) reference.cases

-- | A Factor as the signed percentage a reader expects: @Factor 1.05@ is @5.0@.
asPercent :: Factor -> Double
asPercent (Factor f) = (f - 1) * 100
