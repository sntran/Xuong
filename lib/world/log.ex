defmodule World.Log do
  @moduledoc """
  The log of the world (`docs/world.md`, "The events and the log"): the
  events in the order of their time. The log is the truth of the world:
  the replay and the statistics read it only.

  Each event has its world time (`at`) and its wall time (`wall`), in
  milliseconds, its kind, its order (the hash), its place, its person or
  vehicle (`who`), and the data of its kind. The log keeps the scale and
  the start of its clock, and the yard of the run (`World.Yard.describe/1`)
  when it has one. In JSON, the log is one line for the clock and the
  yard, then one line for each event.
  """
  alias World.Clock

  @kinds ~w(order_received plan_made stock_checked part_ordered picked stored refused
            loaded departed arrived unloaded received task_started task_done model_done delivered
            build_started build_done run_done)

  defmodule Event do
    @moduledoc "One thing that happened: its world time, wall time, kind, order, place, person or vehicle, and data."
    defstruct at: 0, wall: 0, kind: nil, order: nil, place: nil, who: nil, data: %{}
  end

  defstruct clock: nil, yard: nil, events: []

  @doc "The kinds of an event."
  def kinds, do: @kinds

  @doc "An empty log with its clock, and the yard of its run (data)."
  def new(%Clock{} = clock, yard \\ nil), do: %__MODULE__{clock: clock, yard: yard}

  @doc """
  Add an event of a kind. The options: `wall` (the wall time, now by
  default), `order`, `place`, `who`, `data`. The log refuses an unknown
  kind, and an event before the last one: `{:error, reason}`.
  """
  def add(%__MODULE__{clock: clock, events: events} = log, kind, opts \\ []) do
    wall = Keyword.get_lazy(opts, :wall, &Clock.wall/0)

    event = %Event{
      at: Clock.at(clock, wall),
      wall: wall,
      kind: kind,
      order: opts[:order],
      place: opts[:place],
      who: opts[:who],
      data: Keyword.get(opts, :data, %{})
    }

    cond do
      kind not in @kinds -> {:error, {:unknown_kind, kind}}
      events != [] and event.at < hd(events).at -> {:error, {:before_last, event}}
      true -> {:ok, %{log | events: [event | events]}}
    end
  end

  @doc "The events, in the order of their time."
  def events(%__MODULE__{events: events}), do: Enum.reverse(events)

  @doc "The log in JSON: one line for the clock, then one line for each event."
  def to_json(%__MODULE__{clock: clock} = log) do
    head = JSON.encode!(%{"scale" => clock.scale, "start" => clock.start, "yard" => log.yard})

    lines =
      for e <- events(log) do
        JSON.encode!(%{
          "at" => e.at,
          "wall" => e.wall,
          "kind" => e.kind,
          "order" => e.order,
          "place" => e.place,
          "who" => e.who,
          "data" => e.data
        })
      end

    Enum.join([head | lines], "\n") <> "\n"
  end

  @doc "A log from its JSON, then checked (`check/1`): `{:ok, log}` or `{:error, reason}`."
  def from_json(json) do
    [head | lines] = String.split(json, "\n", trim: true)
    %{"scale" => scale, "start" => start} = head = JSON.decode!(head)

    events =
      for line <- lines, e = JSON.decode!(line) do
        %Event{
          at: e["at"],
          wall: e["wall"],
          kind: e["kind"],
          order: e["order"],
          place: e["place"],
          who: e["who"],
          data: e["data"]
        }
      end

    log = %__MODULE__{clock: %Clock{scale: scale, start: start}, yard: head["yard"], events: Enum.reverse(events)}
    with :ok <- check(log), do: {:ok, log}
  end

  @doc """
  Check a log: each event has a known kind, a world time from its wall
  time and the clock, and no event comes before the last one. For each
  order, a task starts once, after the plan of the order (`plan_made`),
  after each task it waits for is done; and a task is done after its
  start. `:ok`, or `{:error, {reason, event}}`.
  """
  def check(%__MODULE__{clock: clock} = log) do
    log
    |> events()
    |> Enum.reduce_while({nil, %{}}, fn e, {last, orders} ->
      case step(e, last, orders, clock) do
        {:ok, orders} -> {:cont, {e.at, orders}}
        {:error, reason} -> {:halt, {:error, {reason, e}}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      _ -> :ok
    end
  end

  defp step(e, last, orders, clock) do
    cond do
      e.kind not in @kinds -> {:error, :unknown_kind}
      e.at != Clock.at(clock, e.wall) -> {:error, :wrong_time}
      last != nil and e.at < last -> {:error, :before_last}
      true -> task(e, orders)
    end
  end

  # The state of an order: the waits of each task, and the tasks that
  # started and that are done.
  defp task(%Event{kind: "plan_made", order: order, data: %{"tasks" => tasks}}, orders) do
    waits = Map.new(tasks, &{&1["id"], &1["waits"]})
    {:ok, Map.put(orders, order, %{waits: waits, started: MapSet.new(), done: MapSet.new()})}
  end

  defp task(%Event{kind: kind, order: order, data: %{"task" => id}}, orders) when kind in ~w(task_started task_done) do
    with {:ok, o} <- Map.fetch(orders, order) |> plan(),
         {:ok, waits} <- Map.fetch(o.waits, id) |> known() do
      case kind do
        "task_started" -> start(orders, order, o, id, waits)
        "task_done" -> finish(orders, order, o, id)
      end
    end
  end

  defp task(_, orders), do: {:ok, orders}

  defp plan(:error), do: {:error, :no_plan}
  defp plan(ok), do: ok

  defp known(:error), do: {:error, :unknown_task}
  defp known(ok), do: ok

  defp start(orders, order, o, id, waits) do
    cond do
      MapSet.member?(o.started, id) -> {:error, :started_twice}
      not Enum.all?(waits, &MapSet.member?(o.done, &1)) -> {:error, :waits_not_done}
      true -> {:ok, Map.put(orders, order, %{o | started: MapSet.put(o.started, id)})}
    end
  end

  defp finish(orders, order, o, id) do
    cond do
      not MapSet.member?(o.started, id) -> {:error, :not_started}
      MapSet.member?(o.done, id) -> {:error, :done_twice}
      true -> {:ok, Map.put(orders, order, %{o | done: MapSet.put(o.done, id)})}
    end
  end
end
