module TestUtils where

import Hedgehog (PropertyT)
import Test.Hspec (Spec, it)
import Test.Hspec.Hedgehog (hedgehog)

prop :: String -> PropertyT IO () -> Spec
prop desc = it desc . hedgehog
