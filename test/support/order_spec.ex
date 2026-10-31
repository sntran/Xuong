defmodule World.OrderSpec do
  @moduledoc """
  The replay of the log of a run (`World.Run`) as a behavior of
  `specs/Order.tla`. A module for the run (`Run.tla`) extends `Order` with
  the plan, the parts and the sizes of the run as its constants. Then the
  machine of Accord (`Accord.TLA.Checker.Machine`) takes each event of the
  log as an action of the specification, and checks the invariants after
  each step.
  """
  alias Accord.TLA.Checker.Machine

  @specs Path.expand("../../specs", __DIR__)
  @invariants ~w(InLimit Conservation InCapacity OneWorkerOneTask WaitsFirst)

  @doc """
  Replay the events of an order. `result` is the result of
  `World.Run.order/3`. With `guard: false`, the replay uses the fault
  model (a task can start twice). It gives `:ok`, `{:error, {:diverged, event}}`
  when the specification has no step for an event, or
  `{:error, {:violated, invariant, event}}`.
  """
  def replay(events, result, run, dir, opts \\ []) do
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "Run.tla"), module(result, run))
    File.write!(Path.join(dir, "Run.cfg"), config(run, Keyword.get(opts, :guard, true)))
    {:ok, m} = Machine.load(Path.join(dir, "Run.tla"), paths: [@specs])
    {:ok, init} = Machine.init_states(m)

    events
    |> Enum.filter(&(&1.order == result.order))
    |> Enum.reduce_while({:ok, init}, fn e, {:ok, states} ->
      case action(e, run) do
        nil -> {:cont, {:ok, states}}
        {name, args} -> step(m, states, name, args, e)
      end
    end)
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp step(m, states, name, args, e) do
    next =
      for s <- states, {:ok, steps} = Machine.step(m, s, name, args), {n, _} <- steps, uniq: true, do: n

    violated = fn s ->
      case Machine.check_invariants(m, s) do
        {:violated, inv} -> inv
        :ok -> nil
      end
    end

    case Enum.find_value(next, violated) do
      _ when next == [] -> {:halt, {:error, {:diverged, e}}}
      nil -> {:cont, {:ok, next}}
      inv -> {:halt, {:error, {:violated, inv, e}}}
    end
  end

  # The action of an event, with its arguments.
  defp action(%{kind: "stored", data: %{"item" => i, "count" => n}}, _), do: {"Supply", [i, n]}
  defp action(%{kind: "stored", data: %{"model" => _}}, _), do: {"StoreModel", []}
  defp action(%{kind: "picked", data: d}, _), do: {"Pick", [d["item"], d["count"]]}
  defp action(%{kind: "loaded", data: d}, _), do: {"Load", [d["item"], d["count"]]}
  defp action(%{kind: "unloaded", data: d}, _), do: {"Unload", [d["item"], d["count"]]}
  defp action(%{kind: "received", data: d}, _), do: {"Receive", [d["item"], d["count"]]}
  defp action(%{kind: "departed", data: d}, run), do: {"Depart", [place(d["from"], run)]}
  defp action(%{kind: "arrived", data: d}, run), do: {"Arrive", [place(d["to"], run)]}
  defp action(%{kind: "task_started", who: w, data: d}, _), do: {"Start", [w, d["task"]]}
  defp action(%{kind: "task_done", who: w, data: d}, _), do: {"Finish", [w, d["task"]]}
  defp action(%{kind: "model_done"}, _), do: {"ModelDone", []}
  defp action(%{kind: "delivered"}, _), do: {"Deliver", []}
  defp action(_, _), do: nil

  # The places of the specification: the warehouse and the factory.
  defp place(name, run), do: if(run.yard.places[name].kind == :factory, do: "factory", else: "warehouse")

  defp module(result, run) do
    tasks = result.plan.tasks
    # The items from other factories never go into the warehouse.
    zero = Map.new(result.plan.ordered, fn {i, _} -> {i, 0} end)
    own = Map.new(result.plan.parts, fn {i, _} -> {i, 0} end)

    """
    ---- MODULE Run ----
    EXTENDS Order, TLC
    RunItems == #{set(Map.keys(result.plan.parts) ++ Map.keys(result.plan.ordered))}
    RunSize == #{fun(Map.merge(zero, result.sizes), &Integer.to_string/1)}
    RunNeed == #{fun(Map.merge(zero, result.plan.parts), &Integer.to_string/1)}
    RunOrdered == #{fun(Map.merge(own, result.plan.ordered), &Integer.to_string/1)}
    RunTasks == #{set(Enum.map(tasks, & &1.id))}
    RunWaits == #{fun(Map.new(tasks, &{&1.id, &1.waits}), &set/1)}
    RunUses == #{fun(Map.new(tasks, &{&1.id, &1.uses || ""}), &str/1)}
    RunWorkers == #{set(Map.keys(run.workers))}
    RunModelSize == #{result.bytes}
    ====
    """
  end

  defp config(run, guard) do
    """
    SPECIFICATION Spec
    CONSTANTS
        Items <- RunItems
        Size <- RunSize
        Need <- RunNeed
        Ordered <- RunOrdered
        Limit = #{run.yard.places["warehouse"].stock.limit}
        Capacity = #{run.yard.vehicles["truck"].capacity}
        Tasks <- RunTasks
        Waits <- RunWaits
        Uses <- RunUses
        Workers <- RunWorkers
        ModelSize <- RunModelSize
        Guard = #{if guard, do: "TRUE", else: "FALSE"}
    INVARIANT #{Enum.join(@invariants, " ")}
    """
  end

  defp str(s), do: ~s("#{s}")
  defp set(names), do: "{" <> Enum.map_join(Enum.sort(names), ", ", &str/1) <> "}"

  defp fun(map, value) do
    map
    |> Enum.sort()
    |> Enum.map_join(" @@ ", fn {k, v} -> "(#{str(k)} :> #{value.(v)})" end)
  end
end
