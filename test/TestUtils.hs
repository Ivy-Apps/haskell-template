{- | Test plumbing: golden helpers, fixture-directory access, and the small
combinators that keep a failing assertion readable.

Deliberately domain-free. A helper that builds one of the project's own types
belongs under @Fixtures.<module>@ next to the module whose type it builds; a
helper that only knows about hspec, Hedgehog or the filesystem belongs here.
-}
module TestUtils (
    -- * Golden tests
    snapshot,
    pathSafeGolden,

    -- * Fixtures on disk
    listFixtures,
    copyDir,

    -- * Assertions
    prop,
    requireJust,
    requireRight,
) where

import Control.Exception (throwIO)
import Control.Exception.Base (AssertionFailed (..))
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Effectful (runEff)
import Effects.FileSystem (fsMkAbsolute, runRoFileSystemIO)
import FileSystem.Path (AbsPath (osPath), encodeOsPathString)
import Hedgehog (PropertyT)
import System.Directory.OsPath qualified as SDO
import System.File.OsPath qualified as SFO
import System.OsPath (OsPath, osp, takeExtension, (</>))
import Test.Hspec (Spec, expectationFailure, it)
import Test.Hspec.Golden (Golden, defaultGolden)
import Test.Hspec.Hedgehog (hedgehog)

--------------------------------------------------------------------------------
-- Golden tests
--------------------------------------------------------------------------------

{- | Concatenates the given files under @dir@, each behind a @>>> FILE:@
header, so one golden can pin a whole directory's worth of output.
-}
snapshot :: OsPath -> [String] -> IO String
snapshot dir filesToVerify = do
    results <- forM filesToVerify $ \relPath -> do
        content <- TE.decodeUtf8 <$> SFO.readFile' (dir </> encodeOsPathString relPath)
        pure $ "\n\n\n>>> FILE: " <> T.pack relPath <> "\n" <> content
    pure . T.unpack . T.dropWhile (== '\n') . T.concat $ results

{- | Goldens a value that holds an absolute path /by design/, with the
directory the suite runs from replaced by @~@ so the snapshot is the same on
every machine.

For internal values only. Never for what the program prints to its users:
scrubbing that output would hide an absolute path rather than fail on it.
-}
pathSafeGolden :: String -> String -> IO (Golden String)
pathSafeGolden name content = do
    -- Spelled as 'show' spells it, since that is how a path reaches the content.
    base <- T.replace "\"" "" . show . (.osPath) <$> (runEff . runRoFileSystemIO . fsMkAbsolute $ [osp|.|])
    pure . defaultGolden name . T.unpack . T.replace base "~" . T.pack $ content

--------------------------------------------------------------------------------
-- Fixtures on disk
--------------------------------------------------------------------------------

-- | The entries of @dir@ with the given extension (including the dot, e.g. @".json"@).
listFixtures :: OsPath -> String -> IO [OsPath]
listFixtures dir ext =
    filter ((== encodeOsPathString ext) . takeExtension) <$> SDO.listDirectory dir

-- | Recursively copies @src@ into @dst@, creating @dst@ if it is missing.
copyDir :: OsPath -> OsPath -> IO ()
copyDir src dst = do
    SDO.createDirectoryIfMissing True dst
    entries <- SDO.listDirectory src
    forM_ entries $ \name -> do
        let srcPath = src </> name
        let dstPath = dst </> name
        isDirectory <- SDO.doesDirectoryExist srcPath
        if isDirectory
            then copyDir srcPath dstPath
            else SDO.copyFile srcPath dstPath

--------------------------------------------------------------------------------
-- Assertions
--------------------------------------------------------------------------------

prop :: String -> PropertyT IO () -> Spec
prop desc = it desc . hedgehog

-- | Extracts the value from a 'Maybe', or fails the test with the message.
requireJust :: (HasCallStack) => String -> Maybe a -> IO a
requireJust msg = \case
    Nothing -> expectationFailure msg >> throwIO (AssertionFailed "unreachable")
    Just x -> pure x

-- | Extracts the value from an 'Either', or fails the test with the rendered error.
requireRight :: (HasCallStack) => (e -> String) -> Either e a -> IO a
requireRight formatErr = \case
    Left e -> expectationFailure (formatErr e) >> throwIO (AssertionFailed "unreachable")
    Right x -> pure x
