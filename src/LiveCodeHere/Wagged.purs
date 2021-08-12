module WAGSI.LiveCodeHere.Wagged where

import Prelude
import Math
import WAGS.Create.Optionals
import Record.Builder as Record
import Type.Row (type (+))
import WAGS.Lib.Cofree (heads, tails)
import WAGSI.LiveCodeHere.Room0 as Room0
import WAGSI.LiveCodeHere.Room1 as Room1
import WAGSI.LiveCodeHere.Room2 as Room2
import WAGSI.LiveCodeHere.Room3 as Room3
import WAGSI.LiveCodeHere.Room4 as Room4
import WAGSI.LiveCodeHere.Room5 as Room5
import WAGSI.Plumbing.Hack ((/@\))
import WAGSI.Plumbing.Types (Extern)

-- change this to make sound
-- for example, you can try:
-- a /@\ speaker { unit0: gain (cos (pi * e.time) * -0.02 + 0.02) { osc0: sinOsc 440.0 } }
type Acc
  = (
    | Room0.Acc + Room1.Acc + Room2.Acc + Room3.Acc + Room4.Acc + Room5.Acc + ()
    )

wagsi (e :: Extern) (a :: { | Acc }) =
  tailed
    /@\ speaker { masterGain: gain 0.5 ( Record.build
            ( Record.union (Room0.graph e headz)
                >>> Record.union (Room1.graph e headz)
                >>> Record.union (Room2.graph e headz)
                >>> Record.union (Room3.graph e headz)
                >>> Record.union (Room4.graph e headz)
                >>> Record.union (Room5.graph e headz)
            )
            { zeros: constant 0.0 }
        ) }
        
  where
  actualizer = {}

  --------------------------------------------
  actualized =
    Record.build
      ( Record.union (Room0.actualizer e a)
          >>> Record.union (Room1.actualizer e a)
          >>> Record.union (Room2.actualizer e a)
          >>> Record.union (Room3.actualizer e a)
          >>> Record.union (Room4.actualizer e a)
          >>> Record.union (Room5.actualizer e a)
      )
      actualizer

  headz = heads actualized

  tailed = tails actualized
