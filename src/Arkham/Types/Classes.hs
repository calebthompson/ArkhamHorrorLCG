{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies          #-}
module Arkham.Types.Classes where

import           Arkham.Types.LocationId
import           Arkham.Types.Message
import           Arkham.Types.Trait
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
pushMessage = pushMessages . pure

pushMessages :: (MonadIO m, MonadReader env m, HasQueue env) => [Message] -> m()
pushMessages msgs = withQueue $ \queue -> (queue <> msgs, ())

unshiftMessage :: (MonadIO m, MonadReader env m, HasQueue env) => Message -> m ()
unshiftMessage = unshiftMessages . pure

unshiftMessages :: (MonadIO m, MonadReader env m, HasQueue env) => [Message] -> m ()
unshiftMessages msgs = withQueue $ \queue -> (msgs <> queue, ())

runCheck
  :: (HasQueue env, MonadReader env m, MonadIO m)
  => Int
  -> m ()
runCheck modifiedSkillValue = unshiftMessage (RunSkillCheck modifiedSkillValue)

class HasSet key a where
  getSet :: a -> HashSet key

class HasLocation a where
  locationOf :: a -> LocationId

class HasCount c b a where
  getCount :: b -> a -> c

class HasClueCount a where
  getClueCount :: a -> ClueCount

class HasTraits a where
  traitsOf :: a -> HashSet Trait
