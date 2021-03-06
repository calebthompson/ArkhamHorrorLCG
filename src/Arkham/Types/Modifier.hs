module Arkham.Types.Modifier
  ( sourceOfModifier
  , Modifier(..)
  , ActionTarget(..)
  )
where

import Arkham.Types.Action
import Arkham.Types.Card
import Arkham.Types.SkillType
import Arkham.Types.Source
import ClassyPrelude
import Data.Aeson

sourceOfModifier :: Modifier -> Source
sourceOfModifier (ActionCostOf _ _ s) = s
sourceOfModifier (CannotPlay _ s) = s
sourceOfModifier (SkillModifier _ _ s) = s
sourceOfModifier (DamageTaken _ s) = s

data Modifier
  = ActionCostOf ActionTarget Int Source
  | CannotPlay [PlayerCardType] Source
  | SkillModifier SkillType Int Source
  | DamageTaken Int Source
  deriving stock (Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data ActionTarget
  = FirstOneOf [Action]
  | IsAction Action
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

