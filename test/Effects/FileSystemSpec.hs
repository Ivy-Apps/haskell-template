module Effects.FileSystemSpec (spec) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Doubles.FileSystem (
    defaultMockRoFileSystem,
    mockFileSystem,
    runMockRoFileSystem,
    runMockWrFileSystem,
 )
import Effectful (runEff)
import Effects.FileSystem (
    fsDirectoryExists,
    fsFileExists,
    fsListDirectory,
    fsMkAbsolute,
    fsReadFile,
    fsWriteFile,
    runRoFileSystemIO,
 )
import FileSystem.Path (AbsPath (..), absPathUnsafe, encodeOsPath)
import System.OsPath (isAbsolute, osp)
import Test.Hspec

spec :: Spec
spec = describe "Effects.FileSystem" $ do
    describe "the IO interpreter" $ do
        it "canonicalizes a relative path into an existing absolute one" $ do
            absPath <- runEff . runRoFileSystemIO . fsMkAbsolute $ [osp|./test/../haskell-app.cabal|]

            absPath.osPath `shouldSatisfy` isAbsolute
            runEff (runRoFileSystemIO $ fsFileExists absPath) `shouldReturn` True

        it "tells a directory from a file" $ do
            (dirExists, fileExists) <- runEff . runRoFileSystemIO $ do
                src <- fsMkAbsolute [osp|src|]
                (,) <$> fsDirectoryExists src <*> fsFileExists src

            (dirExists, fileExists) `shouldBe` (True, False)

        it "lists a directory as sorted absolute paths" $ do
            entries <- runEff . runRoFileSystemIO $ fsListDirectory =<< fsMkAbsolute [osp|src|]

            entries `shouldSatisfy` (not . null)
            entries `shouldSatisfy` all (isAbsolute . (.osPath))
            entries `shouldBe` sort entries

        it "reads a file's bytes" $ do
            content <- runEff . runRoFileSystemIO $ fsReadFile =<< fsMkAbsolute [osp|haskell-app.cabal|]

            content `shouldSatisfy` BS.isPrefixOf "cabal-version:"

    describe "the in-memory double" $ do
        it "holds exactly the files it was given" $ do
            let file = ap "/repo/README.md"
            let fs = mockFileSystem [(file, "# Hello")]

            (exists, missing, content) <- runEff . runMockRoFileSystem fs $ do
                (,,) <$> fsFileExists file <*> fsFileExists (ap "/repo/other.md") <*> fsReadFile file

            (exists, missing, content) `shouldBe` (True, False, "# Hello")

        it "records writes in memory, the last write to a path winning" $ do
            written <- newIORef mempty

            runEff . runMockWrFileSystem written $ do
                fsWriteFile (ap "/repo/a.txt") "first"
                fsWriteFile (ap "/repo/b.txt") "other"
                fsWriteFile (ap "/repo/a.txt") "second"

            readIORef written
                `shouldReturn` Map.fromList [(ap "/repo/a.txt", "second"), (ap "/repo/b.txt", "other")]

        it "resolves a relative path against the home directory" $ do
            absPath <- runEff . runMockRoFileSystem defaultMockRoFileSystem . fsMkAbsolute $ [osp|src/../app/Main.hs|]

            absPath `shouldBe` ap "~/app/Main.hs"
  where
    ap = absPathUnsafe . encodeOsPath
