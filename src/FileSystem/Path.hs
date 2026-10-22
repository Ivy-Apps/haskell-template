{- | The path vocabulary, and the encoding between 'OsPath' and 'Text'.

Nominal rather than a bare 'OsPath': a path that has been made absolute is a
different thing from one that is relative to something, and only one of them
can be opened from anywhere. Nothing here performs IO - reaching the
filesystem is "Effects.FileSystem" - so a pure module may name a path without
taking on an effect to do it.
-}
module FileSystem.Path (
    -- * Encoding
    encodeOsPath,
    encodeOsPathString,
    decodeOsPath,

    -- * Absolute paths
    AbsPath (osPath),
    absPathUnsafe,
    withAbsBaseUnsafe,
) where

import Control.Monad.Catch.Pure (runCatch)
import Data.Text qualified as T
import System.OsPath (OsPath, decodeUtf, encodeUtf, (</>))

encodeOsPath :: Text -> OsPath
encodeOsPath = encodeOsPathString . T.unpack

{- | Encodes as UTF-8 (UTF-16 on Windows). Every 'String' built from a 'Text'
is valid Unicode, so the failure branch is unreachable for those.
-}
encodeOsPathString :: FilePath -> OsPath
encodeOsPathString p =
    case runCatch (encodeUtf p) of
        Right path -> path
        Left err -> error $ "encodeOsPath failed: " <> show err

decodeOsPath :: OsPath -> Text
decodeOsPath = either handleErr T.pack . runCatch . decodeUtf
  where
    handleErr err = error $ "decodeOsPath failed: " <> show err

newtype AbsPath = AbsPath
    { osPath :: OsPath
    }
    deriving stock (Show, Eq, Ord)

-- | Trusts the caller that the path is absolute. Prefer 'Effects.FileSystem.fsMkAbsolute'.
absPathUnsafe :: OsPath -> AbsPath
absPathUnsafe = AbsPath

-- | Appends a path to an absolute base. Unsafe because @..@ segments are kept as they are.
withAbsBaseUnsafe :: AbsPath -> OsPath -> AbsPath
withAbsBaseUnsafe (AbsPath b) p = AbsPath (b </> p)
