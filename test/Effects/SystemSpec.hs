module Effects.SystemSpec (spec) where

import Effectful (runEff)
import Effects.System (runSystem, sLookupEnv)
import System.Environment (setEnv)
import Test.Hspec

spec :: Spec
spec = describe "Effects.System" $ do
    describe "the IO interpreter" $ do
        it "reads a variable from the environment" $ do
            setEnv "HASKELL_APP_SYSTEM_SPEC" "the value"

            runEff (runSystem . sLookupEnv $ "HASKELL_APP_SYSTEM_SPEC") `shouldReturn` Just "the value"

        it "answers Nothing for a variable that is not set" $ do
            runEff (runSystem . sLookupEnv $ "HASKELL_APP_NEVER_SET") `shouldReturn` Nothing
