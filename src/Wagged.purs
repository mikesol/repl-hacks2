module Wagged where

import Prelude
import Math
import WAGS.Create.Optionals

import Wagsi.Types (Extern)
import Hack ((/@\))

-- change this to make sound
-- for example, you can try:
-- a /@\ speaker { unit0: gain (cos (pi * e.time) * -0.02 + 0.02) { osc0: sinOsc 440.0 } }

wagsi (e :: Extern) (a :: {}) = a /@\ speaker { toSpeaker: constant 0.0 }