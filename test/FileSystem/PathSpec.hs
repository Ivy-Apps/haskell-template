module FileSystem.PathSpec (spec) where

import FileSystem.Path (decodeOsPath, encodeOsPath, encodeOsPathString)
import Hedgehog (forAll, tripping)
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import System.OsPath (osp)
import Test.Hspec
import TestUtils (prop)

spec :: Spec
spec = describe "FileSystem.Path" $ do
    describe "encodeOsPath" $ do
        it "spells a relative path the way the osp quasiquoter does" $ do
            encodeOsPath "src/Main.hs" `shouldBe` [osp|src/Main.hs|]

        it "spells the empty path as the empty OsPath" $ do
            encodeOsPath "" `shouldBe` mempty

        it "agrees with encodeOsPathString" $ do
            encodeOsPath "test/Ünïcødé.hs" `shouldBe` encodeOsPathString "test/Ünïcødé.hs"

    describe "decodeOsPath" $ do
        it "reads back a non-ASCII path" $ do
            decodeOsPath [osp|docs/Привет.md|] `shouldBe` "docs/Привет.md"

    prop "decodeOsPath undoes encodeOsPath for any Unicode text" $ do
        path <- forAll . Gen.text (Range.linear 0 64) $ Gen.unicode

        tripping path encodeOsPath (Just . decodeOsPath)
