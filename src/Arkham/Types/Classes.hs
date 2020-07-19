{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies          #-}
module Arkham.Types.Classes where

import           Arkham.Types.LocationId
import           Arkham.Types.Message
import           ClassyPrelude
import           Lens.Micro
import           Lens.Micro.Extras

class HasQueue a where
  messageQueue :: Lens' a (IORef [Message])

class (HasQueue env) => RunMessage env a where
  runMessage :: (MonadIO m, MonadReader env m) => Message -> a -> m a

withQueue
  :: (MonadIO m, MonadReader env m, HasQueue env)
  => ([Message] -> ([Message], r))
  -> m r
withQueue body = do
  ref <- asks $ view messageQueue
  liftIO $ atomicModifyIORef' ref body

popMessage :: (MonadIO m, MonadReader env m, HasQueue env) => m (Maybe Message)
popMessage = withQueue $ \case
  [] -> ([], Nothing)
  (m:ms) -> (ms, Just m)

peekMessage :: (MonadIO m, MonadReader env m, HasQueue env) => m (Maybe Message)
peekMessage = withQueue $ \case
  [] -> ([], Nothing)
  (m:ms) -> (m:ms, Just m)

pushMessage :: (MonadIO m, MonadReader env m, HasQueue env) => Message -> m ()
pushMessage msg = withQueue $ \queue -> (queue <> [msg], ())

unshiftMessage :: (MonadIO m, MonadReader env m, HasQueue env) => Message -> m ()
unshiftMessage msg = withQueue $ \queue -> (msg:queue, ())

-- class HasMap key a where
--   type Elem key = r | r -> key
--   getMap :: Lens' a (HashMap key (Elem key))

class HasMap key a where
  type Elem key
  getMap :: Lens' a (HashMap key (Elem key))

class HasLocation a where
  locationOf :: a -> LocationId
