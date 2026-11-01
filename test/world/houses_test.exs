defmodule World.HousesTest do
  use ExUnit.Case, async: true

  alias World.Assembly

  alias World.Build

  alias World.Detail

  alias World.Part

  alias World.Scene

  alias World.{Buildings, Vec}
  alias World.Materials.Construction

  defp counts(model), do: Map.new(Build.parts(model), &{&1["name"], &1["count"]})
  defp scene(fun, level), do: Build.scene(Detail.with(level, fun), level: level)
  defp size(%Part{} = p), do: p |> Part.bounds() |> then(fn {lo, hi} -> Vec.sub(hi, lo) end)

  describe "the materials" do
    test "the units of masonry, whole and cut" do
      assert Construction.units() == ["brick_us_modular", "brick_vn", "cmu_8"]
      assert %{l: 0.22, w: 0.105, h: 0.06, joint: 0.01, material: :brick} = Construction.unit("brick_vn")

      brick = Construction.masonry("brick_vn")
      half = Construction.masonry("brick_vn", 0.1)
      assert brick.name == half.name and brick.params == half.params
      assert {x, _, _} = size(half)
      assert_in_delta x, 0.1, 1.0e-9

      # A block has two face shells and three webs; a short cut has two.
      assert length(Construction.masonry("cmu_8").shapes) == 5
      assert length(Construction.masonry("cmu_8", 0.2).shapes) == 4
      assert_raise KeyError, fn -> Construction.unit("adobe") end
    end

    test "a lintel, a roof tile, a metal panel and a hinge" do
      lintel = Construction.lintel(1.2, 0.22, 0.13)
      assert lintel.name == "lintel_1200x220x130"

      assert {1.2, 0.22, 0.13} =
               size(lintel) |> then(fn {a, b, c} -> {Float.round(a, 6), Float.round(b, 6), Float.round(c, 6)} end)

      assert Construction.roof_tile().name == "roof_tile_clay_424x335"

      panel = Construction.metal_panel(2.3)
      {{x0, y0, z0}, {x1, y1, z1}} = Part.bounds(panel)
      assert_in_delta x0, 0.0, 1.0e-9
      assert_in_delta x1, 0.9144, 1.0e-9
      assert_in_delta y0, 0.0, 1.0e-9
      assert_in_delta y1, 2.3, 1.0e-9
      assert z0 >= -1.0e-9 and z1 > 0.03

      assert Construction.hinge().detail == :near
    end
  end

  describe "the walls" do
    test "a wall of bricks with a window and its lintel" do
      parts = counts(Buildings.wall_brick_sample())
      # 2 by 1.47 m less the window and the lintel: about 62 bricks to the
      # square meter, with the cut bricks.
      assert parts["brick_vn"] in 140..180
      assert parts["lintel_1100x105x130"] == 1
      refute Map.has_key?(parts, "wall_brick_sample_low")
    end

    test "a wall of two wythes with a gable has more bricks over its top" do
      flat = counts(Buildings.masonry_wall("w", "brick_vn", 2.0, 1.4, wythes: 2))["brick_vn"]
      gable = counts(Buildings.masonry_wall("w", "brick_vn", 2.0, 1.4, wythes: 2, gable: 0.5))["brick_vn"]
      assert flat in 350..400
      # The gable: a triangle of 2 by 0.5 m, of two wythes.
      assert (gable - flat) in 50..80
    end

    test "a wall with no options: one wythe, no opening, no gable" do
      assert counts(Buildings.masonry_wall("w", "brick_vn", 0.92, 0.28))["brick_vn"] in 16..20
      assert counts(Buildings.stud_wall("w", 1.22, 2.467))["lumber_2x4x2353"] == 4
    end

    test "a hole that covers a whole sheet saves the sheet" do
      osb = fn wall -> hd(for {_, %Part{name: "osb_7_16"} = p, _} <- wall.nodes, do: p).params["sheets_4x8"] end
      assert osb.(Buildings.stud_wall("w", 2.44, 2.4)) == 2
      assert osb.(Buildings.stud_wall("w", 2.44, 2.4, openings: [{:hole, 0.0, 1.3, 0.0, 2.4}])) == 1
    end

    test "a wall of concrete blocks" do
      parts = counts(Buildings.wall_cmu_sample())
      assert parts["cmu_8"] in 30..50
    end

    test "a wall of studs with a door, a window and a gable" do
      wall =
        Buildings.stud_wall("w", 3.6, 2.467,
          openings: [{:door, 0.5, 0.95, 0.0, 2.08}, {:window, 2.2, 0.91, 0.91, 1.22}],
          gable: 0.6
        )

      parts = counts(wall)
      names = for {name, _, _} <- wall.nodes, do: name

      # The bottom plate stops at the door: two pieces.
      assert Enum.count(names, &String.starts_with?(&1, "plate_bottom")) == 2
      assert Enum.count(names, &String.starts_with?(&1, "king_")) == 4
      assert Enum.count(names, &String.starts_with?(&1, "header_")) == 4
      assert "sill_2" in names
      refute "sill_1" in names
      assert Enum.any?(names, &String.starts_with?(&1, "gable_stud_"))
      assert parts["lap_siding_8in"] > 30
      [osb] = for {_, %Part{name: "osb_7_16"} = p, _} <- wall.nodes, do: p
      assert osb.params["sheets_4x8"] in 4..8
    end

    test "the low levels have a solid wall in place of the bricks" do
      near = scene(&Buildings.wall_brick_sample/0, :near)
      far = scene(&Buildings.wall_brick_sample/0, :far)
      assert Scene.triangles(near) > 10 * Scene.triangles(far)
      assert Scene.triangles(far) > 0
    end
  end

  describe "the doors and the windows" do
    test "a door opens to the inside, and its knob turns" do
      door = World.Openings.prehung_sample()
      roles = for {_, _, %{role: r}} <- door.nodes, r, do: r
      assert Enum.sort(roles) == [:door, :knob]
      assert counts(door)["hinge_3_5in"] == 3
      assert World.Openings.prehung_opening(0.9144, 2.032) |> elem(0) > 0.9144
    end

    test "a casement window and a fixed window" do
      assert [_, {"sash_window_casement_36x48", _, %{kind: :hinge}}] = World.Openings.window_sample().nodes
      assert [_, {"sash_f", _, %{kind: :fixed}}] = World.Openings.window("f", 0.6, 0.9, 0.11, :fixed).nodes
    end
  end

  describe "the houses" do
    test "the house of bricks of Việt Nam: its bricks, its tiles and its levels" do
      parts = counts(Buildings.house_brick_vn())
      assert parts["brick_vn"] in 6000..8000
      assert parts["roof_tile_clay_424x335"] in 350..450
      assert parts["window_frame_39x47"] == 3

      near = scene(&Buildings.house_brick_vn/0, :near)
      mid = scene(&Buildings.house_brick_vn/0, :mid)
      far = scene(&Buildings.house_brick_vn/0, :far)
      assert Scene.triangles(near) <= 300_000
      assert Scene.triangles(mid) <= 20_000 and Scene.triangles(far) <= 12_000
      assert [w, d, h] = near.extras["size"]
      assert_in_delta w, 7.1, 0.1
      assert_in_delta d, 5.4, 0.2
      assert_in_delta h, 4.3, 0.2
      assert near.extras["kind"] == "house"
      assert Enum.count(near.nodes, &(&1.extras["role"] == "door")) == 5
    end

    test "the cabin of wood: its lumber, its siding and its metal roof" do
      parts = counts(Buildings.cabin_wood_frame())
      assert parts["metal_panel_pbr_2300"] == 14
      assert parts["lap_siding_8in"] > 80
      assert parts["door_slab_36x80"] == 1

      far = scene(&Buildings.cabin_wood_frame/0, :far)
      assert Scene.triangles(far) <= 12_000
    end
  end

  test "an assembly takes many nodes at one time, each with its own name" do
    a = Assembly.new("a", Part.new("m", :mark, [], [Part.port("o", {0, 0, 0}, {0, 0, 1})]), root: "m")
    p = Construction.masonry("brick_vn")

    a =
      Assembly.add_all(
        a,
        for(i <- 1..3, do: {"b#{i}", p, [at: Part.port("x", {i, 0, 0}, {0, 0, 1}, {0, 1, 0}), port: "o"]})
      )

    assert length(a.nodes) == 4
    assert counts(a) == %{"brick_vn" => 3}

    assert_raise ArgumentError, ~r/has a node b1 already/, fn ->
      Assembly.add_all(a, [{"b1", p, [at: "o", port: "o"]}])
    end
  end
end
