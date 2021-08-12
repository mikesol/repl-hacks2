module WAGSI.LiveCodeHere.Stash where

import WAGSI.Plumbing.FFIStuff (Stash, stashable)

stash :: Stash
stash =
  stashable
    { buffers:
        { kick1: "https://freesound.org/data/previews/171/171104_2394245-hq.mp3"
        , sideStick: "https://freesound.org/data/previews/209/209890_3797507-hq.mp3"
        , snare: "https://freesound.org/data/previews/495/495777_10741529-hq.mp3"
        , clap: "https://freesound.org/data/previews/183/183102_2394245-hq.mp3"
        , snareRoll: "https://freesound.org/data/previews/50/50710_179538-hq.mp3"
        , kick2: "https://freesound.org/data/previews/148/148634_2614600-hq.mp3"
        , closedHH: "https://freesound.org/data/previews/269/269720_4965320-hq.mp3"
        , shaker: "https://freesound.org/data/previews/432/432205_8738244-hq.mp3"
        , openHH: "https://freesound.org/data/previews/416/416249_8218607-hq.mp3"
        , tamb: "https://freesound.org/data/previews/207/207925_19852-hq.mp3"
        , crash: "https://freesound.org/data/previews/528/528490_3797507-hq.mp3"
        , ride: "https://freesound.org/data/previews/270/270138_1125482-hq.mp3"
        , trumpet: "https://freesound.org/data/previews/331/331146_3931578-hq.mp3"
        , pad: "https://freesound.org/data/previews/110/110212_1751865-hq.mp3"
        , impulse0: "https://freesound.org/data/previews/382/382907_2812020-hq.mp3" 
        }
    , periodicWaves: {}
    , floatArrays: {}
    }
