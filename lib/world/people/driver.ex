defmodule World.People.Driver do
  @moduledoc """
  A driver (`World.People.Person`, job `:driver`) as a process, with its
  vehicle. A haul takes the parts from the dock of a place to the dock of
  another: the driver loads the truck up to its capacity,
  drives on the road, unloads, and drives back for the next load. The
  drive is real time: the driver waits the time of the drive in the world
  over the scale of the clock. After each unload, the driver tells the
  foreman what is at the dock.
  """
  use GenServer

  alias World.{Clock, Yard}
  alias World.Log.Server

  @doc """
  Start a driver. The options: `name`, `vehicle` (its name in the yard),
  `yard`, `log`.
  """
  def start_link(opts), do: GenServer.start_link(__MODULE__, Map.new(opts))

  @doc """
  Haul the items (`[{item, count}]`) of an order from a place to another
  (the warehouse to a factory, or a factory to another), and tell
  `foreman` each unload (`{:unloaded, order, item, count}`), then
  `{:hauled, driver}`.
  """
  def haul(driver, order, items, from, to, foreman),
    do: GenServer.cast(driver, {:haul, order, items, from, to, foreman})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:haul, order, items, from, to, foreman}, d) do
    capacity = d.yard.vehicles[d.vehicle].capacity

    items
    |> Enum.flat_map(fn {item, n} -> List.duplicate(item, n) end)
    |> Enum.chunk_every(capacity)
    |> Enum.each(fn trip ->
      load = Enum.frequencies(trip)
      for {item, n} <- load, do: record(d, "loaded", order, from, %{"item" => item, "count" => n})
      drive(d, order, from, to)

      for {item, n} <- load do
        record(d, "unloaded", order, to, %{"item" => item, "count" => n})
        send(foreman, {:unloaded, order, item, n})
      end

      drive(d, order, to, from)
    end)

    send(foreman, {:hauled, self()})
    {:noreply, d}
  end

  defp drive(d, order, from, to) do
    {:ok, ms} = Yard.drive(d.yard, d.vehicle, from, to)
    record(d, "departed", order, from, %{"from" => from, "to" => to, "world_ms" => ms})
    Process.sleep(Clock.to_wall(d.yard.clock, ms))
    record(d, "arrived", order, to, %{"from" => from, "to" => to})
  end

  defp record(d, kind, order, place, data),
    do: Server.record(d.log, kind, order: order, place: place, who: d.name, data: Map.put(data, "vehicle", d.vehicle))
end
