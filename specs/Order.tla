---- MODULE Order ----
(***************************************************************************)
(* The flow of one order in the world (docs/world.md): a supplier fills   *)
(* the warehouse, the storekeeper picks the parts, the driver carries      *)
(* them on the truck to the factory, the workers do the tasks of the plan, *)
(* the files of the model go into the warehouse, and the customer gets     *)
(* them. An item of another family (a wheel, a seat) comes from the        *)
(* factory of its family, by its own truck, to the dock of the factory.    *)
(* World.Run makes this flow with processes, and the log of a run          *)
(* replays as a behavior of this module (World.Spec).                      *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
    Items,      \* the names of the parts of the order
    Size,       \* Size[i]: the bytes of one item i
    Need,       \* Need[i]: the count of the item i that the order needs
    Ordered,    \* Ordered[i]: the count of the item i from other factories
    Limit,      \* the size of the warehouse, in bytes
    Capacity,   \* the count of items that the truck carries
    Tasks,      \* the ids of the tasks of the plan
    Waits,      \* Waits[t]: the tasks that the task t waits for
    Uses,       \* Uses[t]: the item that the task t takes from the dock, or ""
    Workers,    \* the names of the workers
    ModelSize,  \* the bytes of the files of the finished model
    Guard       \* FALSE: the fault model, where a task can start twice

VARIABLES
    supplied,   \* the count of each item from the supplier
    received,   \* the count of each item from other factories
    stock,      \* the count of each item in the warehouse
    picked,     \* the count of each item at the dock of the warehouse
    load,       \* the count of each item on the truck
    truck,      \* where the truck is
    dock,       \* the count of each item at the dock of the factory
    started,    \* the tasks that started
    done,       \* the tasks that are done
    busy,       \* busy[w]: the task of the worker w, or ""
    phase       \* "build", "done" (the files), "stored", "delivered"

vars == <<supplied, received, stock, picked, load, truck, dock, started, done, busy, phase>>

Places == {"warehouse", "to_factory", "factory", "to_warehouse"}

RECURSIVE Sum(_, _)
Sum(f, S) == IF S = {} THEN 0
             ELSE LET x == CHOOSE x \in S : TRUE IN f[x] + Sum(f, S \ {x})

StockBytes == Sum([i \in Items |-> stock[i] * Size[i]], Items)
ModelBytes == IF phase \in {"stored", "delivered"} THEN ModelSize ELSE 0
LoadCount == Sum(load, Items)
UsedCount(i) == Cardinality({t \in started : Uses[t] = i})

Init ==
    /\ supplied = [i \in Items |-> 0]
    /\ received = [i \in Items |-> 0]
    /\ stock = [i \in Items |-> 0]
    /\ picked = [i \in Items |-> 0]
    /\ load = [i \in Items |-> 0]
    /\ truck = "warehouse"
    /\ dock = [i \in Items |-> 0]
    /\ started = {}
    /\ done = {}
    /\ busy = [w \in Workers |-> ""]
    /\ phase = "build"

\* The supplier puts n items into the warehouse: only what the order
\* needs, and only when they fit.
Supply(i, n) ==
    /\ n \in 1..(Need[i] - supplied[i])
    /\ StockBytes + ModelBytes + n * Size[i] <= Limit
    /\ supplied' = [supplied EXCEPT ![i] = @ + n]
    /\ stock' = [stock EXCEPT ![i] = @ + n]
    /\ UNCHANGED <<received, picked, load, truck, dock, started, done, busy, phase>>

\* The truck of another factory brings n items of an order of the factory
\* to its dock.
Receive(i, n) ==
    /\ n \in 1..(Ordered[i] - received[i])
    /\ received' = [received EXCEPT ![i] = @ + n]
    /\ dock' = [dock EXCEPT ![i] = @ + n]
    /\ UNCHANGED <<supplied, stock, picked, load, truck, started, done, busy, phase>>

\* The storekeeper takes n items out of the store, to its dock.
Pick(i, n) ==
    /\ n \in 1..stock[i]
    /\ stock' = [stock EXCEPT ![i] = @ - n]
    /\ picked' = [picked EXCEPT ![i] = @ + n]
    /\ UNCHANGED <<supplied, received, load, truck, dock, started, done, busy, phase>>

\* The driver loads n items on the truck at the warehouse.
Load(i, n) ==
    /\ truck = "warehouse"
    /\ n \in 1..picked[i]
    /\ LoadCount + n <= Capacity
    /\ picked' = [picked EXCEPT ![i] = @ - n]
    /\ load' = [load EXCEPT ![i] = @ + n]
    /\ UNCHANGED <<supplied, received, stock, truck, dock, started, done, busy, phase>>

\* The truck leaves a place: the warehouse with a load, the factory empty.
Depart(from) ==
    /\ truck = from
    /\ \/ from = "warehouse" /\ LoadCount > 0 /\ truck' = "to_factory"
       \/ from = "factory" /\ LoadCount = 0 /\ truck' = "to_warehouse"
    /\ UNCHANGED <<supplied, received, stock, picked, load, dock, started, done, busy, phase>>

\* The truck arrives at the end of the road.
Arrive(to) ==
    /\ \/ truck = "to_factory" /\ to = "factory"
       \/ truck = "to_warehouse" /\ to = "warehouse"
    /\ truck' = to
    /\ UNCHANGED <<supplied, received, stock, picked, load, dock, started, done, busy, phase>>

\* The driver unloads n items at the dock of the factory.
Unload(i, n) ==
    /\ truck = "factory"
    /\ n \in 1..load[i]
    /\ load' = [load EXCEPT ![i] = @ - n]
    /\ dock' = [dock EXCEPT ![i] = @ + n]
    /\ UNCHANGED <<supplied, received, stock, picked, truck, started, done, busy, phase>>

\* A free worker starts a task: each task that it waits for is done, and
\* its part is at the dock. Guard keeps a task from a second start.
Start(w, t) ==
    /\ busy[w] = ""
    /\ Guard => t \notin started
    /\ Waits[t] \subseteq done
    /\ IF Uses[t] = "" THEN TRUE ELSE dock[Uses[t]] > 0
    /\ dock' = IF Uses[t] = "" THEN dock ELSE [dock EXCEPT ![Uses[t]] = @ - 1]
    /\ started' = started \cup {t}
    /\ busy' = [busy EXCEPT ![w] = t]
    /\ UNCHANGED <<supplied, received, stock, picked, load, truck, done, phase>>

\* The worker ends its task.
Finish(w, t) ==
    /\ t /= "" /\ busy[w] = t
    /\ done' = done \cup {t}
    /\ busy' = [busy EXCEPT ![w] = ""]
    /\ UNCHANGED <<supplied, received, stock, picked, load, truck, dock, started, phase>>

\* The foreman makes the files of the model when each task is done.
ModelDone ==
    /\ phase = "build" /\ done = Tasks /\ \A w \in Workers : busy[w] = ""
    /\ phase' = "done"
    /\ UNCHANGED <<supplied, received, stock, picked, load, truck, dock, started, done, busy>>

\* The storekeeper puts the files of the model into the warehouse.
StoreModel ==
    /\ phase = "done"
    /\ StockBytes + ModelSize <= Limit
    /\ phase' = "stored"
    /\ UNCHANGED <<supplied, received, stock, picked, load, truck, dock, started, done, busy>>

\* The customer gets the files.
Deliver ==
    /\ phase = "stored"
    /\ phase' = "delivered"
    /\ UNCHANGED <<supplied, received, stock, picked, load, truck, dock, started, done, busy>>

\* A delivered order stays delivered: no deadlock at the end.
Finished == phase = "delivered" /\ UNCHANGED vars

Next ==
    \/ \E i \in Items, n \in 1..Limit : Supply(i, n) \/ Pick(i, n) \/ Load(i, n) \/ Unload(i, n)
    \/ \E i \in Items : \E n \in 1..Ordered[i] : Receive(i, n)
    \/ \E p \in Places : Depart(p) \/ Arrive(p)
    \/ \E w \in Workers, t \in Tasks : Start(w, t) \/ Finish(w, t)
    \/ ModelDone \/ StoreModel \/ Deliver \/ Finished

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

\* --- Invariants --------------------------------------------------------

\* The warehouse never holds more than its size.
InLimit == StockBytes + ModelBytes <= Limit

\* An item is at one place only: in the store, at a dock, on the truck,
\* or in the model. None is lost, and none comes from nowhere: from the
\* supplier or from another factory.
Conservation ==
    \A i \in Items :
        supplied[i] + received[i] = stock[i] + picked[i] + load[i] + dock[i] + UsedCount(i)

\* The truck never carries more than its capacity.
InCapacity == LoadCount <= Capacity

\* Two workers never do one task.
OneWorkerOneTask ==
    \A v, w \in Workers : v /= w /\ busy[v] /= "" => busy[v] /= busy[w]

\* A task starts only after each task that it waits for is done.
WaitsFirst == \A t \in started : Waits[t] \subseteq done

\* --- Liveness ----------------------------------------------------------

\* Each order is delivered in the end.
Delivers == <>(phase = "delivered")
====
