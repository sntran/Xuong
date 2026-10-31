defmodule World.Run do
  @moduledoc """
  A run of the world (`docs/world.md`, steps W2 and W4): orders through
  the places and the people of a yard. The yard has one warehouse with
  its storekeeper and the driver of its truck, three factories (the
  vehicles, the wheels and the seats), each with its foreman, its workers
  and (the wheels and the seats) the driver of its truck, a supplier, and
  the site of the customer. The people are processes. Each act is an
  event of the log, at its real time.

  An order goes to the factory of the family of its item (the vehicles by
  default). A smaller assembly of another family is an order to the
  factory of that family, and its truck brings it by road.
  """
  alias World.{Clock, Places, Yard}
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
    %{place: "seats", family: :seats, at: {-300, 400}, foreman: "lan", workers: ["minh"], out: {"nga", "seat_truck"}}
  ]

  @doc """
  The yard of the run. The options: `limit` (the bytes of the warehouse,
  1 GB by default), `capacity` (the items on the truck of the warehouse,
  20 by default), `workers` (the names of the workers of the vehicle
  factory), `clock`.
  """
  def yard(opts \\ []) do
    yard =
      Yard.new(clock: Keyword.get_lazy(opts, :clock, &Clock.new/0))
      |> Yard.add(Places.warehouse("warehouse", {0, 0}, Keyword.get(opts, :limit, 1_000_000_000)))
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
    |> Enum.reduce(yard, fn f, yard ->
      yard
      |> Yard.add(Places.factory(f.place, f.at, f.family))
      |> Yard.road("warehouse", f.place)
      |> Yard.add(Person.new(f.foreman, :foreman, f.place))
      |> add_workers(f.place, f.workers)
      |> add_out(f)
    end)
    |> Yard.road("vehicles", "customer")
    |> Yard.road("wheels", "vehicles")
    |> Yard.road("seats", "vehicles")
  end

  defp add_workers(yard, place, names),
    do: Enum.reduce(names, yard, &Yard.add(&2, Person.new(&1, :worker, place, station: nil, figure: "man")))

  defp add_out(yard, %{out: {driver, truck}, place: place}) do
    yard
    |> Yard.add(Person.new(driver, :driver, place))
    |> Yard.add(Vehicle.new(truck, "ford_transit_148_camper", capacity: 8, place: place, driver: driver))
  end

  defp add_out(yard, _factory), do: yard

  defstruct yard: nil, log: nil, storekeeper: nil, driver: nil, foreman: nil, foremen: %{}, workers: %{}, people: []

  @doc """
  Start the people of a yard (`yard/1`) as processes, with the log of
  the run. The stock of the warehouse stays between the orders. `workers`
  are the workers of the vehicle factory, and `foreman` its foreman.
  """
  def start(yard \\ yard()) do
    {:ok, log} = Server.start_link(yard.clock, Yard.describe(yard))
    {:ok, sk} = Storekeeper.start_link(name: "an", place: "warehouse", stock: yard.places["warehouse"].stock, log: log)
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
      [log, sk, driver] ++
        Enum.flat_map(started, fn {_, s} -> [s.foreman | Map.values(s.workers)] ++ List.wrap(s.out) end)

    %__MODULE__{
      yard: yard,
      log: log,
      storekeeper: sk,
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
  model, and its files; or `from: :stock`), or `{:error, reason}`. The
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

  @doc "The log of the run (`World.Log`)."
  def log(%__MODULE__{log: log}), do: Server.log(log)

  @doc "Stop the people of the run."
  def stop(%__MODULE__{people: people}) do
    for pid <- Enum.reverse(people), do: GenServer.stop(pid)
    :ok
  end
end
