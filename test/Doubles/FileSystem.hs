module Doubles.FileSystem (
    MockRoFileSystem (..),
    defaultMockRoFileSystem,
    runMockRoFileSystem,
    runMockWrFileSystem,
    mockFileSystem,
    mockDirs,
) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Effectful (Eff, IOE, (:>))
import Effectful.Dispatch.Dynamic (interpret)
import Effects.FileSystem (RoFileSystem (..), WrFileSystem (..))
import FileSystem.Path (AbsPath, absPathUnsafe, decodeOsPath, encodeOsPath)
import System.OsPath (OsPath, (</>))

{- | Mock implementations for every 'RoFileSystem' operation.

Parameterized over @es@ so a mock can use other effects in the test stack
(a @State@ or a @Writer@, say) when it needs to.
-}
data MockRoFileSystem es = MockRoFileSystem
    { mockReadFile :: AbsPath -> Eff es ByteString
    , mockFileExists :: AbsPath -> Eff es Bool
    , mockDirectoryExists :: AbsPath -> Eff es Bool
    , mockIsSymlink :: AbsPath -> Eff es Bool
    , mockListDirectory :: AbsPath -> Eff es [AbsPath]
    , mockGetHomeDirectory :: Eff es AbsPath
    , mockMkAbsolute :: OsPath -> Eff es AbsPath
    }

-- | An empty filesystem whose home and current directory are both @~/@.
defaultMockRoFileSystem :: MockRoFileSystem es
defaultMockRoFileSystem =
    MockRoFileSystem
        { mockReadFile = const $ pure mempty
        , mockFileExists = const $ pure False
        , mockDirectoryExists = const $ pure False
        , mockIsSymlink = const $ pure False
        , mockListDirectory = const $ pure []
        , mockGetHomeDirectory = pure . absPathUnsafe $ encodeOsPath "~/"
        , -- (</>) discards its left argument when `p` is already absolute.
          mockMkAbsolute = pure . absPathUnsafe . normalizeMockPath . (encodeOsPath "~/" </>)
        }

-- | Interprets 'RoFileSystem' with the given mocks.
runMockRoFileSystem :: MockRoFileSystem es -> Eff (RoFileSystem : es) a -> Eff es a
runMockRoFileSystem mocks = interpret $ \_ -> \case
    ReadFile p -> mocks.mockReadFile p
    FileExists p -> mocks.mockFileExists p
    DirectoryExists p -> mocks.mockDirectoryExists p
    IsSymlink p -> mocks.mockIsSymlink p
    ListDirectory p -> mocks.mockListDirectory p
    GetHomeDirectory -> mocks.mockGetHomeDirectory
    MkAbsolute p -> mocks.mockMkAbsolute p

{- | Records every write in memory instead of reaching the disk, the last write
to a path winning. Assert on the resulting map, not on which calls were made.
-}
runMockWrFileSystem ::
    (IOE :> es) =>
    IORef (Map AbsPath ByteString) ->
    Eff (WrFileSystem : es) a ->
    Eff es a
runMockWrFileSystem written = interpret $ \_ -> \case
    WriteFile path content -> modifyIORef' written $ Map.insert path content
    MkDirP _ -> pure ()

{- | An in-memory filesystem: exactly these paths exist, holding exactly these
bytes. A fake rather than a stub, so a component that reads several files runs
its real codepath.
-}
mockFileSystem :: [(AbsPath, ByteString)] -> MockRoFileSystem es
mockFileSystem files =
    defaultMockRoFileSystem
        { mockFileExists = pure . (`Map.member` contents)
        , mockReadFile = pure . fromMaybe mempty . (`Map.lookup` contents)
        }
  where
    contents = Map.fromList files

-- | Exactly these directories exist, each listing exactly these entries.
mockDirs :: [(AbsPath, [AbsPath])] -> MockRoFileSystem es
mockDirs dirs =
    defaultMockRoFileSystem
        { mockDirectoryExists = pure . (`Map.member` entries)
        , mockListDirectory = pure . sort . fromMaybe [] . (`Map.lookup` entries)
        }
  where
    entries = Map.fromList dirs

-- | Purely mimics OS canonicalization of @.@ and @..@ segments.
normalizeMockPath :: OsPath -> OsPath
normalizeMockPath =
    encodeOsPath
        . T.intercalate "/"
        . keepRoot
        . reverse
        . foldl' resolveDots []
        . T.splitOn "/"
        . T.replace "\\" "/"
        . decodeOsPath
  where
    resolveDots acc "." = acc
    resolveDots [""] ".." = [""] -- never back out of the root '/'
    resolveDots [] ".." = [".."] -- keep a relative parent traversal
    resolveDots (_ : acc) ".." = acc
    resolveDots acc x = x : acc

    -- A path reduced to the root alone must still render as "/".
    keepRoot [""] = ["", ""]
    keepRoot parts = parts
