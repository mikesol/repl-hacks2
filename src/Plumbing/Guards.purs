module WAGSI.Plumbing.Guards where

import Prelude

import Control.Monad.State (evalState, modify)
import Data.Array as Array
import Data.Compactable (compact)
import Data.Foldable (foldl, fold)
import Data.Function (on)
import Data.Int (toNumber)
import Data.Lens (over, traversed)
import Data.Lens.Iso.Newtype (unto)
import Data.Lens.Lens.Tuple (_2)
import Data.List (List(..), sortBy)
import Data.Map as Map
import Data.Newtype (unwrap)
import Data.Set as Set
import Data.Traversable (traverse)
import Data.Tuple (fst, snd, swap)
import Data.Tuple.Nested (type (/\), (/\))
import WAGS.Lib.Tidal.Types (TheFuture(..))
import WAGS.Lib.Tidal.Util (d2s, v2s)
import WAGSI.Plumbing.Types (WhatsNext)

epsilon = 0.2 :: Number

asFofCycles :: List (Int /\ WhatsNext) -> WhatsNext -> { clockTime :: Number } -> WhatsNext
asFofCycles = asFofTime
  <<< map swap
  <<< flip evalState 0.0
  <<< traverse (traverse (modify <<< (+)))
  <<< map swap
  <<< map \(a /\ b) -> toNumber a * (unwrap (unwrap b).cycleDuration) /\ b

asFofTime :: List (Number /\ WhatsNext) -> WhatsNext -> { clockTime :: Number } -> WhatsNext
asFofTime a wn = go withPreloads
  where
  sorted = sortBy (compare `on` fst) a
  makeSounds = \(TheFuture { sounds }) -> sounds
  makePreload = \(TheFuture { earth, wind, fire, air, heart, preload }) -> Set.toUnfoldable $ Set.fromFoldable preload
    <> fold (map v2s [ earth, wind, fire ])
    <> (Set.fromFoldable $ compact ((map <<< map) d2s [ air, heart ]))
  allPreloads =
    ( Array.fromFoldable
        $ join
        $ map makePreload (map snd sorted)
    )
      <> (Array.fromFoldable $ makePreload wn)
  allSounds = (foldl Map.union Map.empty $ map makeSounds (map snd sorted))
    `Map.union` (makeSounds wn)
  withPreloads = over (traversed <<< _2 <<< unto TheFuture)
    (_ { preload = allPreloads, sounds = allSounds })
    sorted
  go Nil _ = wn
  go (Cons (x /\ y) z) { clockTime } = if clockTime < (x - epsilon) then y else go z { clockTime }

