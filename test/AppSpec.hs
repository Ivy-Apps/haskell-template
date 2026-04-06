module AppSpec (spec) where

import App (dummyFun)
import Test.Hspec

spec :: Spec
spec = do
    describe "Dummy test suite" $ do
        it "the dummyFun should return 42" $ do
            dummyFun `shouldBe` 42
