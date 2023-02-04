{-# LANGUAGE OverloadedStrings #-}
module MkElmDerivation.Conduits where

import qualified Control.Concurrent as Con
import Control.Monad.IO.Class
import Control.Monad.Reader
import Control.Monad.Trans.Maybe
import Data.Aeson
import qualified Data.ByteString.Lazy as BL
import qualified Data.Conduit.Binary as BS
import qualified Data.HashMap.Strict as M
import Data.Hashable
import qualified Data.Text as T
import qualified Data.Vector as V
import MkElmDerivation.GetPackages
import MkElmDerivation.MapHelpers
import MkElmDerivation.Types
import Network.HTTP.Client.Conduit
import Network.HTTP.Simple
import Network.HTTP.Types.Status
import System.Directory


import qualified Data.ByteString as B
import Data.Conduit
import Data.Conduit.Binary


-- | The absolute path of the output file, to read and save successes.
output :: IO FilePath
output = makeAbsolute "./elmData.json"

-- | The absolute path of the failures file, to read and save failures.
failures :: IO FilePath
failures = makeAbsolute "./failures.json"

conduitFile2Map :: (Monad m, FromJSON b, FromJSONKey a, Hashable a, MonadIO m) => ConduitT B.ByteString Void m (M.HashMap a b)
conduitFile2Map = helper ""
  where
    helper bytes = do
        contentM <- await
        case contentM of
            Just content -> helper $ bytes <> content
            Nothing -> do
            case decodeStrict bytes of
                Nothing -> return M.empty
                Just niceMap -> return niceMap


conduitOutputs ::(Monad m, MonadIO m) => ConduitT B.ByteString Void m (M.HashMap Name (M.HashMap Version Hash))
conduitOutputs = conduitFile2Map

conduitFailures :: (Monad m, MonadIO m) => ConduitT B.ByteString Void m (M.HashMap Name Versions)
conduitFailures = conduitFile2Map

conduitSaveFailuresMap ::
  (Monad m) =>
  M.HashMap Name Versions ->
  M.HashMap Name Versions ->
  ConduitT () B.ByteString m ()
conduitSaveFailuresMap failedPackages alreadyFailed = do
  yield . B.toStrict . encode $ updateFailures failedPackages alreadyFailed

conduitSaveSuccessesMap ::
  (Monad m) =>
  M.HashMap Name (M.HashMap Version Hash) ->
  M.HashMap Name (M.HashMap Version Hash) ->
  ConduitT () B.ByteString m ()
conduitSaveSuccessesMap successfulPackages alreadyHashed = do
  yield . B.toStrict . encode $ joinNewPackages successfulPackages alreadyHashed

-- | Fetch elmPackages JSON and parse into a map.
remoteSrc :: MaybeT IO (M.HashMap Name Versions)
remoteSrc = do
  liftIO $ print "Fetching elmPackages.json"
  req <- parseRequest "https://package.elm-lang.org/all-packages"
  resp <- httpLBS req
  let status = getResponseStatus resp
  if statusIsSuccessful status
    then MaybeT . return . decode . getResponseBody $ resp
    else do
      liftIO $ print "Could not fetch json file"
      MaybeT . return $ Nothing

getNewPkgsToHash ::
  -- | Already hashed packages.
  M.HashMap Name (M.HashMap Version Hash) ->
  -- | Previous failed packages
  M.HashMap Name Versions ->
  -- | All elm-packages.json.
  M.HashMap Name Versions ->
  IO (M.HashMap Name Versions)
getNewPkgsToHash alreadyHashed failuresMap allPkgsMap = do
  return . removeFailedPkgs (extractNewPackages allPkgsMap alreadyHashed) $ failuresMap

getFailuresSuccesses ::
  M.HashMap Name Versions ->
  IO (M.HashMap Name Versions, M.HashMap Name (M.HashMap Version Hash))
getFailuresSuccesses toHash = do
  sucMvar <- Con.newMVar M.empty
  failMvar <- Con.newMVar M.empty

  runReaderT (downloadElmPackages toHash) $ ReadState sucMvar failMvar

  failedPackages <- Con.takeMVar failMvar
  successfulPackages <- Con.takeMVar sucMvar
  return (failedPackages, successfulPackages)
