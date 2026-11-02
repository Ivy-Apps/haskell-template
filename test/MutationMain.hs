{- | The test suite's entry point under the @mutation@ cabal flag: the same hspec
tree, run by sydtest so that sydtest-mutation can drive it.
-}
module Main (main) where

import Spec (spec)
import System.Directory (getTemporaryDirectory)
import System.Environment (setEnv)
import Test.Syd (sydTest)
import Test.Syd.Hspec (fromHspec)
import TestUtils (goldenActualDirEnv)

main :: IO ()
main = do
    setEnv goldenActualDirEnv =<< getTemporaryDirectory
    sydTest . fromHspec $ spec
