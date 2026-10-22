{- | What the benchmark measures. The only project-specific module under
@bench/@: everything else judges and reports whatever this lists.

The list is spelled out rather than discovered, so that adding or removing a
case is a decision someone makes, visible in review, and not a side effect
that silently changes the set the Reference was recorded against.
-}
module Bench.Cases (
    Case (..),
    CaseName (..),
    cases,
) where

import Criterion (Benchmarkable, nf)
import Data.Aeson (FromJSON, ToJSON)
import FileSystem.Path (decodeOsPath, encodeOsPath)

-- | Identifies a case in the report and in @bench/reference.yaml@. Renaming one retires it.
newtype CaseName = CaseName Text
    deriving stock (Show)
    deriving newtype (Eq, Ord, ToJSON, FromJSON)

data Case = Case
    { name :: CaseName
    , benchmarkable :: Benchmarkable
    }

{- | Every case, roughly most expensive first, so the report opens with the rows
carrying the most signal.

Each case does a batch of work rather than a single call: a case that finishes
in nanoseconds is measuring the clock more than the code.
-}
cases :: [Case]
cases =
    [ Case (CaseName "encode + decode paths") $ nf (fmap (decodeOsPath . encodeOsPath)) paths
    , Case (CaseName "encode paths") $ nf (fmap encodeOsPath) paths
    ]

-- | A thousand distinct, realistically shaped module paths.
paths :: [Text]
paths =
    [ "src/Feature" <> show n <> "/Module" <> show m <> ".hs"
    | n <- [1 .. 100 :: Int]
    , m <- [1 .. 10 :: Int]
    ]
