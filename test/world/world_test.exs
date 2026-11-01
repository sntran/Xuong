defmodule World.WorldTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias World.{Assembly, Clock, Log, Part, Places, Plan, Shape, Stock, Yard}
  alias World.People.Person
  alias World.Vehicles.Vehicle

  describe "the clock" do
    test "one second of the wall clock is one day of the world" do
      clock = Clock.new(start: 1_000)
      assert clock.scale == Clock.scale() and Clock.scale() == 86_400
      assert Clock.at(clock, 2_000) == 86_400_000
      assert Clock.to_world(clock, 460) == 39_744_000
      # A walk of 100 m is 71 world seconds: less than one ms of the wall clock.
      assert Clock.to_wall(clock, Person.walk(100)) == 1
      assert Clock.to_wall(clock, 0) == 0
      assert Clock.at(Clock.new(), Clock.wall() + 1) > 0
      assert_raise ArgumentError, fn -> Clock.new(scale: 0) end
    end

    test "a world time as people read it" do
      assert Clock.label(0) == "day 1, 00:00"
      assert Clock.label(411 * 86_400_000 + (14 * 60 + 5) * 60_000 + 59_999) == "day 412, 14:05"
    end

    property "the wall time of a world span is never less than the span over the scale" do
      check all world <- integer(0..10_000_000_000), scale <- integer(1..100_000) do
        clock = Clock.new(start: 0, scale: scale)
        wall = Clock.to_wall(clock, world)
        assert wall * scale >= world and (wall - 1) * scale < world
      end
    end
  end

  describe "the stock" do
    test "a warehouse refuses what does not fit, and gives only what it has" do
      s = Stock.new(1_000)
      {:ok, s} = Stock.put(s, "seat_van", 2, 300)
      assert Stock.used(s) == 600 and Stock.free(s) == 400 and Stock.count(s, "seat_van") == 2
      assert Stock.put(s, "seat_van", 2, 300) == {:error, :full}
      assert Stock.put(s, "seat_van", 1, 299) == {:error, :other_size}
      {:ok, s} = Stock.put(s, "seat_van", 1, 300)
      assert Stock.take(s, "seat_van", 4) == {:error, :missing}
      assert Stock.take(s, "wheel", 1) == {:error, :missing}
      {:ok, s} = Stock.take(s, "seat_van", 1)
      {:ok, s} = Stock.take(s, "seat_van", 2)
      assert Stock.count(s, "seat_van") == 0 and Stock.used(s) == 0
    end

    property "the stock is never less than zero, and never more than its limit" do
      check all limit <- integer(0..5_000),
                moves <- list_of({member_of([:put, :take]), member_of(~w(a b c)), integer(1..5), integer(0..400)}) do
        Enum.reduce(moves, Stock.new(limit), fn {move, name, n, bytes}, s ->
          s =
            case if(move == :put, do: Stock.put(s, name, n, bytes), else: Stock.take(s, name, n)) do
              {:ok, s} -> s
              {:error, _} -> s
            end

          assert Stock.used(s) >= 0 and Stock.used(s) <= limit
          assert Enum.all?(~w(a b c), &(Stock.count(s, &1) >= 0))
          s
        end)
      end
    end
  end

  describe "the yard" do
    defp yard do
      Yard.new(clock: Clock.new(start: 0))
      |> Yard.add(Places.warehouse("warehouse", {0, 0}, 10_000_000))
      |> Yard.add(Places.factory("vehicles", {300, 400}, :vehicles))
      |> Yard.add(Places.supplier("makehuman", {-100, 0}))
      |> Yard.add(Places.site("phuot", {0, 900}))
      |> Yard.road("warehouse", "vehicles")
      |> Yard.road("vehicles", "phuot", limit: 50)
      |> Yard.add(Person.new("an", :driver, "warehouse"))
      |> Yard.add(Person.new("binh", :worker, "vehicles", station: "trim", figure: "woman"))
      |> Yard.add(Vehicle.new("truck", "ford_transit_148_camper", speed: 100, capacity: 20, place: "warehouse"))
      |> Yard.add(Vehicle.new("cart", "cart", speed: 10))
    end

    test "places, people, vehicles and the roads between them" do
      y = yard()
      assert y.places["vehicles"].family == :vehicles and y.places["warehouse"].stock.limit == 10_000_000
      assert Enum.sort(Places.kinds()) == [:factory, :site, :supplier, :warehouse]
      assert :people in Places.families()
      assert y.people["binh"].station == "trim" and :foreman in Person.jobs() and Person.speed() == 1.4

      # 500 m at the limit of the yard (20 km/h): 90 world seconds.
      {:ok, road} = Yard.route(y, "vehicles", "warehouse")
      assert road.length == 500.0 and road.limit == 20
      assert Yard.drive(y, "truck", "warehouse", "vehicles") == {:ok, 90_000}
      # The cart is slower than the limit; the truck is faster than 50 km/h.
      assert Yard.drive(y, "cart", "vehicles", "warehouse") == {:ok, 180_000}

      assert Yard.drive(y, "truck", "vehicles", "phuot") ==
               {:ok, round(Places.distance(y.places["vehicles"], y.places["phuot"]) / (50 / 3.6) * 1000)}

      assert Yard.drive(y, "truck", "warehouse", "makehuman") == {:error, :no_road}
    end

    test "a yard refuses a thing with no place, and two things with one name" do
      y = yard()
      assert_raise ArgumentError, fn -> Yard.add(y, Places.site("phuot", {1, 1})) end
      assert_raise ArgumentError, fn -> Yard.add(y, Person.new("chi", :worker, "nowhere")) end
      assert_raise ArgumentError, fn -> Yard.add(y, Vehicle.new("van", "van", place: "nowhere")) end
      assert_raise ArgumentError, fn -> Yard.road(y, "warehouse", "nowhere") end
      assert_raise ArgumentError, fn -> Person.new("chi", Enum.random([:pilot]), "warehouse") end
      assert_raise ArgumentError, fn -> Places.factory("ships", {0, 0}, Enum.random([:ships])) end
      assert Vehicle.new("van", "van").capacity == 1
      assert_raise ArgumentError, fn -> Vehicle.new("van", "van", speed: 0) end
      assert Yard.new().clock.scale == 86_400
    end
  end

  describe "the plan of an order" do
    # Each model of the catalog: one task for each node, and each task
    # waits for the task of its parent.
    for {name, _} <- World.Catalog.models() do
      @name name
      test "the plan of #{name}" do
        {:ok, fun} = World.Catalog.fetch(@name)
        item = fun.()
        plan = Plan.of(item)
        ids = Enum.map(plan.tasks, & &1.id)
        assert length(ids) == length(Enum.uniq(ids))

        case item do
          %Assembly{nodes: nodes} ->
            connects = for t <- plan.tasks, t.action != :order or t.id == elem(hd(nodes), 0), do: t.id
            assert connects == Enum.map(nodes, &elem(&1, 0))

            for {node, _, c} <- tl(nodes) do
              task = Enum.find(plan.tasks, &(&1.id == node and &1.action == :connect))
              assert c.to in task.waits
            end

          _ ->
            assert [%Plan.Task{action: :make}] = plan.tasks
        end

        # The tasks come in an order where each task waits only for the
        # tasks before it, in the plan and in its flat plan for one factory.
        for p <- [plan, Plan.flat(item)] do
          assert length(p.tasks) == length(Enum.uniq_by(p.tasks, & &1.id))

          Enum.reduce(p.tasks, MapSet.new(), fn t, before ->
            assert Enum.all?(t.waits, &MapSet.member?(before, &1))
            MapSet.put(before, t.id)
          end)
        end
      end
    end

    test "a sub-assembly is an order of its own, a joint keeps its role, and the station comes from the part" do
      box = fn name, station ->
        Part.new(name, :part, [Shape.box({0, 0, 0}, {1, 1, 1}, :steel)], [Part.port("p", {0, 0, 0}, {0, 0, 1})],
          params: %{"station" => station}
        )
      end

      mark = Part.new("origin", :part, [], [Part.port("p", {0, 0, 0}, {0, 0, 1})])
      wheel = Assembly.new("wheel", box.("rim", "wheels"), root: "rim")

      van =
        Assembly.new("van", mark, root: "origin")
        |> Assembly.add("body", box.("body", "body_shop"), at: "p", port: "p")
        |> Assembly.add("door", box.("door", "closures"), to: "body", at: "p", port: "p", kind: :hinge, role: :door)
        |> Assembly.add("wheel", wheel, to: "body", at: World.Port.new("axle", {0, 0, 0}, {1, 0, 0}), port: "p")

      plan = Plan.of(van)

      assert Enum.map(plan.tasks, &{&1.id, &1.action}) == [
               {"origin", :make},
               {"body", :connect},
               {"door", :connect},
               {"wheel/order", :order},
               {"wheel", :connect}
             ]

      door = Enum.find(plan.tasks, &(&1.id == "door"))
      assert door.joint == :door and door.station == "closures" and door.waits == ["body"] and door.at == "p"
      wheel_task = Enum.find(plan.tasks, &(&1.id == "wheel"))
      assert wheel_task.waits == ["body", "wheel/order"] and wheel_task.at == "axle" and wheel_task.item == "wheel"
      assert wheel_task.station == "wheels"
      # The mark of the origin is not a part to get; the wheel brings its own parts.
      assert plan.parts == %{"body" => 1, "door" => 1}
      assert Map.keys(Plan.stations(plan)) |> Enum.sort_by(&to_string/1) == [nil, "body_shop", "closures", "wheels"]

      # The tasks that can start, as the tasks end.
      assert Enum.map(Plan.ready(plan, []), & &1.id) == ["origin", "wheel/order"]
      assert Enum.map(Plan.ready(plan, ["origin"]), & &1.id) == ["body", "wheel/order"]
      assert Enum.map(Plan.ready(plan, ["origin", "body", "wheel/order"]), & &1.id) == ["door", "wheel"]

      data = Plan.to_data(plan)
      assert %{"id" => "wheel", "action" => "connect", "waits" => ["body", "wheel/order"]} = List.last(data["tasks"])
      assert Plan.of(box.("seat", nil)).parts == %{"seat" => 1}

      # The flat plan: the tasks of the wheel come first, then the end of
      # the wheel waits for each of them.
      flat = Plan.flat(van)
      assert Enum.map(flat.tasks, & &1.id) == ["origin", "body", "door", "wheel/rim", "wheel/order", "wheel"]
      assert Enum.find(flat.tasks, &(&1.id == "wheel/order")).waits == ["wheel/rim"]
      assert flat.parts == %{"body" => 1, "door" => 1, "rim" => 1}
      assert [%Plan.Task{id: "seat", uses: "seat"}] = Plan.flat(box.("seat", nil)).tasks
    end

    test "for a factory, a smaller assembly of another family is an order to the factory of that family" do
      part = fn name ->
        Part.new(name, :part, [Shape.box({0, 0, 0}, {1, 1, 1}, :steel)], [Part.port("p", {0, 0, 0}, {0, 0, 1})])
      end

      wheel = %{Assembly.new("wheel_x", part.("rim"), root: "rim") | kind: :wheel}
      seat = %{Assembly.new("seat_x", part.("cushion"), root: "cushion") | kind: :seat}

      corner =
        Assembly.new("corner", part.("knuckle"), root: "knuckle") |> Assembly.add("wheel", wheel, at: "p", port: "p")

      van =
        Assembly.new("van", part.("body"), root: "body")
        |> Assembly.add("corner", corner, at: "p", port: "p")
        |> Assembly.add("seat", seat, at: "p", port: "p")

      assert Places.family_of(wheel) == :wheels and Places.family_of(seat) == :seats and
               Places.family_of(part.("x")) == nil

      # A door and a window come from the openings factory.
      assert Places.family_of(%{Assembly.new("door_x", part.("panel"), root: "panel") | kind: :door}) == :openings
      assert Places.family_of(%{Assembly.new("window_x", part.("glass"), root: "glass") | kind: :window}) == :openings

      plan = Plan.flat(van, family: :vehicles)

      assert Enum.map(plan.tasks, &{&1.id, &1.uses, &1.from}) == [
               {"body", "body", nil},
               {"corner/knuckle", "knuckle", nil},
               {"corner/wheel", "wheel_x", :wheels},
               {"corner/order", nil, nil},
               {"corner", nil, nil},
               {"seat", "seat_x", :seats}
             ]

      assert Enum.find(plan.tasks, &(&1.id == "corner/wheel")).waits == ["corner/knuckle"]
      assert plan.parts == %{"body" => 1, "knuckle" => 1}
      assert plan.ordered == %{"wheel_x" => 1, "seat_x" => 1}
      assert [{:wheels, "corner/wheel", ^wheel}, {:seats, "seat", ^seat}] = plan.orders
      assert %{"from" => "wheels"} = Enum.find(Plan.to_data(plan)["tasks"], &(&1["id"] == "corner/wheel"))

      # With no family, the plan has all the tasks, as before.
      assert Plan.flat(van).ordered == %{} and
               Plan.flat(van).parts == %{"body" => 1, "knuckle" => 1, "rim" => 1, "cushion" => 1}

      # The plan of the wheel factory for two wheels.
      batch = Plan.batch([{"a", wheel}, {"b", wheel}], :wheels)
      assert Enum.map(batch.tasks, & &1.id) == ["a/rim", "b/rim"] and batch.parts == %{"rim" => 2}
    end
  end

  describe "the log" do
    defp plan_data do
      %{"tasks" => [%{"id" => "a", "waits" => []}, %{"id" => "b", "waits" => ["a"]}]}
    end

    defp run(steps) do
      Enum.reduce(steps, Log.new(Clock.new(start: 0)), fn {wall, kind, data}, log ->
        {:ok, log} = Log.add(log, kind, wall: wall, order: "o1", place: "vehicles", who: "binh", data: data)
        log
      end)
    end

    test "the events of an order, in the order of their time, and back from JSON" do
      log =
        run([
          {1, "order_received", %{}},
          {2, "plan_made", plan_data()},
          {3, "task_started", %{"task" => "a"}},
          {5, "task_done", %{"task" => "a"}},
          {5, "task_started", %{"task" => "b"}},
          {9, "task_done", %{"task" => "b"}},
          {9, "model_done", %{}}
        ])

      assert Log.check(log) == :ok
      assert hd(Log.events(log)).at == 86_400 and List.last(Log.events(log)).kind == "model_done"
      assert "task_started" in Log.kinds()
      json = Log.to_json(log)
      assert {:ok, back} = Log.from_json(json)
      assert Log.events(back) == Log.events(log) and back.clock == log.clock
      assert {:ok, _} = Log.add(Log.new(Clock.new()), "order_received")
    end

    test "the log refuses an unknown kind and an event before the last one" do
      log = run([{5, "order_received", %{}}])
      assert {:error, {:unknown_kind, "lunch"}} = Log.add(log, "lunch", wall: 6)
      assert {:error, {:before_last, _}} = Log.add(log, "plan_made", wall: 4)
    end

    test "a log with a bad order of events is refused" do
      bad = fn steps -> run([{1, "plan_made", plan_data()} | steps]) |> Log.check() |> elem(1) |> elem(0) end

      assert bad.([{2, "task_started", %{"task" => "b"}}]) == :waits_not_done
      assert bad.([{2, "task_started", %{"task" => "a"}}, {3, "task_started", %{"task" => "a"}}]) == :started_twice
      assert bad.([{2, "task_done", %{"task" => "a"}}]) == :not_started

      assert bad.([
               {2, "task_started", %{"task" => "a"}},
               {3, "task_done", %{"task" => "a"}},
               {4, "task_done", %{"task" => "a"}}
             ]) == :done_twice

      assert bad.([{2, "task_started", %{"task" => "z"}}]) == :unknown_task

      no_plan = run([{2, "task_started", %{"task" => "a"}}])
      assert {:error, {:no_plan, _}} = Log.check(no_plan)

      # A log changed by hand: a wrong time, an event before the last, an unknown kind.
      log = run([{1, "order_received", %{}}, {2, "model_done", %{}}])
      [first, second] = Log.events(log)
      assert {:error, {:wrong_time, _}} = Log.check(%{log | events: [%{second | at: 1}, first]})
      assert {:error, {:before_last, _}} = Log.check(%{log | events: [first, second]})
      assert {:error, {:unknown_kind, _}} = Log.check(%{log | events: [%{second | kind: "lunch"}, first]})

      json = Log.to_json(log) |> String.replace("model_done", "lunch")
      assert {:error, {:unknown_kind, _}} = Log.from_json(json)
    end
  end
end
