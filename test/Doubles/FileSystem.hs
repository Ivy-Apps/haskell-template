module Doubles.FileSystem (
    MockRoFileSystem (..),
    defaultMockRoFileSystem,
    runMockRoFileSystem,
    runReadOnly,
    runWritesInMemory,
    mockTree,
    mockDirs,
    InMemoryFileSystem (..),
    newInMemoryFileSystem,
    runInMemoryFileSystem,
) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Effectful (Eff, IOE, runEff, (:>))
import Effectful.Dispatch.Dynamic (interpret)
import Effects.FileSystem (RoFileSystem (..), WrFileSystem (..))
import FileSystem.Path (AbsPath (..), absPathUnsafe, decodeOsPath, encodeOsPath)
import System.OsPath (OsPath, splitDirectories, (</>))

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

-- | Runs a read-only computation over the given mocks, with nothing else in the stack.
runReadOnly :: MockRoFileSystem '[IOE] -> Eff '[RoFileSystem, IOE] a -> IO a
runReadOnly mocks = runEff . runMockRoFileSystem mocks

{- | Every write lands in memory, keyed by the path it was written to, and
never reaches the disk: a run can read a real fixture while what it would have
written is asserted on instead. Writing a path again replaces what it held, as
on disk. Directories are implied by the files beneath them, so 'MkDirP'
records nothing.
-}
runWritesInMemory ::
    (IOE :> es) =>
    IORef (Map AbsPath ByteString) ->
    Eff (WrFileSystem : es) a ->
    Eff es a
runWritesInMemory ref = interpret $ \_ -> \case
    WriteFile path content -> modifyIORef' ref $ Map.insert path content
    MkDirP _ -> pure ()

{- | A read-only tree of files, held purely: exactly these paths exist, holding
exactly these bytes, inside the directories the files imply. A fake rather than
a stub, so a component that reads several files or walks a directory runs its
real codepath, even under 'Effectful.runPureEff'.
-}
mockTree :: [(AbsPath, ByteString)] -> MockRoFileSystem es
mockTree = readingFrom . pure . Map.fromList

{- | Exactly these directories exist, each listing exactly these entries. Unlike
'mockTree', a directory here may be empty.
-}
mockDirs :: [(AbsPath, [AbsPath])] -> MockRoFileSystem es
mockDirs dirs =
    defaultMockRoFileSystem
        { mockDirectoryExists = pure . (`Map.member` entries)
        , mockListDirectory = pure . sort . fromMaybe [] . (`Map.lookup` entries)
        }
  where
    entries = Map.fromList dirs

{- | A working filesystem in memory: reads see what was written, and every
write is remembered in order, so a test can tell an untouched file from one
rewritten with the same bytes. Directories are implied by the files beneath
them.
-}
data InMemoryFileSystem = InMemoryFileSystem
    { files :: IORef (Map AbsPath ByteString)
    , written :: IORef [AbsPath]
    }

-- | A filesystem holding exactly these files, with nothing written yet.
newInMemoryFileSystem :: (MonadIO m) => [(AbsPath, ByteString)] -> m InMemoryFileSystem
newInMemoryFileSystem initial =
    InMemoryFileSystem <$> newIORef (Map.fromList initial) <*> newIORef []

-- | Interprets both effects over the given in-memory filesystem.
runInMemoryFileSystem ::
    (IOE :> es) =>
    InMemoryFileSystem ->
    Eff (WrFileSystem : RoFileSystem : es) a ->
    Eff es a
runInMemoryFileSystem fs = runMockRoFileSystem (readingFrom $ readIORef fs.files) . writing
  where
    writing = interpret $ \_ -> \case
        WriteFile p content -> do
            modifyIORef' fs.files $ Map.insert p content
            modifyIORef' fs.written (<> [p])
        MkDirP _ -> pure ()

{- | Reads whatever files the action says there are, as 'mockTree' does.
Listings come back sorted, as the IO interpreter returns them.
-}
readingFrom :: Eff es (Map AbsPath ByteString) -> MockRoFileSystem es
readingFrom current =
    defaultMockRoFileSystem
        { mockReadFile = \p -> fromMaybe mempty . Map.lookup p <$> current
        , mockFileExists = \p -> Map.member p <$> current
        , mockDirectoryExists = \p -> any (isBeneath p) . Map.keys <$> current
        , mockListDirectory = \p -> sort . ordNub . mapMaybe (childOf p) . Map.keys <$> current
        }
  where
    segments = splitDirectories . (.osPath)
    isBeneath dir file = segments dir `isPrefixOf` segments file && segments dir /= segments file
    childOf dir file = case drop (length $ segments dir) (segments file) of
        child : _ | isBeneath dir file -> Just . absPathUnsafe $ dir.osPath </> child
        _ -> Nothing

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
