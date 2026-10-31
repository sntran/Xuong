defmodule World.Buildings.Plants do
  @moduledoc """
  The buildings of the places of the world (`docs/world.md`, step W5): a
  warehouse and a factory are houses of `World.Buildings` (walls of 2x4
  studs, a metal roof, a door at the left end), and the people of the
  world build them as orders (`World.Run.build/3`).

  - The size of a warehouse comes from the limit of its store. One rack
    of strut channel (`World.Framing.Builds.strut_wall_rack/0`) holds
    64 MiB of files: a full rack is a full store (a number of the world,
    not a measurement). The racks stand in two rows, along the long walls,
    0.9 m apart, with an aisle between the rows.
  - A factory has 3 m of its length for each worker.

  The size of a building is in its extras: `racks`, `limit`, `workers`,
  `length` and `depth` (meters).
  """
  alias World.{Assembly, Buildings, Part, Vec}
  alias World.Framing.Builds
  alias World.Places.Place

  # The bytes of files on one rack.
  @rack_bytes 64 * 1024 * 1024
  @inch 0.0254
  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  @doc "The bytes of files on one rack of a warehouse."
  def rack_bytes, do: @rack_bytes

  @doc "The count of the racks of a warehouse with a store of `limit` bytes: one at least."
  def racks(limit) when is_integer(limit) and limit >= 0, do: max(1, div(limit + @rack_bytes - 1, @rack_bytes))

  @doc "The building of a place of a yard (`World.Yard`): a warehouse or a factory."
  def of(yard, name) do
    case Map.fetch!(yard.places, name) do
      %Place{kind: :warehouse, stock: stock} ->
        warehouse(name, stock.limit)

      %Place{kind: :factory} ->
        workers = Enum.count(yard.people, fn {_, p} -> p.place == name and p.job == :worker end)
        factory(name, workers)
    end
  end

  @doc "A warehouse for a store of `limit` bytes, with its racks."
  def warehouse(name, limit) do
    n = racks(limit)
    per_row = div(n + 1, 2)
    {length, depth} = {max(6.0, per_row * 0.9 + 2.0), 6.0}

    house =
      building("building_" <> name, length, depth)
      |> Map.update!(:extras, &Map.merge(&1, %{"racks" => n, "limit" => limit}))

    rack = Builds.strut_wall_rack()

    # The back row looks to +y, the front row to -y; the racks start 1 m
    # from the left end, where the door is.
    for i <- 0..(n - 1), reduce: house do
      house ->
        x = -length / 2 + 1.45 + div(i, 2) * 0.9

        {at, dir} =
          if rem(i, 2) == 0,
            do: {{x, -depth / 2 + 0.15, 0.1}, {1, 0, 0}},
            else: {{-x, depth / 2 - 0.15, 0.1}, {-1, 0, 0}}

        # The port of the rack: its z up, its y (z by x) to the room.
        Assembly.add(house, "rack_#{i + 1}", rack,
          at: Part.port("rack_#{i + 1}", at, {0, 0, 1}, Vec.cross({0, 0, 1}, dir)),
          port: @o
        )
    end
  end

  @doc "A factory with room for its workers."
  def factory(name, workers) when is_integer(workers) and workers >= 0 do
    building("building_" <> name, max(8.0, 3.0 * workers + 4.0), 8.0)
    |> Map.update!(:extras, &Map.put(&1, "workers", workers))
  end

  defp building(name, length, depth) do
    door = {:door, depth / 2, 36 * @inch, 80 * @inch}

    Buildings.house(name,
      length: length,
      depth: depth,
      wall: :studs,
      wall_height: 3.0,
      roof: :metal,
      pitch: 4 / 12,
      overhang: 12 * @inch,
      openings: %{left: [door]},
      sources: ["A building of the world: its size from its store or its workers (World.Buildings.Plants)."]
    )
    |> Map.update!(:extras, &Map.merge(&1, %{"length" => length, "depth" => depth}))
  end
end
