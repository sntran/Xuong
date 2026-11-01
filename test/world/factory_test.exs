defmodule World.FactoryTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias World.Orders.Blueprint

  alias World.Orders.Blueprints

  alias World.Orders
  defp paths({:error, errors}), do: Enum.map(errors, & &1["path"])

  describe "the options of a blueprint" do
    test "each type, from JSON and from the query of a URL" do
      num = Blueprint.option("n", :number, min: 0.0, max: 2.0, unit: "m")
      int = Blueprint.option("i", :integer, min: 1, max: 3)
      assert Blueprint.value(num, 1, "n") == {:ok, 1.0}
      assert Blueprint.value(num, "1.5", "n") == {:ok, 1.5}
      assert {:error, [{"n", "must be from 0.0 to 2.0 m"}]} = Blueprint.value(num, 3, "n")
      assert {:error, [{"n", "must be a number"}]} = Blueprint.value(num, "x", "n")
      assert {:error, [{"n", "must be a number"}]} = Blueprint.value(num, nil, "n")
      assert Blueprint.value(int, "2", "i") == {:ok, 2}
      assert Blueprint.value(int, 2.0, "i") == {:ok, 2}
      assert {:error, [{"i", "must be an integer"}]} = Blueprint.value(int, 2.5, "i")

      yes = Blueprint.option("b", :boolean)
      assert Blueprint.value(yes, "true", "b") == {:ok, true}
      assert Blueprint.value(yes, "false", "b") == {:ok, false}
      assert Blueprint.value(yes, true, "b") == {:ok, true}
      assert {:error, _} = Blueprint.value(yes, 1, "b")

      color = Blueprint.option("c", :color)
      assert Blueprint.value(color, "#AbCdEf", "c") == {:ok, "#abcdef"}
      assert {:error, _} = Blueprint.value(color, "red", "c")

      list = Blueprint.option("l", :list, item: Blueprint.option("x", :choice, values: ["a", "b"]), max: 2)
      assert Blueprint.value(list, "a,b", "l") == {:ok, ["a", "b"]}
      assert Blueprint.value(list, "", "l") == {:ok, []}
      assert {:error, [{"l.1", _}]} = Blueprint.value(list, ["a", "c"], "l")
      assert {:error, [{"l", "must have at most 2 items"}]} = Blueprint.value(list, ["a", "a", "a"], "l")
      assert {:error, [{"l", "must be a list"}]} = Blueprint.value(list, 3, "l")

      # A list with presets takes the name of a preset in place of the list.
      preset = %{list | presets: ["ab"]}
      assert Blueprint.value(preset, "ab", "l") == {:ok, "ab"}
      assert Blueprint.value(preset, "a", "l") == {:ok, ["a"]}
    end

    test "an object: its fields, a field that is required, a field that is not known" do
      fields = [Blueprint.option("a", :number), Blueprint.option("b", :number, default: 2.0)]
      assert Blueprint.check_options(fields, %{"a" => 1}, "o") == {:ok, %{"a" => 1.0, "b" => 2.0}}
      assert Blueprint.check_options(fields, %{}, "o") == {:error, [{"o.a", "is required"}]}
      assert {:error, [{"o.z", "is not an option"}, _]} = Blueprint.check_options(fields, %{"z" => 1}, "o")
      assert Blueprint.check_options(fields, [], "o") == {:error, [{"o", "must be an object"}]}
      assert Blueprint.check_options(fields, %{"a" => "x"}, "o") == {:error, [{"o.a", "must be a number"}]}
    end

    test "each blueprint describes its options as JSON" do
      for b <- Blueprints.all() do
        d = Blueprint.describe(b)
        assert d["name"] == b.name and d["options"] != []
        assert Orders.encode(d) |> JSON.decode!() |> is_map()
      end

      [house] = for b <- Blueprints.all(), b.name == "house", do: Blueprint.describe(b)
      openings = Enum.find(house["options"], &(&1["name"] == "openings"))
      assert openings["item"]["fields"] |> Enum.map(& &1["name"]) == ~w(wall kind x width height sill)
      assert Blueprints.fetch("nope") == :error
    end
  end

  describe "an order" do
    test "the full order has each default, and the same order gives the same hash" do
      {:ok, a} = Orders.check(%{"blueprint" => "extrusion", "options" => %{"profile" => "2020", "length" => "0.5"}})
      {:ok, b} = Orders.check(%{"options" => %{"length" => 0.5, "profile" => "2020"}, "blueprint" => "extrusion"})
      assert a == b and Orders.hash(a) == Orders.hash(b)

      assert a == %{
               "blueprint" => "extrusion",
               "options" => %{"length" => 0.5, "profile" => "2020"},
               "colors" => %{},
               "joints" => %{}
             }

      assert Orders.hash(a) =~ ~r/^[0-9a-f]{32}$/
    end

    test "the errors of an order" do
      assert paths(Orders.check([])) == [""]
      assert paths(Orders.check(%{"blueprint" => "nope"})) == ["blueprint"]
      assert paths(Orders.check(%{"blueprint" => "strut", "x" => 1})) == ["x"]
      assert paths(Orders.check(%{"blueprint" => "strut"})) == ["options.length"]

      assert paths(
               Orders.check(%{
                 "blueprint" => "l_track",
                 "options" => %{"length" => 1},
                 "colors" => %{"nope" => "#000000", "aluminum" => "x"}
               })
             ) ==
               ["colors.aluminum", "colors.nope"]

      assert paths(Orders.check(%{"blueprint" => "l_track", "options" => %{"length" => 1}, "colors" => []})) == [
               "colors"
             ]

      assert paths(Orders.check(%{"blueprint" => "l_track", "options" => %{"length" => 1}, "joints" => %{"a" => "x"}})) ==
               ["joints.a"]

      assert paths(Orders.check(%{"blueprint" => "l_track", "options" => %{"length" => 1}, "joints" => 1})) == [
               "joints"
             ]
    end

    test "a house checks its openings" do
      opening = fn x -> %{"wall" => "left", "kind" => "window", "x" => x, "width" => 1.0, "height" => 1.2} end

      assert {:ok, _} =
               Orders.check(%{
                 "blueprint" => "house",
                 "options" => %{"wall" => "studs", "openings" => [opening.(2.0)]}
               })

      assert paths(Orders.check(%{"blueprint" => "house", "options" => %{"openings" => [opening.(3.9)]}})) == [
               "options.openings.0"
             ]

      tall = %{"wall" => "front", "kind" => "door", "x" => 3.0, "width" => 0.9, "height" => 2.4}

      assert paths(Orders.check(%{"blueprint" => "house", "options" => %{"wall_height" => 2.5, "openings" => [tall]}})) ==
               ["options.openings.0"]
    end

    test "a van checks the items on its roof" do
      roof = fn items -> %{"blueprint" => "van", "options" => %{"roof" => items}} end
      solar = fn at -> %{"kind" => "solar", "at" => at} end
      fan = fn at -> %{"kind" => "fan", "at" => at} end

      assert {:ok, _} = Orders.check(roof.([solar.(3.75), fan.(5.15)]))
      assert paths(Orders.check(roof.([solar.(2.5)]))) == ["options.roof.0"]
      assert paths(Orders.check(roof.([fan.(5.5)]))) == ["options.roof.0"]
      assert paths(Orders.check(roof.([solar.(3.75), fan.(4.8)]))) == ["options.roof.1"]
    end

    test "a van takes its sizes from the order, near those of the model" do
      size = fn s -> %{"blueprint" => "van", "options" => %{"model" => "sprinter_144", "size" => s}} end

      # The height of Mercedes-Benz Australia, under the height of the US page.
      assert {:ok, _} = Orders.check(size.(%{"height" => 2.331}))
      assert paths(Orders.check(size.(%{"height" => 2.2}))) == ["options.size.height"]
      assert paths(Orders.check(size.(%{"width" => 1.9, "length" => 5.932}))) == ["options.size.width"]
      assert World.Vehicles.Van.sizes("sprinter_144")["height"] == {2.328, 2.84}
    end

    test "a van takes its doors, its windows and its rows from the order, in the limits of the model" do
      van = fn o -> %{"blueprint" => "van", "options" => Map.put(o, "model", "transit_148")} end

      # The preset crew, or its windows as a list with numbers.
      assert {:ok, _} = Orders.check(van.(%{"windows" => "crew"}))
      crew = [%{"at" => "left", "to" => 2.8}, %{"at" => "slider", "top" => 2.0}, %{"at" => "rear_doors"}]
      assert {:ok, _} = Orders.check(van.(%{"windows" => crew, "rows" => 1}))
      assert paths(Orders.check(van.(%{"windows" => "glass"}))) == ["options.windows.0"]

      # A window at a place where it does not go, two at one place, one too short.
      assert paths(Orders.check(van.(%{"windows" => [%{"at" => "left", "from" => 0.8}]}))) == ["options.windows.0.from"]
      assert paths(Orders.check(van.(%{"windows" => [%{"at" => "left"}, %{"at" => "left"}]}))) == ["options.windows.1"]

      assert paths(Orders.check(van.(%{"windows" => [%{"at" => "right", "from" => 3.0, "to" => 3.2}]}))) ==
               ["options.windows.0"]

      # The doors move a little; the sliding door stays before the rear wheel.
      assert {:ok, _} = Orders.check(van.(%{"doors" => %{"sliding" => %{"from" => 1.4, "to" => 2.9}}}))
      assert paths(Orders.check(van.(%{"doors" => %{"sliding" => %{"to" => 3.4}}}))) == ["options.doors.sliding.to"]
      assert paths(Orders.check(van.(%{"doors" => %{"front" => %{"back" => 1.35}}}))) == ["options.doors.front.back"]
      assert paths(Orders.check(van.(%{"rows" => 4}))) == ["options.rows"]
    end

    test "a person needs one origin" do
      none = %{"african" => 0, "asian" => 0, "caucasian" => 0}
      assert paths(Orders.check(%{"blueprint" => "person", "options" => %{"origin" => none}})) == ["options.origin"]
      assert paths(Orders.check(%{"blueprint" => "traveler", "options" => %{"origin" => none}})) == ["options.origin"]

      # An order from a URL gives the fields of an object as strings.
      url = %{"african" => "0.5", "asian" => "0.5", "caucasian" => "0"}

      assert {:ok, %{"options" => %{"origin" => %{"african" => 0.5}}}} =
               Orders.check(%{"blueprint" => "traveler", "options" => %{"origin" => url}})
    end
  end

  describe "a build" do
    test "the files of an order, with its colors and its joints" do
      order = %{
        "blueprint" => "catalog",
        "options" => %{"name" => "victron_lynx_distributor"},
        "colors" => %{"blue" => "#FF0000"},
        "joints" => %{"cover" => 30}
      }

      file = fn name ->
        {:ok, bin} = Orders.build(order, "far", name)
        bin
      end

      glb = file.("glb")
      assert <<"glTF", _::binary>> = glb
      json = World.GLBHelper.json(glb)
      blue = Enum.find(json["materials"], &(&1["name"] == "blue"))
      assert hd(blue["pbrMetallicRoughness"]["baseColorFactor"]) == 1.0

      receipt = JSON.decode!(file.("receipt"))
      assert receipt["hash"] == Orders.hash(elem(Orders.check(order), 1))
      assert receipt["level"] == "far" and receipt["joints"] == ["cover"]
      assert receipt["order"]["colors"] == %{"blue" => "#ff0000"}
      assert JSON.decode!(file.("parts"))["parts"] != []
    end

    test "the log of an order: the people of a yard build it, and the replay has a node for each task" do
      order = %{"blueprint" => "strut", "options" => %{"length" => 0.3}}
      {:ok, json} = Orders.build(order, "far", "log")
      {:ok, log} = World.Log.from_json(json)
      assert %{"kind" => "warehouse"} = Enum.find(log.yard["places"], &(&1["name"] == "warehouse"))
      events = World.Log.events(log)
      assert hd(events).kind == "order_received"
      # The last event is the measure of the run, after the delivery.
      assert Enum.map(Enum.take(events, -2), & &1.kind) == ["delivered", "run_done"]
      hash = Orders.hash(elem(Orders.check(order), 1))
      assert Enum.all?(events, &(&1.order == hash))

      tasks =
        for %{kind: "plan_made", data: %{"tasks" => tasks}} <- events, t <- tasks, t["uses"], do: t["id"]

      {:ok, replay} = Orders.build(order, "far", "replay")
      nodes = World.GLBHelper.json(replay)["nodes"]
      assert Enum.sort(for(n <- nodes, id = n["extras"]["task"], do: id)) == Enum.sort(tasks)
    end

    test "each blueprint builds its default, or a small order" do
      orders = [
        %{
          "blueprint" => "house",
          "options" => %{"wall" => "studs", "roof" => "metal", "length" => 4.0, "depth" => 3.5, "openings" => []}
        },
        %{
          "blueprint" => "house",
          "options" => %{
            "length" => 3.5,
            "depth" => 3.0,
            "openings" => [
              %{"wall" => "front", "kind" => "door", "x" => 1.0, "width" => 0.9, "height" => 2.0},
              %{"wall" => "front", "kind" => "window", "x" => 2.5, "width" => 0.8, "height" => 1.0}
            ]
          }
        },
        %{"blueprint" => "extrusion", "options" => %{"profile" => "1515", "length" => 0.2}},
        %{"blueprint" => "strut", "options" => %{"length" => 0.3}},
        %{"blueprint" => "l_track", "options" => %{"length" => 0.3}},
        %{
          "blueprint" => "van",
          "options" => %{
            "model" => "transit_148_medium",
            "size" => %{"height" => 2.6},
            "doors" => %{"sliding" => %{"to" => 2.9}, "rear" => %{"height" => 1.6}},
            "windows" => [%{"at" => "left", "to" => 3.5}, %{"at" => "slider"}],
            "rows" => 1,
            "engine_bay" => ["dc_charger"],
            "roof" => [%{"kind" => "solar", "at" => 3.8}, %{"kind" => "fan", "at" => 5.2}]
          }
        },
        %{
          "blueprint" => "person",
          "options" => %{"hair" => "none", "pose" => "sit", "origin" => %{"african" => 0.5, "asian" => 0.5}}
        },
        %{"blueprint" => "traveler", "options" => %{"vehicle" => "car", "hair_color" => "#3b2a20"}},
        %{
          "blueprint" => "traveler",
          "options" => %{"vehicle" => "motorbike", "helmet_color" => "#c0392b", "head" => 1.5}
        },
        %{"blueprint" => "traveler", "options" => %{"vehicle" => "car", "scene" => "parked"}},
        %{"blueprint" => "exercise", "options" => %{"routine" => "yoga", "count" => 1, "seed" => 3}},
        %{"blueprint" => "person", "options" => %{"animations" => ["tai_chi"]}},
        %{"blueprint" => "person", "options" => %{"right_hand" => "fan", "left_hand" => "bottle", "hat" => "non_la"}},
        %{"blueprint" => "exercise", "options" => %{"count" => 1, "fans" => true}},
        %{
          "blueprint" => "animal",
          "options" => %{"coat" => "#2b2018", "size" => 0.8, "animations" => ["walk"]},
          "joints" => %{"tail.spread" => 20},
          "targets" => %{"front_r" => [0.07, 0.3, 0.15]}
        },
        %{"blueprint" => "animal", "options" => %{"species" => "cat", "animations" => ["wag"]}},
        %{
          "blueprint" => "animal",
          "options" => %{"species" => "macaque", "animations" => ["sit"]},
          "joints" => %{"elbow_l" => 40},
          "targets" => %{"leg_r" => [0.1, 0.05, 0.1]}
        }
      ]

      for order <- orders do
        assert {:ok, <<"glTF", _::binary>>} = Orders.build(order, "far", "glb"), inspect(order)
      end
    end

    test "an animal: each species has the animations of its body plan" do
      assert {:error,
              [
                %{
                  "path" => "options.animations.1",
                  "message" =>
                    "a cat has no animation sit: walk, run, idle, idle_low, eat, attack, jump, jump_stop, hit_l, hit_r, death, wag"
                }
              ]} =
               Orders.check(%{
                 "blueprint" => "animal",
                 "options" => %{"species" => "cat", "animations" => ["walk", "sit"]}
               })

      assert {:ok, %{"options" => %{"coat" => nil}}} =
               Orders.check(%{"blueprint" => "animal", "options" => %{"species" => "macaque"}})

      # Numbers of the shape and markings: each number in its range.

      assert {:error, [%{"path" => "options.shape.leg_length"}]} =
               Orders.check(%{
                 "blueprint" => "animal",
                 "options" => %{"species" => "cat", "shape" => %{"leg_length" => 3}}
               })

      order = %{
        "blueprint" => "animal",
        "options" => %{"species" => "wolf", "shape" => %{"ear_droop" => 30}, "markings" => %{"socks" => "#FFFFFF"}}
      }

      assert {:ok,
              %{
                "options" => %{"shape" => %{"ear_droop" => 30.0, "horns" => nil}, "markings" => %{"socks" => "#ffffff"}}
              }} =
               Orders.check(order)

      assert {:ok, <<"glTF", _::binary>>} = Orders.build(order, "far", "glb")

      # The shape space: only on a template with a space (the wolf).
      horse = World.Animals.space("wolf")["animals"]["horse"]

      spaced = %{
        "blueprint" => "animal",
        "options" => %{"species" => "wolf", "shape" => horse["shape"], "space" => horse["space"]}
      }

      assert {:ok, %{"options" => %{"space" => [_ | _]}}} = Orders.check(spaced)
      assert {:ok, <<"glTF", _::binary>>} = Orders.build(spaced, "far", "glb")

      assert {:error,
              [%{"path" => "options.space", "message" => "a cat has no shape space; the species with one: hyena, wolf"}]} =
               Orders.check(%{"blueprint" => "animal", "options" => %{"species" => "cat", "space" => [1]}})
    end

    test "a person with the colors of the hair and of the clothes" do
      order = %{
        "blueprint" => "person",
        "options" => %{
          "hair" => "long01",
          "hair_color" => "#E8C070",
          "clothes" => ["female_sportsuit01", "shoes03"],
          "clothes_colors" => ["#c0392b"],
          "gender" => 0.0
        }
      }

      {:ok, full} = Orders.check(order)
      assert full["options"]["hair_color"] == "#e8c070"

      # The full order gives null for the color of the hair, and it is
      # correct again.
      natural = put_in(full, ["options", "hair_color"], nil)
      assert {:ok, ^natural} = Orders.check(natural)

      factor = fn glb, name ->
        m = Enum.find(World.GLBHelper.json(glb)["materials"], &(&1["name"] == name))
        m["pbrMetallicRoughness"]["baseColorFactor"]
      end

      # At mid, the clothes have the color of the order, and the gray hair
      # has it as its factor; with no color, the hair has its own color.
      {:ok, mid} = Orders.build(order, "mid", "glb")
      assert [r, g, b, 1.0] = factor.(mid, "color_female_sportsuit01")
      assert r > g and r > b
      assert [hr, hg, hb, 1.0] = factor.(mid, "hair")
      assert hr > hg and hg > hb
      {:ok, own} = Orders.build(natural, "mid", "glb")
      assert factor.(own, "hair") != factor.(mid, "hair")

      # At near, the color of the clothes is a tint of the texture; an item
      # with no color has no tint.
      {:ok, near} = Orders.build(order, "near", "glb")
      assert [_, _, _, 1.0] = factor.(near, "clothes_female_sportsuit01")
      assert factor.(near, "clothes_shoes03") == [1.0, 1.0, 1.0, 1.0]
    end

    test "the joints of a person in an order: by itself, and as a node of a traveler" do
      node = fn glb, name -> Enum.find(World.GLBHelper.json(glb)["nodes"], &(&1["name"] == name)) end
      person = %{"blueprint" => "person", "options" => %{"hair" => "none", "clothes" => []}}
      {:ok, rest} = Orders.build(person, "far", "glb")

      {:ok, bent} =
        Orders.build(Map.put(person, "joints", %{"elbow_l" => 120, "shoulder_r.spread" => 60}), "far", "glb")

      assert node.(bent, "lowerarm_l")["rotation"] != node.(rest, "lowerarm_l")["rotation"]
      assert node.(bent, "upperarm_r")["rotation"] != node.(rest, "upperarm_r")["rotation"]
      assert node.(bent, "lowerarm_r")["rotation"] == node.(rest, "lowerarm_r")["rotation"]

      {:ok, receipt} = Orders.build(person, "far", "receipt")
      joints = JSON.decode!(receipt)["joints"]
      assert "elbow_l" in joints and "neck.twist" in joints and length(joints) == 36
      assert paths(Orders.build(Map.put(person, "joints", %{"tail" => 1}), "far", "glb")) == ["joints.tail"]

      traveler = %{"blueprint" => "traveler", "options" => %{"vehicle" => "bicycle", "hair" => "none", "clothes" => []}}
      {:ok, receipt} = Orders.build(traveler, "far", "receipt")
      assert "traveler/knee_r" in JSON.decode!(receipt)["joints"]
      {:ok, ride} = Orders.build(traveler, "far", "glb")
      {:ok, wave} = Orders.build(Map.put(traveler, "joints", %{"traveler/elbow_r" => 140}), "far", "glb")
      assert node.(wave, "lowerarm_r")["rotation"] != node.(ride, "lowerarm_r")["rotation"]
      assert paths(Orders.build(Map.put(traveler, "joints", %{"elbow_r" => 1}), "far", "glb")) == ["joints.elbow_r"]
    end

    test "the targets of the limbs in an order" do
      node = fn glb, name -> Enum.find(World.GLBHelper.json(glb)["nodes"], &(&1["name"] == name)) end
      person = %{"blueprint" => "person", "options" => %{"hair" => "none", "clothes" => []}}
      # An order with no target has no key "targets": its hash stays.
      assert {:ok, full} = Orders.check(person)
      refute Map.has_key?(full, "targets")
      reach = Map.put(person, "targets", %{"arm_r" => [0.3, 0.4, 1.3]})
      assert {:ok, %{"targets" => %{"arm_r" => [0.3, 0.4, 1.3]}}} = Orders.check(reach)
      {:ok, rest} = Orders.build(person, "far", "glb")
      {:ok, up} = Orders.build(reach, "far", "glb")
      assert node.(up, "upperarm_r")["rotation"] != node.(rest, "upperarm_r")["rotation"]
      {:ok, receipt} = Orders.build(person, "far", "receipt")
      assert "spine" in JSON.decode!(receipt)["limbs"]

      assert paths(Orders.check(Map.put(person, "targets", %{"arm_r" => [1, 2]}))) == ["targets.arm_r"]
      assert paths(Orders.check(Map.put(person, "targets", [1]))) == ["targets"]
      assert paths(Orders.build(Map.put(person, "targets", %{"wing" => [0, 0, 1]}), "far", "glb")) == ["targets.wing"]

      traveler = %{"blueprint" => "traveler", "options" => %{"vehicle" => "car", "hair" => "none", "clothes" => []}}

      assert {:ok, <<"glTF", _::binary>>} =
               Orders.build(Map.put(traveler, "targets", %{"traveler/arm_l" => [-0.3, 0.3, 1.0]}), "far", "glb")
    end

    test "a wrong level, a wrong file, a joint that the model does not have, a wrong order" do
      order = %{"blueprint" => "strut", "options" => %{"length" => 0.3}}
      assert paths(Orders.build(order, "huge", "glb")) == ["level"]
      assert paths(Orders.build(order, "far", "zip")) == ["file"]
      assert paths(Orders.build(Map.put(order, "joints", %{"door" => 1}), "far", "glb")) == ["joints.door"]
      assert paths(Orders.build(%{"blueprint" => "strut"}, "far", "glb")) == ["options.length"]
    end

    property "the JSON of a value has its keys in order, and JSON gives the value back" do
      check all(
              map <- map_of(string(:alphanumeric, min_length: 1), one_of([integer(), boolean(), string(:printable)])),
              max_runs: 50
            ) do
        bin = Orders.encode(map)
        assert JSON.decode!(bin) == map
        assert Orders.encode(Map.new(Enum.reverse(Map.to_list(map)))) == bin
      end
    end
  end
end
