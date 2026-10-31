defmodule World.People.Foreman do
  @moduledoc """
  A foreman (`World.People.Person`, job `:foreman`) as a process: the
  foreman of one factory runs an order from the start to the delivery.

  0. When the warehouse has the files of the model already (an order of
     before), the customer gets them from the stock.
  1. The foreman makes the plan of the order (`World.Plan.flat/2`, for
     the family of the factory). A smaller assembly of another family (the
     wheels, the seats) is an order to the factory of that family
     (`part_ordered`): its foreman makes it, and its driver brings it by
     road to the dock of this factory (`received`).
  2. The storekeeper checks the stock, takes what is missing from the
     supplier, and picks the parts of the plan to the dock of the
     warehouse (`World.People.Storekeeper`).
  3. The driver of the warehouse hauls them to the dock of the factory
     (`World.People.Driver`).
  4. At the start, and each time a part arrives or a task ends, the
     foreman gives each free worker a task that can start: each task that
     it waits for is done, and its part is at the dock
     (`World.People.Worker`).
  5. When each task is done, the foreman makes the files of the model
     (`World.GLB`), the storekeeper puts them in the warehouse, and the
     customer gets them. For an order of another factory, the driver of
     this factory brings the items to the dock of that factory.

  A factory does one order at a time; the next order waits.
  """
  use GenServer

  alias World.{Build, GLB, Plan}
  alias World.Log.Server
  alias World.People.{Driver, Storekeeper, Worker}

  @doc """
  Start a foreman. The options: `name`, `place` (the factory), `family`
  (the family of the factory, `:vehicles` by default), `warehouse`,
  `site`, `supplier`, `storekeeper`, `driver` (the driver of the
  warehouse), `out` (the driver of this factory, for the orders of other
  factories), `workers` (a map of the names to the processes), `log`.
  The other factories come with `factories/2`.
  """
  def start_link(opts), do: GenServer.start_link(__MODULE__, Map.new(opts))

  @doc """
  The other factories: a map of each family to `{place, foreman}`. A
  smaller assembly of a family with no factory here stays in the plan of
  this factory.
  """
  def factories(foreman, factories), do: GenServer.call(foreman, {:factories, factories})

  @doc """
  Run an order of an item (or of a function that makes it, in the
  process of the foreman), and wait for its delivery: `{:ok, result}`, with
  the plan, the bytes of each part and of the model; or `{:error, reason}`.
  `files` makes the files of the model from the item (`files/1`).
  """
  def order(foreman, order, item, files),
    do: GenServer.call(foreman, {:order, order, item, files}, :infinity)

  @doc """
  An order of another factory (`requester`, at the place `to`): the
  items (`[{node, item}]`). The driver of this factory brings each item
  to the dock of `to`, and tells the requester
  (`World.People.Driver.haul/6`).
  """
  def sub_order(foreman, order, items, to, requester),
    do: GenServer.cast(foreman, {:sub_order, order, items, to, requester})

  @doc "The files of a model by default: the GLB at the near level."
  def files(item), do: item |> Build.scene() |> GLB.encode()

  @impl true
  def init(state), do: {:ok, state |> Map.put_new(:family, :vehicles) |> Map.merge(%{factories: %{}, queue: []})}

  @impl true
  def handle_call({:factories, factories}, _from, f), do: {:reply, :ok, %{f | factories: factories}}

  def handle_call({:order, order, item, files}, from, f) do
    item = if is_function(item, 0), do: item.(), else: item
    record(f, "order_received", order, f.place, %{"item" => item.name})
    model = model(item)

    case Storekeeper.check(f.storekeeper, order, %{model => 1}) do
      %{^model => 0} ->
        record(f, "delivered", order, f.site, %{"item" => item.name, "from" => "stock"})
        {:reply, {:ok, %{from: :stock}}, f}

      _ ->
        plan = Plan.flat(item, family: if(map_size(f.factories) > 0, do: f.family))
        start(f, %{order: order, item: item, files: files, from: from, plan: plan})
    end
  end

  @doc "The name of the files of a model in the stock of a warehouse."
  def model(item), do: "model:" <> item.name

  @impl true
  def handle_cast({:sub_order, order, items, to, requester}, f) do
    job = {order, items, to, requester}
    if Map.has_key?(f, :run), do: {:noreply, %{f | queue: f.queue ++ [job]}}, else: sub_order(f, job)
  end

  defp sub_order(f, {order, items, to, requester}) do
    record(f, "order_received", order, f.place, %{"items" => Enum.map(items, &elem(&1, 0)), "for" => to})
    plan = Plan.batch(items, f.family)
    start(f, %{order: order, to: to, requester: requester, plan: plan, items: items})
  end

  # The start of an order: the plan in the log, the orders to the other
  # factories, the parts from the warehouse, then the tasks that can
  # start.
  defp start(f, run) do
    plan = run.plan
    record(f, "plan_made", run.order, f.place, Plan.to_data(plan))
    sizes = sizes(plan)

    for {family, list} <- Enum.group_by(plan.orders, &elem(&1, 0), &Tuple.delete_at(&1, 0)) do
      {place, foreman} = Map.fetch!(f.factories, family)
      sub = "#{run.order}/#{family}"
      counts = list |> Enum.frequencies_by(fn {_, i} -> i.name end)
      record(f, "part_ordered", run.order, f.place, %{"order" => sub, "factory" => place, "items" => counts})
      sub_order(foreman, sub, list, f.place, self())
    end

    with :ok <- fetch(f, run.order, plan.parts, sizes) do
      if plan.parts != %{}, do: Driver.haul(f.driver, run.order, Enum.sort(plan.parts), f.warehouse, f.place, self())

      run =
        Map.merge(run, %{
          sizes: sizes,
          waiting: plan.tasks,
          done: MapSet.new(),
          dock: %{},
          free: f.workers |> Map.keys() |> Enum.sort(),
          hauled: plan.parts == %{}
        })

      # A task with no part (a person, the end of a smaller assembly with
      # no parts) can start before the truck arrives.
      f |> Map.put(:run, run) |> assign()
    else
      error ->
        if Map.has_key?(run, :from), do: {:reply, error, f}, else: {:noreply, f}
    end
  end

  @impl true
  def handle_info({:unloaded, order, item, n}, %{run: r} = f) do
    # An item of an order of this factory to another: it arrives from
    # that factory.
    if order != r.order,
      do: record(f, "received", r.order, f.place, %{"item" => item, "count" => n, "order" => order})

    f |> put_run(%{r | dock: Map.update(r.dock, item, n, &(&1 + n))}) |> assign()
  end

  # The end of a haul of the driver of the warehouse; the end of a haul of
  # another factory changes nothing.
  def handle_info({:hauled, driver}, f) do
    if driver == f.driver and Map.has_key?(f, :run),
      do: f |> put_run(%{f.run | hauled: true}) |> finish(),
      else: {:noreply, f}
  end

  def handle_info({:done, worker, id}, %{run: r} = f) do
    f
    |> put_run(%{r | done: MapSet.put(r.done, id), free: Enum.sort([worker | r.free])})
    |> assign()
  end

  defp put_run(f, run), do: %{f | run: run}

  # The bytes of one part of each name: its size in the external format
  # of the BEAM. Two parts of one name can differ a little (a place in the
  # model): the largest is the size of the name.
  defp sizes(plan) do
    for t <- plan.tasks, t.work, reduce: %{} do
      acc -> Map.update(acc, t.uses, :erlang.external_size(t.work), &max(&1, :erlang.external_size(t.work)))
    end
  end

  # The storekeeper gets each part: from the stock, or from the supplier
  # when it is missing, one name at a time, so the warehouse holds the
  # parts of one name only before they go to its dock.
  defp fetch(_f, _order, needs, _sizes) when needs == %{}, do: :ok

  defp fetch(f, order, needs, sizes) do
    missing = Storekeeper.check(f.storekeeper, order, needs)

    Enum.reduce_while(Enum.sort(needs), :ok, fn {item, n}, :ok ->
      with :ok <- supply(f, order, item, missing[item], sizes[item]),
           :ok <- Storekeeper.pick(f.storekeeper, order, item, n) do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp supply(_f, _order, _item, 0, _bytes), do: :ok
  defp supply(f, order, item, n, bytes), do: Storekeeper.supply(f.storekeeper, order, f.supplier, item, n, bytes)

  # Give each free worker a task that can start.
  defp assign(%{run: r} = f) do
    {tasks, r} =
      Enum.reduce(r.free, {[], r}, fn worker, {acc, r} ->
        case Enum.find(r.waiting, &ready?(&1, r)) do
          nil ->
            {acc, r}

          t ->
            dock = if t.uses, do: Map.update!(r.dock, t.uses, &(&1 - 1)), else: r.dock
            r = %{r | waiting: List.delete(r.waiting, t), dock: dock, free: List.delete(r.free, worker)}
            {[{worker, t} | acc], r}
        end
      end)

    for {worker, t} <- Enum.reverse(tasks), do: Worker.work(f.workers[worker], r.order, t, self())
    finish(put_run(f, r))
  end

  defp ready?(t, r),
    do: Enum.all?(t.waits, &MapSet.member?(r.done, &1)) and (t.uses == nil or Map.get(r.dock, t.uses, 0) > 0)

  # The end of an order: each task done, each worker free, and the truck
  # of the warehouse back.
  defp finish(%{run: r} = f) do
    if r.waiting == [] and r.hauled and length(r.free) == map_size(f.workers) and
         MapSet.size(r.done) == length(r.plan.tasks) do
      if Map.has_key?(r, :requester), do: ship(f, r), else: deliver(f, r)
      f = Map.delete(f, :run)

      case f.queue do
        [] ->
          # The plan and the files of the order are garbage now.
          {:noreply, f, :hibernate}

        [job | rest] ->
          sub_order(%{f | queue: rest}, job)
      end
    else
      {:noreply, f}
    end
  end

  # An order of another factory: the driver of this factory brings the
  # items to its dock.
  defp ship(f, r) do
    counts = r.items |> Enum.frequencies_by(fn {_, i} -> i.name end) |> Enum.sort()
    record(f, "model_done", r.order, f.place, %{"items" => Map.new(counts)})
    Driver.haul(f.out, r.order, counts, f.place, r.to, r.requester)
  end

  # An order of a customer: the foreman makes the files, the storekeeper
  # stores them, and the customer gets them.
  defp deliver(f, r) do
    # The garbage of the run goes before the largest build of the order.
    :erlang.garbage_collect()
    glb = r.files.(r.item)
    bytes = byte_size(glb)
    record(f, "model_done", r.order, f.place, %{"item" => r.item.name, "bytes" => bytes})

    result =
      case Storekeeper.store_model(f.storekeeper, r.order, model(r.item), bytes) do
        :ok ->
          record(f, "delivered", r.order, f.site, %{"item" => r.item.name, "bytes" => bytes})
          {:ok, %{from: :factory, plan: r.plan, sizes: r.sizes, bytes: bytes, glb: glb}}

        error ->
          error
      end

    GenServer.reply(r.from, result)
  end

  defp record(f, kind, order, place, data),
    do: Server.record(f.log, kind, order: order, place: place, who: f.name, data: data)
end
