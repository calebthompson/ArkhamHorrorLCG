{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
module Arkham.Types.Game
  ( runGame
  , newGame
  , Game(..)
  )
where

import Arkham.Types.Act
import Arkham.Types.ActId
import Arkham.Types.Agenda
import Arkham.Types.AgendaId
import Arkham.Types.Asset
import Arkham.Types.AssetId
import Arkham.Types.Card
import Arkham.Types.Classes
import Arkham.Types.Difficulty
import Arkham.Types.Enemy
import Arkham.Types.EnemyId
import Arkham.Types.Event
import Arkham.Types.GameJson
import Arkham.Types.Helpers
import Arkham.Types.Investigator
import Arkham.Types.InvestigatorId
import Arkham.Types.Location
import Arkham.Types.LocationId
import Arkham.Types.Message
import Arkham.Types.Phase
import Arkham.Types.Prey
import Arkham.Types.Query
import Arkham.Types.Scenario
import Arkham.Types.ScenarioId
import Arkham.Types.SkillCheck
import Arkham.Types.SkillType
import Arkham.Types.Stats
import Arkham.Types.Token (Token)
import qualified Arkham.Types.Token as Token
import Arkham.Types.Trait
import Arkham.Types.Treachery
import Arkham.Types.TreacheryId
import ClassyPrelude
import Control.Monad.State
import Data.Coerce
import qualified Data.HashMap.Strict as HashMap
import qualified Data.HashSet as HashSet
import qualified Data.Sequence as Seq
import Data.UUID.V4
import Lens.Micro
import Lens.Micro.Extras
import Lens.Micro.Platform ()
import Safe (fromJustNote)
import System.Environment
import System.Random
import System.Random.Shuffle
import Text.Pretty.Simple
import Text.Read hiding (get)

data Game = Game
  { giMessages :: IORef [Message]
  , giSeed :: Int
  , giScenario :: Scenario
  , giLocations :: HashMap LocationId Location
  , giInvestigators :: HashMap InvestigatorId Investigator
  , giEnemies :: HashMap EnemyId Enemy
  , giAssets :: HashMap AssetId Asset
  , giActiveInvestigatorId :: InvestigatorId
  , giLeadInvestigatorId :: InvestigatorId
  , giPhase :: Phase
  , giEncounterDeck :: Deck EncounterCard
  , giDiscard :: [EncounterCard]
  , giChaosBag :: Bag Token
  , giSkillCheck :: Maybe SkillCheck
  , giActs :: HashMap ActId Act
  , giAgendas :: HashMap AgendaId Agenda
  , giTreacheries :: HashMap TreacheryId Treachery
  }

phase :: Lens' Game Phase
phase = lens giPhase $ \m x -> m { giPhase = x }

acts :: Lens' Game (HashMap ActId Act)
acts = lens giActs $ \m x -> m { giActs = x }

agendas :: Lens' Game (HashMap AgendaId Agenda)
agendas = lens giAgendas $ \m x -> m { giAgendas = x }

treacheries :: Lens' Game (HashMap TreacheryId Treachery)
treacheries = lens giTreacheries $ \m x -> m { giTreacheries = x }

locations :: Lens' Game (HashMap LocationId Location)
locations = lens giLocations $ \m x -> m { giLocations = x }

investigators :: Lens' Game (HashMap InvestigatorId Investigator)
investigators = lens giInvestigators $ \m x -> m { giInvestigators = x }

enemies :: Lens' Game (HashMap EnemyId Enemy)
enemies = lens giEnemies $ \m x -> m { giEnemies = x }

assets :: Lens' Game (HashMap AssetId Asset)
assets = lens giAssets $ \m x -> m { giAssets = x }

encounterDeck :: Lens' Game [EncounterCard]
encounterDeck =
  lens (coerce . giEncounterDeck) $ \m x -> m { giEncounterDeck = coerce x }

discard :: Lens' Game [EncounterCard]
discard = lens giDiscard $ \m x -> m { giDiscard = x }

chaosBag :: Lens' Game [Token]
chaosBag = lens (coerce . giChaosBag) $ \m x -> m { giChaosBag = coerce x }

leadInvestigatorId :: Lens' Game InvestigatorId
leadInvestigatorId =
  lens giLeadInvestigatorId $ \m x -> m { giLeadInvestigatorId = x }

activeInvestigatorId :: Lens' Game InvestigatorId
activeInvestigatorId =
  lens giActiveInvestigatorId $ \m x -> m { giActiveInvestigatorId = x }

scenario :: Lens' Game Scenario
scenario = lens giScenario $ \m x -> m { giScenario = x }

skillCheck :: Lens' Game (Maybe SkillCheck)
skillCheck = lens giSkillCheck $ \m x -> m { giSkillCheck = x }

activeInvestigator :: Game -> Investigator
activeInvestigator g =
  fromJustNote "No active investigator" $ g ^? investigators . ix iid
  where iid = g ^. activeInvestigatorId

newGame :: MonadIO m => ScenarioId -> [Investigator] -> m Game
newGame scenarioId investigatorsList = do
  ref <- newIORef [Setup]
  mseed <- liftIO $ lookupEnv "SEED"
  seed <- maybe
    (liftIO $ randomIO @Int)
    (pure . fromJustNote "invalid seed" . readMaybe)
    mseed
  liftIO $ setStdGen (mkStdGen seed)
  pure $ Game
    { giMessages = ref
    , giSeed = seed
    , giScenario = lookupScenario scenarioId Easy
    , giLocations = mempty
    , giEnemies = mempty
    , giAssets = mempty
    , giInvestigators = investigatorsMap
    , giActiveInvestigatorId = initialInvestigatorId
    , giLeadInvestigatorId = initialInvestigatorId
    , giPhase = InvestigationPhase
    , giEncounterDeck = mempty
    , giDiscard = mempty
    , giSkillCheck = Nothing
    , giAgendas = mempty
    , giTreacheries = mempty
    , giActs = mempty
    , giChaosBag = Bag
      [ Token.PlusOne
      , Token.PlusOne
      , Token.Zero
      , Token.Zero
      , Token.Zero
      , Token.MinusOne
      , Token.MinusOne
      , Token.MinusOne
      , Token.MinusTwo
      , Token.MinusTwo
      , Token.Skull
      , Token.Skull
      , Token.Cultist
      , Token.Tablet
      , Token.AutoFail
      , Token.ElderSign
      ]
    }
 where
  initialInvestigatorId =
    fromJustNote "No investigators" . headMay . HashMap.keys $ investigatorsMap
  investigatorsMap =
    HashMap.fromList $ map (\i -> (getInvestigatorId i, i)) investigatorsList

instance HasId LeadInvestigatorId () Game where
  getId _ = LeadInvestigatorId . view leadInvestigatorId

instance HasId (Maybe OwnerId) AssetId Game where
  getId aid g = getId () asset
    where asset = fromJustNote "Asset not in game" $ g ^? assets . ix aid

instance HasId StoryAssetId CardCode Game where
  getId cardCode =
    StoryAssetId
      . fst
      . fromJustNote "Asset not in game"
      . find ((cardCode ==) . getCardCode . snd)
      . HashMap.toList
      . view assets

instance HasId LocationId InvestigatorId Game where
  getId = locationFor

instance HasCount ClueCount LocationId Game where
  getCount lid g =
    fromJustNote "No location" $ getClueCount <$> g ^? locations . ix lid

instance HasCount ClueCount InvestigatorId Game where
  getCount iid g =
    fromJustNote "No investigator"
      $ getClueCount
      <$> (g ^? investigators . ix iid)

instance HasCount ClueCount AllInvestigators Game where
  getCount _ g =
    mconcat $ map (`getCount` g) (g ^. investigators . to HashMap.keys)

instance HasCount PlayerCount () Game where
  getCount _ = PlayerCount . HashMap.size . view investigators

instance HasCount EnemyCount (LocationId, [Trait]) Game where
  getCount (lid, traits) g@Game {..} = EnemyCount . length $ HashSet.filter
    enemyMatcher
    locationEnemies
   where
    location = fromJustNote "No location" $ g ^? locations . ix lid
    locationEnemies = getSet () location
    enemyMatcher eid =
      all (`HashSet.member` (traitsOf $ g ^?! enemies . ix eid)) traits

instance HasCount EnemyCount (InvestigatorLocation, [Trait]) Game where
  getCount (InvestigatorLocation iid, traits) g@Game {..} = getCount
    (locationId, traits)
    g
    where locationId = locationFor iid g

instance HasInvestigatorStats Stats InvestigatorId Game where
  getStats iid g = getStats () (g ^?! investigators . ix iid)

instance HasSet RemainingHealth () Game where
  getSet _ =
    HashSet.fromList
      . map (RemainingHealth . remainingHealth)
      . HashMap.elems
      . view investigators

instance HasSet LocationId () Game where
  getSet _ = HashMap.keysSet . view locations

instance HasSet BlockedLocationId () Game where
  getSet _ =
    HashSet.map BlockedLocationId
      . HashMap.keysSet
      . HashMap.filter isBlocked
      . view locations

data BFSState = BFSState
  { _bfsSearchQueue       :: Seq LocationId
  , _bfsVisistedLocations :: HashSet LocationId
  , _bfsParents           :: HashMap LocationId LocationId
  }

getShortestPath :: Game -> LocationId -> (LocationId -> Bool) -> [LocationId]
getShortestPath game initialLocation target = evalState
  (bfs game initialLocation target)
  (BFSState (pure initialLocation) (HashSet.singleton initialLocation) mempty)

bfs :: Game -> LocationId -> (LocationId -> Bool) -> State BFSState [LocationId]
bfs game initialLocation target = do
  BFSState searchQueue visitedSet parentsMap <- get
  if Seq.null searchQueue
    then pure []
    else do
      let nextLoc = Seq.index searchQueue 0
      if target nextLoc
        then pure (unwindPath parentsMap [nextLoc])
        else do
          let
            adjacentCells =
              HashSet.toList . HashSet.map unConnectedLocationId $ getSet
                nextLoc
                game
            unvisitedNextCells =
              filter (\loc -> not (HashSet.member loc visitedSet)) adjacentCells
            newVisitedSet = HashSet.insert nextLoc visitedSet
            newSearchQueue = foldr
              (flip (Seq.|>))
              (Seq.drop 1 searchQueue)
              unvisitedNextCells
            newParentsMap =
              foldr (`HashMap.insert` nextLoc) parentsMap unvisitedNextCells
          put (BFSState newSearchQueue newVisitedSet newParentsMap)
          bfs game initialLocation target
 where
  unwindPath parentsMap currentPath =
    case
        HashMap.lookup
          (fromJustNote "failed bfs" $ headMay currentPath)
          parentsMap
      of
        Nothing -> fromJustNote "failed bfs on tail" $ tailMay currentPath
        Just parent -> unwindPath parentsMap (parent : currentPath)

instance HasSet ClosestLocationId (LocationId, Prey) Game where
  getSet (start, prey) g =
    HashSet.fromList . map ClosestLocationId $ getShortestPath g start matcher
    where matcher lid = not . null $ getSet @PreyId (prey, lid) g

instance HasSet Int SkillType Game where
  getSet skillType g = HashSet.fromList
    $ map (getSkill skillType) (HashMap.elems $ g ^. investigators)

instance HasSet PreyId (Prey, LocationId) Game where
  getSet (preyType, lid) g = HashSet.map PreyId
    $ HashSet.filter matcher investigators'
   where
    location = fromJustNote "No location" $ g ^? locations . ix lid
    investigators' = getSet () location
    matcher iid =
      isPrey preyType g
        . fromJustNote "No investigator"
        $ (g ^? investigators . ix iid)


instance HasSet AdvanceableActId () Game where
  getSet _ g = HashSet.map AdvanceableActId . HashMap.keysSet $ acts'
    where acts' = HashMap.filter isAdvanceable (g ^. acts)

instance HasSet ConnectedLocationId LocationId Game where
  getSet lid g = getSet () location
    where location = fromJustNote "No location" $ g ^? locations . ix lid

instance HasSet AssetId InvestigatorId Game where
  getSet iid g =
    getSet () $ fromJustNote "No investigator" $ g ^? investigators . ix iid

instance HasSet DamageableAssetId InvestigatorId Game where
  getSet iid g = HashSet.map DamageableAssetId . HashMap.keysSet $ assets'
   where
    assetIds = getSet iid g
    assets' = HashMap.filterWithKey
      (\k v -> k `elem` assetIds && isDamageable v)
      (g ^. assets)

instance HasSet EnemyId LocationId Game where
  getSet lid g = getSet () location
    where location = fromJustNote "No location" $ g ^? locations . ix lid

instance HasSet InvestigatorId () Game where
  getSet _ = HashMap.keysSet . view investigators

instance HasSet InvestigatorId LocationId Game where
  getSet lid g = getSet () location
    where location = fromJustNote "No location" $ g ^? locations . ix lid

instance HasQueue Game where
  messageQueue = lens giMessages $ \m x -> m { giMessages = x }

createEnemy :: MonadIO m => CardCode -> m (EnemyId, Enemy)
createEnemy cardCode = do
  eid <- liftIO $ EnemyId <$> nextRandom
  pure (eid, lookupEnemy cardCode eid)

createAsset :: MonadIO m => CardCode -> m (AssetId, Asset)
createAsset cardCode = do
  aid <- liftIO $ AssetId <$> nextRandom
  pure (aid, lookupAsset cardCode aid)

createTreachery :: MonadIO m => CardCode -> m (TreacheryId, Treachery)
createTreachery cardCode = do
  tid <- liftIO $ TreacheryId <$> nextRandom
  pure (tid, lookupTreachery cardCode tid)

locationFor :: InvestigatorId -> Game -> LocationId
locationFor iid g = locationOf investigator
 where
  investigator =
    fromJustNote "could not find investigator" $ g ^? investigators . ix iid

drawToken :: MonadIO m => Game -> m (Token, [Token])
drawToken Game {..} = do
  let tokens = coerce giChaosBag
  n <- liftIO $ randomRIO (0, length tokens - 1)
  let token = fromJustNote "impossible" $ tokens !!? n
  pure (token, without n tokens)

runGameMessage
  :: (HasQueue env, MonadReader env m, MonadIO m) => Message -> Game -> m Game
runGameMessage msg g = case msg of
  PlaceLocation lid -> do
    unshiftMessage (PlacedLocation lid)
    pure $ g & locations . at lid ?~ lookupLocation lid
  SetEncounterDeck encounterDeck' -> pure $ g & encounterDeck .~ encounterDeck'
  RemoveEnemy eid -> pure $ g & enemies %~ HashMap.delete eid
  RemoveLocation lid -> pure $ g & locations %~ HashMap.delete lid
  NextAgenda aid1 aid2 ->
    pure $ g & agendas %~ HashMap.delete aid1 & agendas %~ HashMap.insert
      aid2
      (lookupAgenda aid2)
  NextAct aid1 aid2 ->
    pure $ g & acts %~ HashMap.delete aid1 & acts %~ HashMap.insert
      aid2
      (lookupAct aid2)
  AddAct aid -> pure $ g & acts . at aid ?~ lookupAct aid
  AddAgenda aid -> pure $ g & agendas . at aid ?~ lookupAgenda aid
  SkillTestEnds -> pure $ g & skillCheck .~ Nothing
  ReturnTokens tokens -> pure $ g & chaosBag %~ (tokens <>)
  InvestigatorPlayCard iid cardCode _ -> do
    let
      card =
        fromJustNote "Could not find card" $ HashMap.lookup cardCode allCards
    case card of
      PlayerCard pc -> case pcCardType pc of
        AssetType -> do
          let
            builder = fromJustNote "could not find asset"
              $ HashMap.lookup cardCode allAssets
          aid <- liftIO $ AssetId <$> nextRandom
          unshiftMessage (InvestigatorPlayAsset iid aid)
          pure $ g & assets %~ HashMap.insert aid (builder aid)
        EventType -> do
          let
            eventMessages =
              ($ iid) . fromJustNote "could not find event" $ HashMap.lookup
                cardCode
                allEvents
          g <$ unshiftMessages eventMessages
        _ -> pure g
      EncounterCard _ -> pure g
  EnemyWillAttack iid eid -> do
    mNextMessage <- peekMessage
    case mNextMessage of
      Just (EnemyAttacks as) -> do
        _ <- popMessage
        unshiftMessage (EnemyAttacks (EnemyAttack iid eid : as))
      Just aoo@(CheckAttackOfOpportunity _) -> do
        _ <- popMessage
        unshiftMessage msg
        unshiftMessage aoo
      Just (EnemyWillAttack iid2 eid2) -> do
        _ <- popMessage
        unshiftMessage
          (EnemyAttacks [EnemyAttack iid eid, EnemyAttack iid2 eid2])
      _ -> unshiftMessage (EnemyAttack iid eid)
    pure g
  EnemyAttacks as -> do
    mNextMessage <- peekMessage
    case mNextMessage of
      Just (EnemyAttacks as2) -> do
        _ <- popMessage
        unshiftMessage (EnemyAttacks $ as ++ as2)
      Just aoo@(CheckAttackOfOpportunity _) -> do
        _ <- popMessage
        unshiftMessage msg
        unshiftMessage aoo
      Just (EnemyWillAttack iid2 eid2) -> do
        _ <- popMessage
        unshiftMessage (EnemyAttacks (EnemyAttack iid2 eid2 : as))
      _ -> unshiftMessage (Ask . ChooseOneAtATime $ map ChoiceResult as)
    pure g
  DiscardAsset aid -> do
    let asset = g ^?! assets . ix aid
    unshiftMessage (AssetDiscarded aid (getCardCode asset))
    pure $ g & assets %~ HashMap.delete aid
  AssetDefeated aid -> do
    let asset = g ^?! assets . ix aid
    unshiftMessage (AssetDiscarded aid (getCardCode asset))
    pure $ g & assets %~ HashMap.delete aid
  EnemyDefeated eid _ _ ->
    let
      enemy = g ^?! enemies . ix eid
      encounterCard = fromJustNote "missing"
        $ HashMap.lookup (getCardCode enemy) allEncounterCards
    in pure
      $ g
      & (enemies %~ HashMap.delete eid)
      & (discard %~ (encounterCard :))
  BeginInvestigation -> pure $ g & phase .~ InvestigationPhase
  EndInvestigation -> g <$ pushMessage BeginEnemy
  BeginEnemy -> do
    pushMessages [HuntersMove, EnemiesAttack, EndEnemy]
    pure $ g & phase .~ EnemyPhase
  EndEnemy -> g <$ pushMessage BeginUpkeep
  BeginUpkeep -> do
    pushMessages
      [ReadyExhausted, AllDrawCardAndResource, AllCheckHandSize, EndUpkeep]
    pure $ g & phase .~ UpkeepPhase
  EndUpkeep -> g <$ pushMessages [EndRoundWindow, EndRound]
  EndRound -> g <$ pushMessage BeginRound
  BeginRound -> g <$ pushMessage BeginMythos
  BeginMythos -> g <$ pushMessages
    [ PlaceDoomOnAgenda
    , AdvanceAgendaIfThresholdSatisfied
    , AllDrawEncounterCard
    , EndMythos
    ]
  EndMythos -> g <$ pushMessage BeginInvestigation
  BeginSkillCheck iid skillType difficulty skillValue onSuccess onFailure -> do
    (token, chaosBag') <- drawToken g
    unshiftMessage (ResolveToken token iid skillValue)
    unshiftMessage (DrawToken token)
    pure
      $ g
      & (skillCheck
        ?~ SkillCheck
             iid
             skillType
             difficulty
             onSuccess
             onFailure
             DrawOne
             ResolveAll
             []
             Unrun
        )
      & (chaosBag .~ chaosBag')
  DrawAnotherToken iid skillValue _ -> do
    (token, chaosBag') <- drawToken g
    unshiftMessage (ResolveToken token iid skillValue)
    unshiftMessage (DrawToken token)
    pure $ g & chaosBag .~ chaosBag'
  ResolveToken Token.PlusOne _ skillValue -> g <$ runCheck (skillValue + 1)
  ResolveToken Token.Zero _ skillValue -> g <$ runCheck skillValue
  ResolveToken Token.MinusOne _ skillValue -> g <$ runCheck (skillValue - 1)
  ResolveToken Token.MinusTwo _ skillValue -> g <$ runCheck (skillValue - 2)
  ResolveToken Token.MinusThree _ skillValue -> g <$ runCheck (skillValue - 3)
  ResolveToken Token.MinusFour _ skillValue -> g <$ runCheck (skillValue - 4)
  ResolveToken Token.MinusFive _ skillValue -> g <$ runCheck (skillValue - 5)
  ResolveToken Token.MinusSix _ skillValue -> g <$ runCheck (skillValue - 6)
  ResolveToken Token.MinusSeven _ skillValue -> g <$ runCheck (skillValue - 7)
  ResolveToken Token.MinusEight _ skillValue -> g <$ runCheck (skillValue - 8)
  ResolveToken Token.AutoFail _ _ -> g <$ unshiftMessage FailSkillCheck
  CreateStoryAssetAt cardCode lid -> do
    (assetId', asset') <- createAsset cardCode
    unshiftMessage (AddAssetAt assetId' lid)
    pure $ g & assets . at assetId' ?~ asset'
  CreateEnemyAt cardCode lid -> do
    (enemyId', enemy') <- createEnemy cardCode
    unshiftMessage (EnemySpawn lid enemyId')
    pure $ g & enemies . at enemyId' ?~ enemy'
  FindAndDrawEncounterCard iid matcher -> do
    let
      matchingDiscards =
        filter (encounterCardMatch matcher . snd) (zip [1 ..] (g ^. discard))
    let
      matchingDeckCards = filter
        (encounterCardMatch matcher . snd)
        (zip [1 ..] (g ^. encounterDeck))
    g <$ unshiftMessage
      (Ask
      $ ChooseOne
      $ map
          (ChoiceResult . FoundAndDrewEncounterCard iid FromDiscard)
          matchingDiscards
      <> map
           (ChoiceResult . FoundAndDrewEncounterCard iid FromEncounterDeck)
           matchingDeckCards
      )
  FoundAndDrewEncounterCard iid cardSource (n, card) -> do
    let
      discard' = case cardSource of
        FromDiscard -> without n (g ^. discard)
        _ -> g ^. discard
      encounterDeck' = case cardSource of
        FromEncounterDeck -> without n (g ^. encounterDeck)
        _ -> g ^. encounterDeck
    shuffled <- liftIO $ shuffleM encounterDeck'
    unshiftMessage (InvestigatorDrewEncounterCard iid card)
    pure $ g & encounterDeck .~ shuffled & discard .~ discard'
  DiscardEncounterUntilFirst source matcher -> do
    let
      (discards, remainingDeck) =
        break (encounterCardMatch matcher) (g ^. encounterDeck)
    case remainingDeck of
      [] -> do
        unshiftMessage (RequestedEncounterCard source Nothing)
        encounterDeck' <- liftIO $ shuffleM (discards <> g ^. discard)
        pure $ g & encounterDeck .~ encounterDeck' & discard .~ mempty
      (x : xs) -> do
        unshiftMessage (RequestedEncounterCard source (Just x))
        pure $ g & encounterDeck .~ xs & discard %~ (reverse discards <>)
  InvestigatorDrawEncounterCard iid -> do
    let (card : encounterDeck') = g ^. encounterDeck
    unshiftMessage (InvestigatorDrewEncounterCard iid card)
    pure $ g & encounterDeck .~ encounterDeck'
  InvestigatorDrewEncounterCard iid card -> case ecCardType card of
    EnemyType -> do
      (enemyId', enemy') <- createEnemy (ecCardCode card)
      let lid = locationFor iid g
      unshiftMessage (InvestigatorDrawEnemy iid lid enemyId')
      pure $ g & (enemies . at enemyId' ?~ enemy')
    TreacheryType -> do
      (treacheryId', treachery') <- createTreachery (ecCardCode card)
      unshiftMessage (RunTreachery iid treacheryId')
      pure $ g & (treacheries . at treacheryId' ?~ treachery')
    LocationType -> pure g
  DiscardTreachery tid ->
    let
      treachery = fromJustNote "missing treachery" $ g ^? treacheries . ix tid
      card = fromJustNote "missing card"
        $ HashMap.lookup (getCardCode treachery) allEncounterCards
    in pure $ g & treacheries %~ HashMap.delete tid & discard %~ (card :)
  _ -> pure g

instance RunMessage Game Game where
  runMessage msg g =
    traverseOf scenario (runMessage msg) g
      >>= traverseOf (acts . traverse) (runMessage msg)
      >>= traverseOf (agendas . traverse) (runMessage msg)
      >>= traverseOf (treacheries . traverse) (runMessage msg)
      >>= traverseOf (locations . traverse) (runMessage msg)
      >>= traverseOf (enemies . traverse) (runMessage msg)
      >>= traverseOf (assets . traverse) (runMessage msg)
      >>= traverseOf (skillCheck . traverse) (runMessage msg)
      >>= traverseOf (investigators . traverse) (runMessage msg)
      >>= runGameMessage msg

toExternalGame :: MonadIO m => Game -> m GameJson
toExternalGame Game {..} = do
  queue <- liftIO $ readIORef giMessages
  pure $ GameJson
    { gMessages = queue
    , gSeed = giSeed
    , gScenario = giScenario
    , gLocations = giLocations
    , gInvestigators = giInvestigators
    , gEnemies = giEnemies
    , gAssets = giAssets
    , gActiveInvestigatorId = giActiveInvestigatorId
    , gLeadInvestigatorId = giLeadInvestigatorId
    , gPhase = giPhase
    , gEncounterDeck = giEncounterDeck
    , gDiscard = giDiscard
    , gSkillCheck = giSkillCheck
    , gChaosBag = giChaosBag
    , gActs = giActs
    , gAgendas = giAgendas
    , gTreacheries = giTreacheries
    }

toInternalGame' :: IORef [Message] -> GameJson -> Game
toInternalGame' ref GameJson {..} = Game
  { giMessages = ref
  , giSeed = gSeed
  , giScenario = gScenario
  , giLocations = gLocations
  , giInvestigators = gInvestigators
  , giEnemies = gEnemies
  , giAssets = gAssets
  , giActiveInvestigatorId = gActiveInvestigatorId
  , giLeadInvestigatorId = gLeadInvestigatorId
  , giPhase = gPhase
  , giEncounterDeck = gEncounterDeck
  , giDiscard = gDiscard
  , giSkillCheck = gSkillCheck
  , giChaosBag = gChaosBag
  , giAgendas = gAgendas
  , giTreacheries = gTreacheries
  , giActs = gActs
  }

runMessages :: MonadIO m => Game -> m (Maybe Question, GameJson)
runMessages g = flip runReaderT g $ do
  liftIO $ readIORef (giMessages g) >>= pPrint
  mmsg <- popMessage
  case mmsg of
    Nothing -> case giPhase g of
      ResolutionPhase -> (Nothing, ) <$> toExternalGame g
      MythosPhase -> (Nothing, ) <$> toExternalGame g
      EnemyPhase -> (Nothing, ) <$> toExternalGame g
      UpkeepPhase -> (Nothing, ) <$> toExternalGame g
      InvestigationPhase -> if hasEndedTurn (activeInvestigator g)
        then pushMessage EndInvestigation >> runMessages g
        else
          pushMessages
              [ PrePlayerWindow
              , PlayerWindow $ g ^. activeInvestigatorId
              , PostPlayerWindow
              ]
            >> runMessages g
    Just msg -> case msg of
      Ask q -> (Just q, ) <$> toExternalGame g
      _ -> runMessage msg g >>= runMessages

keepAsking :: forall a m . (Show a, Read a, MonadIO m) => String -> m a
keepAsking s = do
  putStr $ pack s
  liftIO $ hFlush stdout
  mresult <- readMaybe @a . unpack <$> getLine
  case mresult of
    Nothing -> keepAsking s
    Just a -> pure a

extract :: Int -> [a] -> (Maybe a, [a])
extract n xs =
  let a = xs !!? (n - 1) in (a, [ x | (i, x) <- zip [1 ..] xs, i /= n ])

handleQuestion :: MonadIO m => GameJson -> Question -> m [Message]
handleQuestion _ = \case
  ChoiceResult msg -> pure [msg]
  ChoiceResults msgs -> pure msgs
  q@(ChooseToDoAll msgs) -> do
    putStr $ pack $ show q
    liftIO $ hFlush stdout
    resp <- getLine
    if "n" `isPrefixOf` toLower resp then pure [] else pure msgs
  q@(ChooseTo msg) -> do
    putStr $ pack $ show q
    liftIO $ hFlush stdout
    resp <- getLine
    if "n" `isPrefixOf` toLower resp then pure [] else pure [msg]
  ChooseOne [] -> pure []
  ChooseOne qs -> do
    i <- keepAsking @Int
      ("Choose one:\n\n" <> unlines (map show $ zip @_ @Int [1 ..] qs))
    pure $ maybeToList $ Ask <$> qs !!? (i - 1)
  ChooseOneAtATime [] -> pure []
  ChooseOneAtATime qs -> do
    i <- keepAsking @Int
      ("Choose one at a time:\n\n" <> unlines (map show $ zip @_ @Int [1 ..] qs)
      )
    let (mq, qs') = extract i qs
    case mq of
      Just q' -> pure [Ask q', Ask $ ChooseOneAtATime qs']
      Nothing -> pure []

runGame :: MonadIO m => Game -> m GameJson
runGame g = do
  let ref = giMessages g
  (mQuestion, gameJson) <- runMessages g
  pPrint gameJson
  messages <- maybe (pure []) (handleQuestion gameJson) mQuestion
  modifyIORef' ref (messages <>)
  messages' <- readIORef ref
  if null messages'
    then pure gameJson
    else runGame $ toInternalGame' ref gameJson
