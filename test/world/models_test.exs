defmodule World.ModelsTest do
  use ExUnit.Case, async: true

  alias World.Build

  alias World.Detail

  alias World.Scene
  # The size of each vehicle from its data page: {width, length, height}
  # in meters, and the tolerance. The width of a model has its mirrors.
  @sizes %{
    "honda_vision_110" => {{0.686, 1.871, 1.101}, 0.03},
    "chevy_bolt_ev" => {{1.98, 4.145, 1.611}, 0.06},
    "ford_transit_148_camper" => {{2.4, 5.98, 2.87}, 0.1},
    "royal_enfield_himalayan" => {{0.84, 2.19, 1.37}, 0.08},
    "touring_bicycle" => {{0.44, 1.72, 1.04}, 0.05}
  }

  @limits %{near: 50_000, mid: 12_000, far: 5_000}

  for {name, fun} <- World.Catalog.models(), Map.has_key?(@sizes, name) do
    @name name
    @fun fun

    test "#{name}: the size, the levels, the joints and the parts" do
      scenes = for level <- [:near, :mid, :far], do: {level, Build.scene(Detail.with(level, @fun), level: level)}

      for {level, scene} <- scenes do
        tris = Scene.triangles(scene)
        assert tris <= @limits[level], "#{@name} has #{tris} triangles at #{level}"
      end

      [{:near, near}, {:mid, mid}, {:far, far}] = scenes
      assert Scene.triangles(near) > Scene.triangles(mid) and Scene.triangles(mid) > Scene.triangles(far)

      {{w, l, h}, tol} = @sizes[@name]
      [sw, sl, sh] = near.extras["size"]
      assert abs(sw - w) <= tol and abs(sl - l) <= tol and abs(sh - h) <= tol, "#{@name}: #{inspect([sw, sl, sh])}"

      roles = for n <- near.nodes, r = n.extras["role"], do: r
      assert Enum.count(roles, &(&1 == "wheel")) >= 2
      assert "steer" in roles
      assert near.extras["kind"] == "vehicle"
      assert near.extras["sources"] != []
      assert Build.parts(@fun.()) != []
    end
  end

  # Each van has the size of Ford: the length and the height of the data,
  # and the width with its mirrors.
  for name <- World.Vehicles.Van.models() do
    @name name

    test "the van #{name}: its size, its levels and its doors" do
      m = World.Vehicles.Van.model(@name)
      fun = fn -> World.Vehicles.Van.build(@name) end
      scenes = for level <- [:near, :mid, :far], do: {level, Build.scene(Detail.with(level, fun), level: level)}

      # The windows all around fit in the limits too.
      passenger = fn -> World.Vehicles.Van.build(@name, windows: :passenger) end

      for level <- [:near, :mid, :far],
          scene <- [Keyword.fetch!(scenes, level), Build.scene(Detail.with(level, passenger), level: level)] do
        tris = Scene.triangles(scene)
        assert tris <= @limits[level], "#{@name} has #{tris} triangles at #{level}"
      end

      [{:near, near} | _] = scenes
      [sw, sl, sh] = near.extras["size"]
      assert abs(sl - m["length"]) <= 0.06 and abs(sh - m["height"]) <= 0.05, inspect(near.extras["size"])
      assert sw > m["width"] and sw < m["width"] + 0.5

      van = fun.()
      joints = for {name, _, %{kind: kind}} <- van.nodes, into: %{}, do: {name, kind}
      assert %{"sliding_door" => :slide, "rear_door_right" => :hinge, "rear_door_left" => :hinge} = joints
    end
  end

  test "the hull of a van: its span, its sections and its back" do
    alias World.Vehicles.Hull
    h = World.Vehicles.Van.hull("transit_148")
    {d0, d1} = Hull.span(h)
    assert d0 < 0.01 and abs(d1 - h.length) < 0.01
    assert Hull.z_high(h, 3.0) == h.top
    assert Hull.half_width(h, 3.0) == h.width / 2 and Hull.half_width(h, d1) < h.width / 2

    # The back steps to the front over the bumper, and has no face over the top.
    assert Hull.back(h, 0.7) < Hull.back(h, 1.6)
    assert Hull.back(h, h.top + 1.0) == nil

    # The arch of a wheel raises the bottom of the hull over it.
    {f, _, _} = hd(h.arches)
    assert Hull.z_low(h, f) > Hull.z_low(h, f, false)

    # A sheet of the side of the hull, cut by the arch of the wheel.
    sheet = Hull.shell(h, f - 0.8, f + 0.8, :paint)
    assert length(sheet) > 1 and Enum.all?(sheet, &(World.Mesh.volume(&1.points, &1.faces) > 0))

    # A door between the sill and the roof: the parts of the sheet over and
    # under it are pieces of their own, with no face across the door.
    door = fn _ -> [[{:x_min, 0.5}, {:z_min, 0.42}, {:z_max, 2.36}]] end
    sheet = Hull.shell(h, 2.0, 3.5, :paint, holes: door, edges: [2.0, 3.5])

    across =
      for mesh <- sheet, pts = List.to_tuple(mesh.points), f <- mesh.faces, ps = Enum.map(f, &elem(pts, &1)) do
        {zs, xs} = {Enum.map(ps, &elem(&1, 2)), Enum.map(ps, &elem(&1, 0))}
        Enum.max(zs) - Enum.min(zs) > 1.5 and Enum.max(xs) - Enum.min(xs) < 1.0e-6
      end

    refute Enum.any?(across)

    # A section is a closed loop, and a wider skin is bigger.
    section = Hull.section(h, 3.0)
    assert length(section) > 8
    assert Hull.area(Hull.section(h, 3.0, 0.01)) > Hull.area(section)
  end

  test "the cab of a van has the seats of its body: the front seats, a row more in the crew van" do
    seats = fn windows ->
      van = Detail.with(:near, fn -> World.Vehicles.Van.build("transit_148", windows: windows) end)
      for {name, %World.Assembly{kind: :seat}, c} <- van.nodes, do: {name, c.to, c.at}
    end

    front = [{"driver", "inside", "seat_driver"}, {"passenger", "inside", "seat_passenger"}]
    assert seats.(:cargo) == front
    assert seats.(:crew) == front ++ [{"row_2", "inside", "row_2"}]
    assert length(seats.(:passenger)) == 5

    # The front seats move on their tracks, and their backs recline.
    van = Detail.with(:near, fn -> World.Vehicles.Van.build("transit_148") end)
    joints = Build.scene(van).extras["joints"]
    assert "driver_seat" in joints and "passenger_back" in joints
  end

  test "a skin over rings of other counts of points joins them by their places" do
    rings = [
      [{{0, 0, 0}, 0}, {{1, 0, 0}, 1}, {{1, 1, 0}, 2}, {{0, 1, 0}, 3}],
      [{{0, 0, 1}, 0}, {{1, 0, 1}, 1}, {{1, 0.5, 1}, 1.5}, {{1, 1, 1}, 2}, {{0, 1, 1}, 3}]
    ]

    mesh = World.Shape.stitch(rings, :paint)
    # Each line between two points is in two faces: the skin is closed.
    edges = for f <- mesh.faces, [u, v] <- Enum.chunk_every(f ++ [hd(f)], 2, 1, :discard), do: {u, v}
    assert Enum.all?(edges, &({elem(&1, 1), elem(&1, 0)} in edges))
    assert_in_delta World.Mesh.volume(mesh.points, mesh.faces) / 6, 1.0, 1.0e-9

    # A ring with its places far along the sheet: the other ring moves
    # before the first ring finishes, and the skin stays closed.
    late = for {{p, _}, s} <- Enum.zip(hd(rings), [0, 3, 3.3, 3.6]), do: {World.Vec.add(p, {0, 0, 1}), s}
    mesh = World.Shape.stitch([hd(rings), late], :paint)
    edges = for f <- mesh.faces, [u, v] <- Enum.chunk_every(f ++ [hd(f)], 2, 1, :discard), do: {u, v}
    assert Enum.all?(edges, &({elem(&1, 1), elem(&1, 0)} in edges))
  end

  test "the hood of the van opens on the engine bay, with the items of DIY in it" do
    van = World.Vehicles.FordTransit.model()
    assert {_, _, %{kind: :hinge, role: :lid, limits: [0, 60]}} = List.keyfind(van.nodes, "hood", 0)

    parts = Map.new(Build.parts(van), &{&1["name"], &1["count"]})
    assert parts["redarc_bcdc1250d"] == 1 and parts["second_alternator_250a"] == 1
    assert parts["engine_ford_3_5_v6"] == 1 and parts["radiator_fan_transit"] == 1

    # The parts in the bay are only in the near level: at mid, the joint of
    # the fan stays, with no mesh.
    fan = fn level ->
      scene = Build.scene(Detail.with(level, &World.Vehicles.FordTransit.model/0), level: level)
      Enum.find(scene.nodes, &(&1.name == "radiator_fan")).primitives
    end

    assert fan.(:near) != [] and fan.(:mid) == []
  end

  test "the level of detail" do
    assert Detail.level() == :near

    assert Detail.with(:far, fn -> {Detail.level(), Detail.sides(24), Detail.smooth(2), Detail.step(0.1)} end) ==
             {:far, 6, 0, 0.4}

    assert Detail.with(:mid, fn -> {Detail.sides(4), Detail.smooth(2)} end) == {4, 1}
    assert Detail.with(:mid, fn -> Detail.with(:far, fn -> :ok end) && Detail.level() end) == :mid
    assert Detail.level() == :near
  end

  test "a body loft with arches is closed" do
    mesh = World.Vehicles.Body.loft([{0.0, 0.2, 1.0, 0.8, 4}, {2.0, 0.2, 1.0, 0.8, 4}], [{1.0, 0.3, 0.35}], :paint)
    tris = World.Mesh.triangles(mesh)
    assert length(tris) > 100
    # The bottom over the axle is above the top of the wheel.
    low = for {{_, y, z}, _} <- tris, abs(y - 1.0) < 0.01, do: z
    assert Enum.min(low) >= 0.3 + 0.35 - 0.05
  end
end
