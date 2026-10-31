---- MODULE MCOrder ----
(***************************************************************************)
(* A small model of Order: a body, two doors, a wheel of a rim and a tire  *)
(* (a smaller assembly), and a seat from another factory, with two        *)
(* workers, a truck of two items, and a warehouse of 6 bytes. MCOrder.cfg *)
(* checks it; MCOrderFault.cfg checks the fault model, where the checker   *)
(* must find two workers on one task.                                      *)
(***************************************************************************)
EXTENDS Order, TLC

MCItems == {"body", "door", "rim", "tire", "seat"}
MCSize == ("body" :> 3) @@ ("door" :> 1) @@ ("rim" :> 1) @@ ("tire" :> 1) @@ ("seat" :> 0)
MCNeed == ("body" :> 1) @@ ("door" :> 2) @@ ("rim" :> 1) @@ ("tire" :> 1) @@ ("seat" :> 0)
MCOrdered == ("body" :> 0) @@ ("door" :> 0) @@ ("rim" :> 0) @@ ("tire" :> 0) @@ ("seat" :> 1)
MCTasks == {"body", "door_left", "door_right", "wheel/rim", "wheel/tire", "wheel/order", "wheel", "seat"}
MCWaits ==
    ("body" :> {}) @@ ("door_left" :> {"body"}) @@ ("door_right" :> {"body"})
    @@ ("wheel/rim" :> {}) @@ ("wheel/tire" :> {"wheel/rim"})
    @@ ("wheel/order" :> {"wheel/rim", "wheel/tire"}) @@ ("wheel" :> {"body", "wheel/order"})
    @@ ("seat" :> {"body"})
MCUses ==
    ("body" :> "body") @@ ("door_left" :> "door") @@ ("door_right" :> "door")
    @@ ("wheel/rim" :> "rim") @@ ("wheel/tire" :> "tire")
    @@ ("wheel/order" :> "") @@ ("wheel" :> "") @@ ("seat" :> "seat")
MCWorkers == {"dung", "em"}
====
