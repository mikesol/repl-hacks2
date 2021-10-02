module WAGSI.Main where

import Prelude

import Control.Comonad.Cofree (Cofree, (:<))
import Control.Monad.Error.Class (try)
import Data.Either (hush)
import Data.Foldable (for_)
import Data.Maybe (Maybe(..), maybe)
import Data.Tuple (fst, snd)
import Data.Tuple.Nested ((/\), type (/\))
import Data.Typelevel.Num (class Pos)
import Data.Vec as V
import Effect (Effect)
import Effect.Aff.Class (class MonadAff)
import Effect.Class (class MonadEffect)
import Effect.Ref as Ref
import FRP.Behavior (Behavior)
import FRP.Event (Event, EventIO, create, subscribe)
import FRP.Event as E
import FRP.Event.Time (interval)
import Halogen (SubscriptionId)
import Halogen as H
import Halogen.Aff (awaitBody, runHalogenAff)
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Subscription as HS
import Halogen.VDom.Driver (runUI)
import Random.LCG (randomSeed)
import Test.QuickCheck.Gen (evalGen)
import WAGS.Interpret (close, context, defaultFFIAudio, makePeriodicWave, makeUnitCache)
import WAGS.Lib.Learn (FullSceneBuilder(..))
import WAGS.Run (Run, run)
import WAGS.WebAPI (AudioContext, BrowserAudioBuffer, BrowserPeriodicWave)
import WAGSI.Plumbing.Cycle (cycleLength, cycleToString)
import WAGSI.Plumbing.Download (HasOrLacks, ForwardBackwards)
import WAGSI.Plumbing.Example as Example
import WAGSI.Plumbing.Samples (Samples)
import WAGSI.Plumbing.Types (TheFuture(..))
import WAGSI.Plumbing.Tidal (djQuickCheck, openVoice)
import WAGSI.Plumbing.Engine (engine)
import WAGSI.Plumbing.WagsiMode (WagsiMode(..), wagsiMode)

main :: Effect Unit
main =
  runHalogenAff do
    body <- awaitBody
    runUI component unit body

type StashInfo
  = { buffers :: Array String, periodicWaves :: Array String, floatArrays :: Array String }

type State
  =
  { unsubscribe :: Effect Unit
  , unsubscribeFromHalogen :: Maybe SubscriptionId
  , audioCtx :: Maybe AudioContext
  , audioStarted :: Boolean
  , canStopAudio :: Boolean
  , triggerWorld ::
      Maybe
        ( Event { theFuture :: TheFuture } /\ Behavior
            { buffers :: { | Samples (Maybe ForwardBackwards) }
            , silence :: BrowserAudioBuffer
            }
        )
  , hasOrLacks :: Maybe (HasOrLacks)
  , loadingHack :: LoadingHack
  , djqc :: Maybe String
  , tick :: Maybe Int
  , doingGraphRendering :: Boolean
  }

data Action
  = Initialize
  | StartAudio
  | GraphRenderingDone
  | Tick (Maybe Int)
  | DJQC String
  | StopAudio

component :: forall query input output m. MonadEffect m => MonadAff m => H.Component query input output m
component =
  H.mkComponent
    { initialState
    , render
    , eval: H.mkEval $ H.defaultEval { initialize = Just Initialize, handleAction = handleAction }
    }

initialState :: forall input. input -> State
initialState _ =
  { unsubscribe: pure unit
  , audioCtx: Nothing
  , audioStarted: false
  , canStopAudio: false
  , loadingHack: Loading
  , triggerWorld: Nothing
  , tick: Nothing
  , djqc: Nothing
  , hasOrLacks: case wagsiMode of
      Example -> Example.hasOrLacks
      _ -> Nothing
  , unsubscribeFromHalogen: Nothing
  , doingGraphRendering: false
  }

data LoadingHack = Loading | Failed | Loaded

classes :: forall r p. Array String -> HP.IProp (class :: String | r) p
classes = HP.classes <<< map H.ClassName

render :: forall m. State -> H.ComponentHTML Action () m
render { audioStarted, canStopAudio, loadingHack, tick, djqc, doingGraphRendering } =
  HH.div [ classes [ "w-screen", "h-screen" ] ]
    [ HH.div [ classes [ "flex", "flex-col", "w-full", "h-full" ] ]
        [ HH.div [ classes [ "flex-grow" ] ] [ HH.div_ [] ]
        , HH.div [ classes [ "flex-grow-0", "flex", "flex-row" ] ]
            [ HH.div [ classes [ "flex-grow" ] ]
                []
            , HH.div [ classes [ "flex", "flex-col" ] ]
                case loadingHack of
                  Loading ->
                    [ HH.h1 [ classes [ "text-center", "text-3xl", "font-bold" ] ]
                        [ HH.text "Loading..." ]
                    , HH.p [ classes [ "text-center", "text-xl" ] ]
                        [ HH.text "This should take less than a minute.  If an error happens, we'll let you know." ]
                    ]
                  Failed ->
                    [ HH.p [ classes [ "text-center", "text-xl" ] ]
                        [ HH.text "Well, this is embarassing. We couldn't load your files. Please reload the page. If the error persists, please open an issue on https://github.com/mikesol/wagsi." ]
                    ]
                  Loaded ->
                    [ HH.h1 [ classes [ "text-center", "text-3xl", "font-bold" ] ]
                        [ HH.text $ case wagsiMode of
                            LiveCoding -> "wagsi - The Tidal Cycles jam"
                            DJQuickCheck -> "d j q u i c k c h e c k"
                            Example -> Example.title
                        ]
                    ]
                      <>
                        ( if doingGraphRendering then
                            [ HH.p [ classes [ "text-center", "text-xxl" ] ]
                                [ HH.text ("Setting phasers on stun (pre-rendering audio graphs)...") ]
                            ]
                          else []
                        )
                      <> maybe
                        ( maybe []
                            ( \v ->
                                [ HH.p [ classes [ "text-center", "text-xxl" ] ]
                                    [ HH.text ("Starting in " <> show v <> "s") ]
                                ]
                            )
                            tick
                        )
                        ( \v ->
                            [ HH.p [ classes [ "text-center", "text-xl" ] ]
                                [ HH.text "Now Playing (or soon-to-be-playing)" ]
                            , HH.p [ classes [ "text-center", "text-base", "font-mono" ] ]
                                [ HH.text v.djqc ]
                            , HH.p [ classes [ "text-center", "text-xl" ] ]
                                [ HH.text ("Next change in " <> show v.tick <> "s") ]
                            ]
                        )
                        ({ tick: _, djqc: _ } <$> tick <*> djqc)
                      <>
                        [ if not audioStarted then
                            HH.button
                              [ classes [ "text-2xl", "m-5", "bg-indigo-500", "p-3", "rounded-lg", "text-white", "hover:bg-indigo-400" ], HE.onClick \_ -> StartAudio ]
                              [ HH.text "Start audio" ]
                          else
                            HH.button
                              ([ classes [ "text-2xl", "m-5", "bg-pink-500", "p-3", "rounded-lg", "text-white", "hover:bg-pink-400" ] ] <> if canStopAudio then [ HE.onClick \_ -> StopAudio ] else [])
                              [ HH.text "Stop audio" ]
                        ]
            , HH.div [ classes [ "flex-grow" ] ] []
            ]
        , HH.div [ classes [ "flex-grow" ] ] []
        ]
    ]

makeOsc
  :: ∀ m s
   . MonadEffect m
  => Pos s
  => AudioContext
  -> (V.Vec s Number) /\ (V.Vec s Number)
  -> m BrowserPeriodicWave
makeOsc ctx o =
  H.liftEffect
    $ makePeriodicWave ctx (fst o) (snd o)

easingAlgorithm :: Cofree ((->) Int) Int
easingAlgorithm =
  let
    fOf initialTime = initialTime :< \adj -> fOf $ max 15 (initialTime - adj)
  in
    fOf 15

handleAction :: forall output m. MonadEffect m => MonadAff m => Action -> H.HalogenM State Action () output m Unit
handleAction = case _ of
  Tick tick -> do
    H.modify_ _ { tick = tick }
  DJQC djqc -> do
    H.modify_ _ { djqc = Just djqc }
  GraphRenderingDone -> do
    H.modify_ _ { doingGraphRendering = false }
  Initialize -> do
    ctx <- H.liftEffect context
    state <- H.get
    let FullSceneBuilder { triggerWorld } = engine state.hasOrLacks
    tw <- H.liftAff $ try (snd $ triggerWorld (ctx /\ pure (pure {} /\ pure {})))
    maybe (H.modify_ _ { loadingHack = Failed })
      (\triggerWorld -> H.modify_ _ { triggerWorld = Just triggerWorld, loadingHack = Loaded })
      (hush tw)
  StartAudio -> do
    handleAction StopAudio
    nextCycleEnds <- H.liftEffect $ Ref.new 0
    H.modify_ _ { audioStarted = true, canStopAudio = false, doingGraphRendering = true }
    { emitter, listener } <- H.liftEffect HS.create
    unsubscribeFromHalogen <- H.subscribe emitter
    tw <- H.gets _.triggerWorld
    state <- H.get
    { ctx, unsubscribeFromWags } <-
      H.liftAff do
        ctx <- H.liftEffect context
        unitCache <- H.liftEffect makeUnitCache
        let
          ffiAudio = defaultFFIAudio ctx unitCache
        let FullSceneBuilder { triggerWorld, piece } = engine state.hasOrLacks
        trigger' /\ world <- case tw of
          Nothing -> do
            snd $ triggerWorld (ctx /\ pure (pure {} /\ pure {}))
          Just ttww -> pure ttww
        { trigger, unsub } <- case wagsiMode of
          LiveCoding -> H.liftEffect $ do
            -- we prime the pump by pushing an empty future
            theFuture :: EventIO TheFuture <- create
            theFuture.push $ TheFuture { earth: openVoice, wind: openVoice, fire: openVoice }
            unsub <- subscribe trigger' (theFuture.push <<< _.theFuture)
            HS.notify listener GraphRenderingDone
            pure { trigger: { theFuture: _ } <$> theFuture.event, unsub }
          Example -> do
            let ivl = E.fold (const $ add 1) (interval 1000) (-2)
            theFuture :: EventIO TheFuture <- H.liftEffect create
            unsub <- H.liftEffect $ subscribe ivl \ck' -> case ck' of
              (-1) -> do
                HS.notify listener GraphRenderingDone
                HS.notify listener (Tick $ Just 1)
                theFuture.push $ TheFuture { earth: openVoice, wind: openVoice, fire: openVoice }
              0 -> HS.notify listener (Tick $ Nothing) *> theFuture.push Example.example
              _ -> pure unit
            pure { trigger: { theFuture: _ } <$> theFuture.event, unsub }
          DJQuickCheck -> do
            let ivl = E.fold (const $ add 1) (interval 1000) (-4)
            theFuture :: EventIO TheFuture <- H.liftEffect create
            unsub <- H.liftEffect $ subscribe ivl \ck' -> case ck' of
              (-3) -> do
                HS.notify listener GraphRenderingDone
                HS.notify listener (Tick $ Just 3)
                theFuture.push $ TheFuture { earth: openVoice, wind: openVoice, fire: openVoice }
              (-2) -> HS.notify listener (Tick $ Just 2)
              (-1) -> HS.notify listener (Tick $ Just 1)
              ck -> do
                nce <- Ref.read nextCycleEnds
                when (ck >= nce) do
                  seed <- randomSeed
                  let goDJ = evalGen djQuickCheck { newSeed: seed, size: 10 }
                  HS.notify listener (DJQC $ cycleToString goDJ.cycle)
                  theFuture.push goDJ.future
                  Ref.write (if cycleLength goDJ.cycle < 6 then ck + 6 else ck + 20) nextCycleEnds
                nce2 <- Ref.read nextCycleEnds
                HS.notify listener (Tick $ Just (nce2 - ck))
            pure { trigger: { theFuture: _ } <$> theFuture.event, unsub }
        unsubscribeFromWags <-
          H.liftEffect do
            usu <- subscribe
              (run trigger world { easingAlgorithm } ffiAudio piece)
              (\(_ :: Run Unit ()) -> pure unit) -- (Log.info <<< show)
            pure $ do
              _ <- usu
              _ <- unsub
              pure unit
        pure { ctx, unsubscribeFromWags }
    H.modify_
      _
        { unsubscribe = unsubscribeFromWags
        , audioCtx = Just ctx
        , canStopAudio = true
        , unsubscribeFromHalogen = Just unsubscribeFromHalogen
        }
  StopAudio -> do
    { unsubscribe, audioCtx, unsubscribeFromHalogen } <- H.get
    H.liftEffect unsubscribe
    for_ unsubscribeFromHalogen H.unsubscribe
    for_ audioCtx (H.liftEffect <<< close)
    H.modify_ _ { unsubscribe = pure unit, audioCtx = Nothing, audioStarted = false, canStopAudio = false, tick = Nothing, djqc = Nothing }
