defmodule World.Yard do
  @moduledoc """
  The yard of the world (`docs/world.md`): its places, the roads between
  them, its people, its vehicles and its clock. A road is a straight line
  between two places, with a speed limit (20 km/h on the yard). A
  vehicle drives at its top speed or at the limit, at the less of the two.
  """
  alias World.{Clock, Places}
  alias World.People.Person
  alias World.Places.Place
  alias World.Vehicles.Vehicle

  # The speed limit of a road of the yard, in km/h.
  @limit 20

  defmodule Road do
    @moduledoc "A road between two places: its length in meters and its speed limit in km/h."
    defstruct from: nil, to: nil, length: 0.0, limit: 20
  end

  defstruct places: %{}, roads: %{}, people: %{}, vehicles: %{}, clock: nil

  @doc "An empty yard. The option `clock` (`World.Clock.new/0` by default)."
  def new(opts \\ []), do: %__MODULE__{clock: Keyword.get_lazy(opts, :clock, &Clock.new/0)}

  @doc "Add a place, a person or a vehicle. A second thing with one name is an error."
  def add(%__MODULE__{} = yard, %Place{name: name} = p), do: put(yard, :places, name, p)

  def add(%__MODULE__{} = yard, %Person{name: name, place: place} = p) do
    known!(yard, place)
    put(yard, :people, name, p)
  end

  def add(%__MODULE__{} = yard, %Vehicle{name: name, place: place} = v) do
    if place, do: known!(yard, place)
    put(yard, :vehicles, name, v)
  end

  defp put(yard, key, name, thing) do
    things = Map.fetch!(yard, key)
    if Map.has_key?(things, name), do: raise(ArgumentError, "the yard has #{name} already")
    Map.put(yard, key, Map.put(things, name, thing))
  end

  defp known!(yard, place) do
    unless Map.has_key?(yard.places, place), do: raise(ArgumentError, "the yard has no place #{inspect(place)}")
  end

  @doc "Add a road both ways between two places. The option `limit` (km/h, 20 by default)."
  def road(%__MODULE__{places: places} = yard, from, to, opts \\ []) do
    known!(yard, from)
    known!(yard, to)
    length = Places.distance(places[from], places[to])
    limit = Keyword.get(opts, :limit, @limit)

    roads =
      Map.merge(yard.roads, %{{from, to} => way(from, to, length, limit), {to, from} => way(to, from, length, limit)})

    %{yard | roads: roads}
  end

  defp way(from, to, length, limit), do: %Road{from: from, to: to, length: length, limit: limit}

  @doc """
  The yard as data for the head of a log and for its replay: the places
  (name, kind, family, position, and the limit of the store of a
  warehouse), the roads, the people (name, job,
  place, station) and the vehicles (name, model, place, driver).
  """
  def describe(%__MODULE__{} = yard) do
    %{
      "places" =>
        for(
          {_, p} <- Enum.sort(yard.places),
          do: %{
            "name" => p.name,
            "kind" => Atom.to_string(p.kind),
            "family" => p.family && Atom.to_string(p.family),
            "at" => Tuple.to_list(p.at),
            "limit" => p.stock && p.stock.limit
          }
        ),
      "roads" =>
        for(
          {{a, b}, r} <- Enum.sort(yard.roads),
          a < b,
          do: %{"from" => a, "to" => b, "length" => r.length, "limit" => r.limit}
        ),
      "people" =>
        for(
          {_, p} <- Enum.sort(yard.people),
          do: %{"name" => p.name, "job" => Atom.to_string(p.job), "place" => p.place, "station" => p.station}
        ),
      "vehicles" =>
        for(
          {_, v} <- Enum.sort(yard.vehicles),
          do: %{"name" => v.name, "model" => v.model, "place" => v.place, "driver" => v.driver}
        )
    }
  end

  @doc "The road from a place to another: `{:ok, road}` or `{:error, :no_road}`."
  def route(%__MODULE__{roads: roads}, from, to) do
    case Map.fetch(roads, {from, to}) do
      {:ok, r} -> {:ok, r}
      :error -> {:error, :no_road}
    end
  end

  @doc """
  The world time of a drive of a vehicle on the road from a place to
  another, in milliseconds: the length of the road over the speed.
  """
  def drive(%__MODULE__{} = yard, vehicle, from, to) do
    with {:ok, road} <- route(yard, from, to) do
      speed = min(Map.fetch!(yard.vehicles, vehicle).speed, road.limit) / 3.6
      {:ok, round(road.length / speed * 1000)}
    end
  end
end
