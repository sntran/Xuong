defmodule World.PlantsTest do
  use ExUnit.Case, async: true

  alias World.Buildings.Plants
  alias World.{Places, Run}

  @mib 1024 * 1024

  test "a rack holds 64 MiB: the racks of a store" do
    assert Plants.rack_bytes() == 64 * @mib
    assert Plants.racks(0) == 1 and Plants.racks(64 * @mib) == 1 and Plants.racks(64 * @mib + 1) == 2
    assert Plants.racks(1_000_000_000) == 15
  end

  test "a larger store makes a longer warehouse, with its racks in it" do
    small = Plants.warehouse("a", 100 * @mib)
    large = Plants.warehouse("b", 2_000 * @mib)
    assert small.extras["racks"] == 2 and large.extras["racks"] == 32
    assert small.extras["length"] == 6.0 and large.extras["length"] > 15
    assert small.kind == :house and Places.family_of(small) == :houses

    racks = for {"rack_" <> _, _, _} <- large.nodes, do: 1
    assert length(racks) == 32

    # The racks stand in the building: inside its walls.
    {{x0, y0, _}, {x1, y1, _}} = World.Scene.bounds(World.Build.scene(large))
    assert x1 - x0 < large.extras["length"] + 1.0 and y1 - y0 < large.extras["depth"] + 1.0
  end

  test "a factory has room for its workers, and the building of a place comes from the yard" do
    assert Plants.factory("f", 1).extras["length"] == 8.0 and Plants.factory("f", 4).extras["length"] == 16.0
    yard = Run.yard(limit: 64 * @mib)
    assert Plants.of(yard, "warehouse").extras["racks"] == 1
    assert Plants.of(yard, "vehicles").extras["workers"] == 2
    assert Plants.of(yard, "houses").name == "building_houses"
  end
end
