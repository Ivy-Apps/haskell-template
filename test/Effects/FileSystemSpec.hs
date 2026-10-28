module Effects.FileSystemSpec (spec) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Doubles.FileSystem (
    InMemoryFileSystem (..),
    defaultMockRoFileSystem,
    mockTree,
    newInMemoryFileSystem,
    runInMemoryFileSystem,
    runReadOnly,
    runWritesInMemory,
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
import System.IO.Error (isDoesNotExistError)
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

        it "fails to read a missing file" $ do
            let reading = runEff . runRoFileSystemIO $ fsReadFile =<< fsMkAbsolute [osp|no-such-file|]

            reading `shouldThrow` isDoesNotExistError

        it "fails to list a missing directory" $ do
            let listing = runEff . runRoFileSystemIO $ fsListDirectory =<< fsMkAbsolute [osp|no-such-dir|]

            listing `shouldThrow` isDoesNotExistError

    describe "the read-only tree double" $ do
        it "holds exactly the files it was given" $ do
            let file = ap "/repo/README.md"

            result <- runReadOnly (mockTree [(file, "# Hello")]) $ do
                (,,) <$> fsFileExists file <*> fsFileExists (ap "/repo/other.md") <*> fsReadFile file

            result `shouldBe` (True, False, "# Hello")

        it "implies the directories its files live in, but not the files themselves" $ do
            let tree = mockTree [(ap "/repo/src/Main.hs", "")]

            result <- runReadOnly tree $ do
                (,,) <$> fsDirectoryExists (ap "/repo") <*> fsDirectoryExists (ap "/repo/src") <*> fsDirectoryExists (ap "/repo/src/Main.hs")

            result `shouldBe` (True, True, False)

        it "lists a directory's direct children once each, sorted" $ do
            let tree =
                    mockTree
                        [ (ap "/repo/src/b/Deep.hs", "")
                        , (ap "/repo/src/b.hs", "")
                        , (ap "/repo/src/b/Other.hs", "")
                        , (ap "/repo/src/a.hs", "")
                        ]

            entries <- runReadOnly tree . fsListDirectory $ ap "/repo/src"

            entries `shouldBe` [ap "/repo/src/a.hs", ap "/repo/src/b", ap "/repo/src/b.hs"]

        it "resolves a relative path against the home directory" $ do
            absPath <- runReadOnly defaultMockRoFileSystem . fsMkAbsolute $ [osp|src/../app/Main.hs|]

            absPath `shouldBe` ap "~/app/Main.hs"

    describe "the in-memory writes double" $ do
        it "records every written path, the last write to a path winning" $ do
            written <- newIORef mempty

            runEff . runWritesInMemory written $ do
                fsWriteFile (ap "/repo/a.txt") "first"
                fsWriteFile (ap "/repo/b.txt") "other"
                fsWriteFile (ap "/repo/a.txt") "second"

            readIORef written
                `shouldReturn` Map.fromList [(ap "/repo/a.txt", "second"), (ap "/repo/b.txt", "other")]

    describe "the in-memory filesystem" $ do
        it "reads back what was written over its initial files" $ do
            fs <- newInMemoryFileSystem [(ap "/repo/a.txt", "old"), (ap "/repo/b.txt", "kept")]

            result <- runEff . runInMemoryFileSystem fs $ do
                fsWriteFile (ap "/repo/a.txt") "new"
                fsWriteFile (ap "/repo/c.txt") "added"
                traverse fsReadFile [ap "/repo/a.txt", ap "/repo/b.txt", ap "/repo/c.txt"]

            result `shouldBe` ["new", "kept", "added"]

        it "tells a file rewritten with the same bytes from an untouched one" $ do
            fs <- newInMemoryFileSystem [(ap "/repo/a.txt", "same"), (ap "/repo/b.txt", "same")]

            runEff . runInMemoryFileSystem fs . fsWriteFile (ap "/repo/a.txt") $ "same"

            readIORef fs.written `shouldReturn` [ap "/repo/a.txt"]

        it "fails to read a missing file, as the IO interpreter does" $ do
            fs <- newInMemoryFileSystem [(ap "/repo/a.txt", "")]

            runEff (runInMemoryFileSystem fs . fsReadFile $ ap "/repo/b.txt")
                `shouldThrow` isDoesNotExistError

        it "fails to list a missing directory, as the IO interpreter does" $ do
            fs <- newInMemoryFileSystem [(ap "/repo/a.txt", "")]

            runEff (runInMemoryFileSystem fs . fsListDirectory $ ap "/other")
                `shouldThrow` isDoesNotExistError
  where
    ap = absPathUnsafe . encodeOsPath
