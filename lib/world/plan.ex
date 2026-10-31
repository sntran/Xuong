defmodule World.Plan do
  @moduledoc """
  The plan of an order, from the tree of its assembly (`docs/world.md`,
  "The plan from an assembly"). It needs no new data:

  - The root item is the first task: `:make` the root part (or the whole
    item, when it is a part or a figure).
  - Each node with a part is a task `:connect`: the worker connects the
    part to its parent node, at the station of the part
    (`params["station"]`). The task waits for the task of its parent.
    A smaller assembly connects at the station of its root part.
  - A node with a smaller assembly or a figure is an order of its own:
    a task `:order` (`NODE/order`), then the task `:connect` that waits
    for it and for the parent.
  - The parts of the plan are the parts of this level, each with its
    count: the storekeeper gets them. A smaller assembly brings its own.

  The id of a task is the name of its node. A task takes one part from
  the dock (`uses`), the part with shapes of its node, and its work is to
  make that part (`work`). `flat/2` puts the plans of the smaller
  assemblies into one plan, for one factory: a smaller assembly of
  another family of things (`World.Places.family_of/1`: the wheels, the
  seats) is an order to the factory of that family, and the plan has
  only the task that connects it when it arrives.
  """
  alias World.{Assembly, Figure, Part, Places}

  defmodule Task do
    @moduledoc """
    A task of a plan: its `id`, its `action` (`:make`, `:order`,
    `:connect`), the name of its item, its station, the node and the port
    it connects to, its joint (the role of a joint, or `nil`), the ids
    of the tasks it waits for, the name of the part it takes from the dock
    (`uses`, or `nil`), the part to make (`work`, or `nil`), and the
    family of the factory that makes its part (`from`, or `nil`: the
    part comes from the warehouse).
    """
    defstruct id: nil,
              action: nil,
              item: nil,
              station: nil,
              to: nil,
              at: nil,
              port: nil,
              joint: nil,
              waits: [],
              uses: nil,
              work: nil,
              from: nil
  end

  @doc """
  A plan: its tasks, the parts to get from the warehouse (`parts`, the
  count of each name), the items that come from other factories
  (`ordered`, the count of each name), and the orders to those factories
  (`orders`: `{family, node, item}`, one for each item).
  """
  defstruct name: nil, tasks: [], parts: %{}, ordered: %{}, orders: []

  @doc "The plan of a part, a figure or an assembly."
  def of(%Part{} = p), do: %__MODULE__{name: p.name, tasks: [make(p.name, p)], parts: parts([p])}
  def of(%Figure{} = f), do: %__MODULE__{name: f.name, tasks: [%Task{id: f.name, action: :make, item: f.name, work: f}]}

  def of(%Assembly{name: name, nodes: [{root, root_item, nil} | rest]}) do
    tasks = [make(root, root_item) | Enum.flat_map(rest, &step/1)]
    items = [root_item | Enum.map(rest, &elem(&1, 1))]
    %__MODULE__{name: name, tasks: tasks, parts: parts(items)}
  end

  defp make(id, %Part{} = p), do: uses(%Task{id: id, action: :make, item: p.name, station: station(p)}, p)
  defp make(id, item), do: %Task{id: id, action: :order, item: item.name}

  defp step({name, %Part{} = p, c}), do: [uses(connect(name, p, c, [c.to]), p)]

  defp step({name, item, c}) do
    order = name <> "/order"
    [%Task{id: order, action: :order, item: item.name}, connect(name, item, c, [c.to, order])]
  end

  defp connect(name, item, c, waits) do
    %Task{
      id: name,
      action: :connect,
      item: item.name,
      station: station(item),
      to: c.to,
      at: port_name(c.at),
      port: port_name(c.port),
      joint: if(c.kind != :fixed, do: c.role),
      waits: waits
    }
  end

  # A part with shapes comes from the dock; a mark (no shapes) does not.
  defp uses(t, %Part{shapes: []}), do: t
  defp uses(t, %Part{} = p), do: %{t | uses: p.name, work: p}

  defp station(%Part{params: params}), do: params["station"]
  defp station(%Assembly{nodes: [{_, root, nil} | _]}), do: station(root)
  defp station(_), do: nil

  defp port_name(%World.Port{name: name}), do: name
  defp port_name(name), do: name

  # The parts to get: the parts of this level with shapes (a part with no
  # shapes is a mark, the origin of a build).
  defp parts(items) do
    for %Part{shapes: [_ | _]} = p <- items, reduce: %{} do
      acc -> Map.update(acc, p.name, 1, &(&1 + 1))
    end
  end

  @doc """
  One plan for an item and each smaller assembly in it, for one factory.
  The tasks of a smaller assembly have the name of its node before their
  ids (`"front_left_wheel/tire"`). Its task `:order` waits for each of
  its tasks: the smaller assembly is done when they are done.

  With the option `family` (the family of the factory), a smaller
  assembly of another family has no tasks here: it is an order to the
  factory of its family (`orders`), and its task `:connect` takes it
  from the dock when it arrives (`from`: its family).
  """
  def flat(item, opts \\ []), do: flat(item, "", Keyword.get(opts, :family))

  defp flat(%Assembly{name: name, nodes: [{root, root_item, nil} | rest]} = a, prefix, family) do
    items = Map.new(rest, fn {n, i, _} -> {n, i} end)
    foreign = for {n, i, _} <- rest, foreign?(i, family), into: MapSet.new(), do: n

    subs =
      Map.new(
        [{root, root_item} | for({n, i, _} <- rest, not MapSet.member?(foreign, n), do: {n <> "/order", i})],
        fn {id, i} -> {id, {id, i}} end
      )

    {tasks, orders} =
      Enum.flat_map_reduce(of(a).tasks, [], fn t, orders ->
        node = String.replace_suffix(t.id, "/order", "")

        cond do
          MapSet.member?(foreign, node) and t.action == :order ->
            {[], orders}

          MapSet.member?(foreign, t.id) ->
            i = items[t.id]
            waits = for w <- t.waits, w != t.id <> "/order", do: prefix <> w

            {[%{t | id: prefix <> t.id, waits: waits, uses: i.name, from: Places.family_of(i)}],
             orders ++ [{Places.family_of(i), prefix <> t.id, i}]}

          true ->
            case {t.action, subs[t.id]} do
              {:order, {id, sub}} ->
                inner = flat(sub, prefix <> String.replace_suffix(id, "/order", "") <> "/", family)

                {inner.tasks ++ [%{t | id: prefix <> t.id, waits: Enum.map(inner.tasks, & &1.id)}],
                 orders ++ inner.orders}

              _ ->
                {[%{t | id: prefix <> t.id, waits: Enum.map(t.waits, &(prefix <> &1))}], orders}
            end
        end
      end)

    plan(name, tasks, orders)
  end

  defp flat(item, prefix, _family) do
    plan = of(item)
    %{plan | tasks: for(t <- plan.tasks, do: %{t | id: prefix <> t.id})}
  end

  defp foreign?(item, family) do
    other = Places.family_of(item)
    family != nil and other != nil and other != family
  end

  defp plan(name, tasks, orders) do
    {ordered, own} = Enum.split_with(tasks, & &1.from)
    %__MODULE__{name: name, tasks: tasks, parts: needs(own), ordered: needs(ordered), orders: orders}
  end

  @doc """
  The plan of a factory for an order of other factory: the items
  (`{node, item}`, each a smaller assembly of the family of this
  factory), each with its tasks under the name of its node
  (`"front_left_wheel/rim"`).
  """
  def batch(items, family) do
    plans = for {node, item} <- items, do: flat(item, node <> "/", family)
    plan(Enum.map_join(items, ", ", &elem(&1, 0)), Enum.flat_map(plans, & &1.tasks), Enum.flat_map(plans, & &1.orders))
  end

  @doc "The count of each part that the tasks of a plan take from the dock."
  def needs(tasks), do: tasks |> Enum.filter(& &1.uses) |> Enum.frequencies_by(& &1.uses)

  @doc "The tasks that can start now: not done, and each task they wait for is done."
  def ready(%__MODULE__{tasks: tasks}, done) do
    done = MapSet.new(done)
    for t <- tasks, not MapSet.member?(done, t.id), Enum.all?(t.waits, &MapSet.member?(done, &1)), do: t
  end

  @doc "The tasks of each station, in the order of the plan. A task with no station is under `nil`."
  def stations(%__MODULE__{tasks: tasks}), do: Enum.group_by(tasks, & &1.station)

  @doc "The plan as data for the log: the id, the action, the station and the waits of each task."
  def to_data(%__MODULE__{name: name, tasks: tasks, parts: parts, ordered: ordered}) do
    %{
      "name" => name,
      "parts" => parts,
      "ordered" => ordered,
      "tasks" =>
        for(
          t <- tasks,
          do: %{
            "id" => t.id,
            "action" => Atom.to_string(t.action),
            "station" => t.station,
            "waits" => t.waits,
            "uses" => t.uses,
            "from" => t.from && Atom.to_string(t.from)
          }
        )
    }
  end
end
