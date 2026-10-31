defmodule World.RunTest do
  use ExUnit.Case, async: true

  alias World.{Clock, Log, Plan, Run, Stock}
  alias World.Furniture.Seats
  alias World.People.{Foreman, Storekeeper}

  @moduletag :tmp_dir

  test "an order of the van: the people make it, its log is in order, and it replays in the specification", %{
    tmp_dir: dir
  } do
    run = Run.start()
    van = World.Vehicles.FordTransit.model()
    assert {:ok, %{from: :factory} = result} = Run.order(run, van, "van-1")
    log = Run.log(run)
    events = Log.events(log)
    assert Log.check(log) == :ok

    # One start and one end of each task of the plan, at the stations of the line.
    van_events = Enum.filter(events, &(&1.order == "van-1"))
    kinds = Enum.frequencies_by(van_events, & &1.kind)
    assert kinds["task_started"] == length(result.plan.tasks) and kinds["task_done"] == length(result.plan.tasks)
    assert kinds["delivered"] == 1 and kinds["model_done"] == 1
    assert byte_size(result.glb) == result.bytes and result.bytes > 1_000_000

    # The truck of the warehouse drives 500 m to the vehicle factory at
    # the limit of the yard: 90 world seconds.
    assert %{data: %{"world_ms" => 90_000}} =
             Enum.find(van_events, &(&1.kind == "departed" and &1.data["to"] == "vehicles"))

    # The four wheels come from the wheel factory and the two seats from the
    # seat factory (orders of their own), each by a drive of the truck of
    # that factory to the vehicle factory.
    assert result.plan.ordered == %{"wheel_car_235_65R16" => 4, "driver" => 1, "passenger" => 1}

    for {sub, factory, truck, count} <- [
          {"van-1/wheels", "wheels", "wheel_truck", 4},
          {"van-1/seats", "seats", "seat_truck", 2}
        ] do
      ordered = Enum.find(van_events, &(&1.kind == "part_ordered" and &1.data["order"] == sub))
      assert ordered.data["factory"] == factory

      sub_events = Enum.filter(events, &(&1.order == sub))
      assert Enum.any?(sub_events, &(&1.kind == "task_done" and &1.place == factory))

      assert Enum.any?(
               sub_events,
               &(&1.kind == "departed" and &1.data["vehicle"] == truck and &1.data["to"] == "vehicles")
             )

      received = for e <- van_events, e.kind == "received", e.data["order"] == sub, do: e.data["count"]
      assert Enum.sum(received) == count
    end

    # The van takes hours of the world.
    assert List.last(events).at - hd(events).at > 3_600_000

    # The log is a behavior of specs/Order.tla, with the plan of the van.
    result = Map.put(result, :order, "van-1")
    assert World.OrderSpec.replay(events, result, run, dir) == :ok

    # A log with an unload less is not: a task takes a part that is not at the dock.
    i = Enum.find_index(events, &(&1.kind == "unloaded" and &1.order == "van-1"))
    assert {:error, {:diverged, %{kind: kind}}} = World.OrderSpec.replay(List.delete_at(events, i), result, run, dir)
    assert kind in ~w(task_started departed)

    # A log with one more item from another factory is not: the factory
    # ordered fewer.
    j = Enum.find_index(events, &(&1.kind == "received"))

    assert {:error, {:diverged, %{kind: "received"}}} =
             World.OrderSpec.replay(List.insert_at(events, j, Enum.at(events, j)), result, run, dir)

    # The fault model allows the run too.
    assert World.OrderSpec.replay(events, result, run, dir, guard: false) == :ok

    # The same order a second time comes from the stock.
    assert Run.order(run, van, "van-2") == {:ok, %{from: :stock}}
    assert %{kind: "delivered", data: %{"from" => "stock"}} = List.last(Log.events(Run.log(run)))
    assert Run.stop(run) == :ok
  end

  test "a factory does the orders of other factories one at a time, and its truck brings the items" do
    run = Run.start()
    van = World.Detail.with(:far, &World.Vehicles.FordTransit.model/0)
    [wheel | _] = for {_, %World.Assembly{kind: :wheel} = w, _} <- van.nodes, do: w

    Foreman.sub_order(run.foremen.wheels, "a", [{"w", wheel}], "vehicles", self())
    Foreman.sub_order(run.foremen.wheels, "b", [{"w", wheel}], "vehicles", self())
    assert_receive {:unloaded, "a", name, 1}, 5_000
    assert name == wheel.name
    assert_receive {:unloaded, "b", ^name, 1}, 5_000
    assert_receive {:hauled, _}, 5_000

    # The items of another factory never come from the warehouse.
    events = Log.events(Run.log(run))
    refute Enum.any?(events, &(&1.kind == "picked" and &1.data["item"] == name))
    Run.stop(run)
  end

  test "an order of another factory that the warehouse cannot hold stops" do
    run = Run.start(Run.yard(limit: 1_000))
    van = World.Detail.with(:far, &World.Vehicles.FordTransit.model/0)
    [wheel | _] = for {_, %World.Assembly{kind: :wheel} = w, _} <- van.nodes, do: w
    Foreman.sub_order(run.foremen.wheels, "a", [{"w", wheel}], "vehicles", self())
    refute_receive {:unloaded, "a", _, _}, 500
    assert Enum.any?(Log.events(Run.log(run)), &(&1.kind == "refused" and &1.order == "a"))
    Run.stop(run)
  end

  test "a warehouse too small for a part refuses it, and the order stops" do
    run = Run.start(Run.yard(limit: 1_000, capacity: 2, workers: ["dung"], clock: Clock.new()))
    assert Run.order(run, Seats.seat("s")) == {:error, :full}
    assert Enum.any?(Log.events(Run.log(run)), &(&1.kind == "refused"))
    Run.stop(run)
  end

  test "a warehouse too small for the files of the model refuses them" do
    run = Run.start(Run.yard(limit: 10_000))
    assert Run.order(run, Seats.seat("s")) == {:error, :full}
    assert %{kind: "refused", data: %{"model" => "model:s"}} = List.last(Log.events(Run.log(run)))
    Run.stop(run)
  end

  test "a part in the stock does not come from the supplier again, and a missing part cannot be picked" do
    run = Run.start()
    seat = Seats.seat("s")
    [t | _] = for t <- Plan.flat(seat).tasks, t.uses, do: t
    assert Storekeeper.pick(run.storekeeper, "o", t.uses, 1) == {:error, :missing}
    assert :ok = Storekeeper.supply(run.storekeeper, "o", "supplier", t.uses, 1, :erlang.external_size(t.work))
    assert Stock.count(Storekeeper.stock(run.storekeeper), t.uses) == 1
    assert {:ok, %{from: :factory}} = Run.order(run, seat, "seat")

    supplied = for e <- Log.events(Run.log(run)), e.kind == "stored", e.data["item"] == t.uses, do: e
    assert length(supplied) == 1
    Run.stop(run)
  end

  test "the replay with the fault model finds two workers on one task", %{tmp_dir: dir} do
    run = %Run{yard: Run.yard(), workers: %{"dung" => nil, "em" => nil}}
    tasks = [%Plan.Task{id: "a", action: :order}, %Plan.Task{id: "b", action: :make, uses: "p", waits: ["a"]}]
    result = %{order: "o", plan: %Plan{tasks: tasks, parts: %{"p" => 1}}, sizes: %{"p" => 10}, bytes: 100}
    start = fn who -> %Log.Event{kind: "task_started", order: "o", who: who, data: %{"task" => "a"}} end

    assert {:error, {:violated, "OneWorkerOneTask", %{who: "em"}}} =
             World.OrderSpec.replay([start.("dung"), start.("em")], result, run, dir, guard: false)

    assert {:error, {:diverged, %{who: "em"}}} =
             World.OrderSpec.replay([start.("dung"), start.("em")], result, run, dir)
  end
end
