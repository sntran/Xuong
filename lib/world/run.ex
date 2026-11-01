defmodule World.Run do
  @moduledoc """
  A run of the world (`docs/world.md`, steps W2, W4, W5 and W6): orders
  through the places and the people of a yard. The yard has one warehouse
  with its storekeeper and the driver of its truck, an annex (a second
  warehouse, for the models that the warehouse refuses) with its
  storekeeper, the catalog of a release when it is given, four factories (the
  vehicles, the wheels, the seats and the houses), each with its foreman,
  its workers and (the wheels and the seats) the driver of its truck, a
  supplier, and the site of the customer. The people are processes. Each
  act is an event of the log, at its real time.

  The people build the places too (`build/3`): the houses factory makes
  the building of a warehouse or of a factory.

  An order goes to the factory of the family of its item (the vehicles by
  default). A smaller assembly of another family is an order to the
  factory of that family, and its truck brings it by road.
  """
  alias World.{Clock, Places, Yard}
  alias World.Buildings.Plants
  alias World.Log.Server
  alias World.People.{Driver, Foreman, Person, Storekeeper, Worker}
  alias World.Vehicles.Vehicle

  # The factories: the place, its family, its position, its foreman, its
  # workers, and the driver and the truck that bring its items to another
  # factory.
  @factories [
    %{place: "vehicles", family: :vehicles, at: {300, 400}, foreman: "chi", workers: ["dung", "em"]},
    %{
      place: "wheels",
      family: :wheels,
      at: {600, 0},
      foreman: "giang",
      workers: ["hanh"],
      out: {"khoa", "wheel_truck"}
    },
    %{place: "seats", family: :seats, at: {-300, 400}, foreman: "lan", workers: ["minh"], out: {"nga", "seat_truck"}},
    %{
      place: "openings",
      family: :openings,
      at: {600, 400},
      foreman: "vinh",
      workers: ["xuan"],
      out: {"yen", "opening_truck"}
    },
    %{place: "houses", family: :houses, at: {-300, -300}, foreman: "oanh", workers: ["phuc", "quang"]}
  ]

  @doc """
  The yard of the run. The options: `limit` (the bytes of the warehouse,
  1 GB by default), `store` (the store of the warehouse,
  `World.Store`, the memory of the VM by default), `annex_limit` and
  `annex_store` (the same for the annex), `catalog` (the folder of the
  models of a release, `World.Places.catalog/3`; no catalog by default),
  `capacity` (the items on the truck of the warehouse, 20 by default),
  `workers` (the names of the workers of the vehicle factory), `clock`.
  """
  def yard(opts \\ []) do
    yard =
      Yard.new(clock: Keyword.get_lazy(opts, :clock, &Clock.new/0))
      |> Yard.add(warehouse("warehouse", {0, 0}, opts[:limit], opts[:store]))
      |> Yard.add(warehouse("annex", {200, -200}, opts[:annex_limit], opts[:annex_store]))
      |> Yard.add(Person.new("tam", :storekeeper, "annex"))
      |> Yard.add(Places.supplier("supplier", {-200, 0}))
      |> Yard.add(Places.site("customer", {300, 900}))
      |> Yard.add(Person.new("an", :storekeeper, "warehouse"))
      |> Yard.add(Person.new("binh", :driver, "warehouse"))
      |> Yard.add(
        Vehicle.new("truck", "ford_transit_148_camper",
          capacity: Keyword.get(opts, :capacity, 20),
          place: "warehouse",
          driver: "binh"
        )
      )

    factories =
      Enum.map(@factories, fn
        %{family: :vehicles} = f -> %{f | workers: Keyword.get(opts, :workers, f.workers)}
        f -> f
      end)

    factories
    |> Enum.reduce(add_catalog(yard, opts[:catalog]), fn f, yard ->
      yard
      |> Yard.add(Places.factory(f.place, f.at, f.family))
      |> Yard.road("warehouse", f.place)
      |> Yard.road("annex", f.place)
      |> Yard.add(Person.new(f.foreman, :foreman, f.place))
      |> add_workers(f.place, f.workers)
      |> add_out(f)
    end)
    |> Yard.road("vehicles", "customer")
    |> Yard.road("wheels", "vehicles")
    |> Yard.road("seats", "vehicles")
    |> Yard.road("openings", "vehicles")
    |> Yard.road("openings", "houses")
  end

  defp warehouse(name, at, limit, store),
    do: Places.warehouse(name, at, limit || 1_000_000_000, store || World.Store.memory())

  defp add_catalog(yard, nil), do: yard

  defp add_catalog(yard, dir),
    do:
      yard
      |> Yard.add(Places.catalog("catalog", {-100, -250}, dir))
      |> Yard.add(Person.new("uyen", :storekeeper, "catalog"))

  defp add_workers(yard, place, names),
    do: Enum.reduce(names, yard, &Yard.add(&2, Person.new(&1, :worker, place, station: nil, figure: "man")))

  defp add_out(yard, %{out: {driver, truck}, place: place}) do
    yard
    |> Yard.add(Person.new(driver, :driver, place))
    |> Yard.add(Vehicle.new(truck, "ford_transit_148_camper", capacity: 8, place: place, driver: driver))
  end

  defp add_out(yard, _factory), do: yard

  defstruct yard: nil,
            log: nil,
            storekeeper: nil,
            storekeepers: %{},
            driver: nil,
            foreman: nil,
            foremen: %{},
            workers: %{},
            people: []

  @doc """
  Start the people of a yard (`yard/1`) as processes, with the log of
  the run. The stock of the warehouses stays between the orders. `workers`
  are the workers of the vehicle factory, and `foreman` its foreman;
  `storekeepers` the storekeeper of each warehouse, by its place.
  """
  def start(yard \\ yard()) do
    {:ok, log} = Server.start_link(yard.clock, Yard.describe(yard))

    keepers =
      for {name, %Person{job: :storekeeper, place: place}} <- yard.people, into: %{} do
        {:ok, pid} = Storekeeper.start_link(name: name, place: place, stock: yard.places[place].stock, log: log)
        {place, pid}
      end

    sk = keepers["warehouse"]

    {catalogs, annexes} =
      keepers
      |> Map.delete("warehouse")
      |> Enum.sort()
      |> Enum.split_with(fn {place, _} -> yard.places[place].stock.store.kind == :release end)

    {:ok, driver} = Driver.start_link(name: "binh", vehicle: "truck", yard: yard, log: log)

    started =
      for {_, %{kind: :factory} = place} <- yard.places, into: %{} do
        workers =
          for {name, %Person{job: :worker, place: p}} <- yard.people, p == place.name, into: %{} do
            {:ok, pid} = Worker.start_link(name: name, place: place.name, log: log)
            {name, pid}
          end

        out =
          Enum.find_value(yard.vehicles, fn {name, v} ->
            if v.place == place.name do
              {:ok, pid} = Driver.start_link(name: v.driver, vehicle: name, yard: yard, log: log)
              pid
            end
          end)

        [foreman] = for {name, %Person{job: :foreman, place: p}} <- yard.people, p == place.name, do: name

        {:ok, pid} =
          Foreman.start_link(
            name: foreman,
            place: place.name,
            family: place.family,
            warehouse: "warehouse",
            site: "customer",
            supplier: "supplier",
            storekeeper: sk,
            annexes: annexes,
            catalogs: catalogs,
            driver: driver,
            out: out,
            workers: workers,
            log: log
          )

        {place.family, %{place: place.name, foreman: pid, workers: workers, out: out}}
      end

    factories = Map.new(started, fn {family, s} -> {family, {s.place, s.foreman}} end)
    for {family, s} <- started, do: Foreman.factories(s.foreman, Map.delete(factories, family))

    people =
      [log | Map.values(keepers)] ++
        [driver] ++
        Enum.flat_map(started, fn {_, s} -> [s.foreman | Map.values(s.workers)] ++ List.wrap(s.out) end)

    %__MODULE__{
      yard: yard,
      log: log,
      storekeeper: sk,
      storekeepers: keepers,
      driver: driver,
      foreman: started.vehicles.foreman,
      foremen: Map.new(started, fn {family, s} -> {family, s.foreman} end),
      workers: started.vehicles.workers,
      people: people
    }
  end

  @doc """
  Run an order of an item (or of a function that makes the item: the
  foreman calls it), and wait for its delivery: `{:ok, result}`
  (`from: :factory` with the plan, the bytes of each part and of the
  model; or `from: :stock`; each with the files of the model and the
  warehouse that keeps them), or `{:error, reason}`. The
  order goes to the factory of the family of the item
  (`World.Places.family_of/1`), the vehicles by default. The option
  `files` is the function that makes the files of the model from the
  item (the GLB at near by default): an order with a level, a pose and
  colors gives its own.
  """
  def order(%__MODULE__{} = run, item, order \\ nil, opts \\ []) do
    foreman = Map.get(run.foremen, is_struct(item) && Places.family_of(item), run.foreman)

    Foreman.order(
      foreman,
      order || "order-#{System.unique_integer([:positive])}",
      item,
      Keyword.get(opts, :files, &Foreman.files/1)
    )
  end

  @doc """
  Build a place of the yard (`World.Buildings.Plants.of/2`): its building
  is an order to the houses factory, delivered to the place. The log has
  `build_started` (the model and its size) and `build_done`. The result
  is the result of the order.
  """
  def build(%__MODULE__{} = run, name, order \\ nil) do
    item = Plants.of(run.yard, name)
    order = order || "build-#{name}"
    size = Map.take(item.extras, ~w(length depth racks limit workers))
    Server.record(run.log, "build_started", order: order, place: name, data: Map.put(size, "model", item.name))
    result = Foreman.order(run.foremen.houses, order, item, &Foreman.files/1, name)

    with {:ok, r} <- result do
      Server.record(run.log, "build_done",
        order: order,
        place: name,
        data: %{"model" => item.name, "from" => to_string(r.from)}
      )
    end

    result
  end

  @doc """
  Measure a function in the run (`docs/world.md`, step W7): the time of
  the wall clock, and the memory of the VM (`memory/1`, each 25 ms and
  at the end). The log gets `run_done` with `ms`, `memory_peak` and
  `memory_end` (in bytes), and `memory` (what the bytes count). The
  result is the result of the function.
  """
  def measure(%__MODULE__{log: log}, order, fun) do
    sampler = spawn_link(fn -> sample(memory()) end)
    start = System.monotonic_time(:millisecond)
    result = fun.()
    ms = System.monotonic_time(:millisecond) - start
    send(sampler, {:peak, self()})
    peak = receive do: ({:peak, peak} -> peak)
    {what, bytes} = memory()
    data = %{"ms" => ms, "memory_peak" => max(elem(peak, 1), bytes), "memory_end" => bytes, "memory" => what}
    Server.record(log, "run_done", order: order, data: data)
    result
  end

  defp sample({what, peak}) do
    {_, now} = memory()
    peak = {what, max(peak, now)}

    receive do
      {:peak, from} -> send(from, {:peak, peak})
    after
      25 -> sample(peak)
    end
  end

  @doc """
  The memory of the VM, in bytes: `{"total", bytes}` (`:erlang.memory/1`).
  An emulator with no allocators of ERTS (`-Mea min`, at the edge) does
  not have it: then `{"processes", bytes}`, the memory of each process
  and of each binary that a process holds (one time each). `total` is
  the function of the memory of all of the VM.
  """
  def memory(total \\ &:erlang.memory/1) do
    {"total", total.(:total)}
  rescue
    ErlangError ->
      infos = for p <- Process.list(), info = Process.info(p, [:memory, :binary]), do: info
      binaries = for info <- infos, {id, size, _} <- info[:binary], into: %{}, do: {id, size}
      {"processes", Enum.sum(for info <- infos, do: info[:memory]) + Enum.sum(Map.values(binaries))}
  end

  @doc "The log of the run (`World.Log`)."
  def log(%__MODULE__{log: log}), do: Server.log(log)

  @doc "Stop the people of the run."
  def stop(%__MODULE__{people: people}) do
    for pid <- Enum.reverse(people), do: GenServer.stop(pid)
    :ok
  end
end
