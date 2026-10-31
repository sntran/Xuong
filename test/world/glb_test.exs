defmodule World.GLBTest do
  use ExUnit.Case, async: true

  alias World.Frame

  alias World.GLB

  alias World.GLBHelper

  alias World.Mesh

  alias World.Scene

  alias World.Shape

  defp box_node(name, parent \\ nil) do
    m = Shape.box({0, 0, 0}, {1, 1, 1}, :paint)

    %Scene.Node{
      name: name,
      parent: parent,
      frame: Frame.move({0, 1, 0}),
      primitives: [Scene.primitive(:paint, Mesh.triangles(m))]
    }
  end

  test "a scene of two nodes" do
    scene = %Scene{
      name: "two",
      extras: %{"kind" => "item"},
      nodes: [box_node("a"), %{box_node("b", 0) | extras: %{"role" => "door"}}]
    }

    json = GLBHelper.json(GLB.encode(scene))

    assert [%{"nodes" => [0], "name" => "two", "extras" => %{"kind" => "item"}}] = json["scenes"]
    assert [%{"children" => [1], "mesh" => 0}, %{"mesh" => 1, "extras" => %{"role" => "door"}}] = json["nodes"]
    # (x, y, z) is (-x, z, y) in glTF: a move along y is a move along +Z.
    assert hd(json["nodes"])["translation"] == [-0.0, 0.0, 1.0]
    assert [%{"name" => "paint"}] = json["materials"]
    assert Scene.triangles(scene) == 24
    assert GLB.encode(scene) == GLB.encode(scene)
  end

  test "a node with no mesh, a skin, an animation, and a texture" do
    corners = Mesh.triangles(Shape.box({0, 0, 0}, {1, 1, 1}, :skin))
    p = Scene.primitive(:skin, corners)
    n = length(p.positions)

    p = %{
      p
      | uvs: List.duplicate({0.5, 0.5}, n),
        joints: List.duplicate({0, 1, 0, 0}, n),
        weights: List.duplicate({0.5, 0.5, 0.0, 0.0}, n)
    }

    scene = %Scene{
      name: "skin",
      nodes: [
        %Scene.Node{name: "root"},
        %Scene.Node{name: "bone", parent: 0, frame: Frame.move({0, 0, 1})},
        %Scene.Node{name: "body", skin: 0, primitives: [p]}
      ],
      skins: [%{joints: [0, 1], inverse_bind: [Frame.identity(), Frame.move({0, 0, -1})], skeleton: 0, name: "rig"}],
      animations: [
        %{
          name: "wave",
          channels: [
            %{node: 1, path: :rotation, times: [0, 1], values: [Frame.identity(), Frame.turn({1, 0, 0}, 30)]},
            %{node: 1, path: :translation, times: [0, 1], values: [{0, 0, 1}, {0, 0, 1.1}]}
          ]
        }
      ],
      materials: %{
        skin: %{
          "color" => [200, 150, 120],
          "roughness" => 0.6,
          "metalness" => 0.0,
          "image" => {"image/png", <<137, 80, 78, 71>>}
        }
      }
    }

    json = GLBHelper.json(GLB.encode(scene))
    assert [%{"joints" => [0, 1], "skeleton" => 0, "name" => "rig"}] = json["skins"]
    assert [%{"channels" => [_, _], "samplers" => [_, _]}] = json["animations"]
    assert [%{"mimeType" => "image/png"}] = json["images"]
    assert [%{"pbrMetallicRoughness" => %{"baseColorTexture" => %{"index" => 0}}}] = json["materials"]
    assert %{"JOINTS_0" => _, "WEIGHTS_0" => _, "TEXCOORD_0" => _} = hd(hd(json["meshes"])["primitives"])["attributes"]
    refute Map.has_key?(Enum.at(json["nodes"], 0), "mesh")
    refute Map.has_key?(json, "extensionsUsed")

    # A texture that repeats: 3 times in one unit of UV.
    tiled = put_in(scene.materials.skin["image_scale"], 3.0)
    json = GLBHelper.json(GLB.encode(tiled))
    assert json["extensionsUsed"] == ["KHR_texture_transform"]

    assert [%{"pbrMetallicRoughness" => %{"baseColorTexture" => %{"extensions" => %{"KHR_texture_transform" => t}}}}] =
             json["materials"]

    assert t == %{"scale" => [3.0, 3.0]}

    # Skin: a normal texture that repeats, a sheen and less reflection.
    skin =
      Map.merge(scene.materials.skin, %{
        "normal_image" => {"image/png", <<137, 80, 78, 71, 1>>},
        "normal_scale" => 0.5,
        "normal_image_scale" => 60,
        "sheen" => [255, 255, 255],
        "specular" => 0.5
      })

    json = GLBHelper.json(GLB.encode(%{scene | materials: %{skin: skin}}))
    assert json["extensionsUsed"] == ["KHR_materials_sheen", "KHR_materials_specular", "KHR_texture_transform"]
    assert [m] = json["materials"]

    assert %{"index" => 1, "scale" => 0.5, "extensions" => %{"KHR_texture_transform" => %{"scale" => [60, 60]}}} =
             m["normalTexture"]

    assert m["extensions"] == %{
             "KHR_materials_sheen" => %{"sheenColorFactor" => [1.0, 1.0, 1.0], "sheenRoughnessFactor" => 0.5},
             "KHR_materials_specular" => %{"specularFactor" => 0.5}
           }

    # The same normal texture with no repeat and the default scale.
    skin = Map.drop(skin, ["normal_scale", "normal_image_scale", "sheen", "specular"])
    json = GLBHelper.json(GLB.encode(%{scene | materials: %{skin: skin}}))
    assert json["materials"] |> hd() |> Map.fetch!("normalTexture") == %{"index" => 1, "scale" => 1.0}
    refute Map.has_key?(json, "extensionsUsed")
  end

  test "the tangents of a primitive with a normal texture" do
    # Two triangles of a square in the plane z = 0, the normal +z; the
    # second has its UVs in a mirror (u to the left).
    p = %Scene.Primitive{
      material: :skin,
      positions: [{0, 0, 0}, {1, 0, 0}, {0, 1, 0}, {2, 0, 0}, {3, 0, 0}, {2, 1, 0}],
      normals: List.duplicate({0.0, 0.0, 1.0}, 6),
      uvs: [{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}, {1.0, 0.0}, {0.0, 0.0}, {1.0, 1.0}],
      indices: [0, 1, 2, 3, 4, 5]
    }

    spec = %{"color" => [255, 255, 255], "roughness" => 0.5, "metalness" => 0.0, "normal_image" => {"image/png", <<1>>}}
    scene = %Scene{name: "t", nodes: [%Scene.Node{name: "square", primitives: [p]}], materials: %{skin: spec}}
    glb = GLB.encode(scene)
    [prim] = hd(GLBHelper.json(glb)["meshes"])["primitives"]
    tangents = GLBHelper.floats(glb, prim["attributes"]["TANGENT"])

    # +u is +x of World (-x of glTF) on the first triangle; +v is +y of
    # World, so the sign is -1 (the normal times the tangent is +v, and
    # the sign makes it -v). On the mirror, -x of World, with the sign 1.
    assert Enum.take(tangents, 3) == List.duplicate({-1.0, 0.0, 0.0, -1.0}, 3)
    assert Enum.drop(tangents, 3) == List.duplicate({1.0, 0.0, 0.0, 1.0}, 3)
  end

  test "an animation of the weights of the morph targets" do
    p = Scene.primitive(:paint, Mesh.triangles(Shape.box({0, 0, 0}, {1, 1, 1}, :paint)))
    p = %{p | targets: [{"open", Enum.map(p.positions, fn _ -> {0.0, 0.0, 0.1} end)}]}

    scene = %Scene{
      nodes: [%Scene.Node{name: "face", primitives: [p]}],
      animations: [
        %{name: "talk", channels: [%{node: 0, path: :weights, times: [0, 0.5, 1], values: [[0.0], [1.0], [0.0]]}]}
      ]
    }

    json = GLBHelper.json(GLB.encode(scene))

    [%{"channels" => [%{"target" => %{"path" => "weights", "node" => 0}}], "samplers" => [%{"output" => out}]}] =
      json["animations"]

    assert Enum.at(json["accessors"], out)["count"] == 3
    # All the points move up (z of World is y of glTF).
    [%{"primitives" => [%{"targets" => [%{"POSITION" => t}]}]}] = json["meshes"]

    [x, y, z] = Enum.at(json["accessors"], t)["max"]
    assert x == 0.0 and z == 0.0
    assert_in_delta y, 0.1, 1.0e-6

    # A target as a map of the points that move gives the same file as
    # a move for each point (with zeros).
    [{"open", list}] = p.targets
    sparse = Map.new(0..3, &{&1, Enum.at(list, &1)})
    dense = for {m, i} <- Enum.with_index(list), do: if(i < 4, do: m, else: {0.0, 0.0, 0.0})

    one = fn moves ->
      GLB.encode(put_in(scene.nodes, [%Scene.Node{name: "face", primitives: [%{p | targets: [{"open", moves}]}]}]))
    end

    assert one.(sparse) == one.(dense)
  end

  test "a material with no role in the palette is grey, and a scene with no mesh" do
    json = GLBHelper.json(GLB.encode(%Scene{nodes: [%Scene.Node{}]}))
    refute Map.has_key?(json, "buffers")

    m = Shape.box({0, 0, 0}, {1, 1, 1}, :unknown_role)

    json =
      GLBHelper.json(
        GLB.encode(%Scene{nodes: [%Scene.Node{primitives: [Scene.primitive(m.material, Mesh.triangles(m))]}]})
      )

    assert [%{"name" => "unknown_role"}] = json["materials"]

    json =
      GLBHelper.json(
        GLB.encode(%Scene{
          materials: %{unknown_role: %{color: [0, 0, 0], roughness: 1, metalness: 0}},
          nodes: [%Scene.Node{primitives: [Scene.primitive(m.material, Mesh.triangles(m))]}]
        })
      )

    assert [%{"pbrMetallicRoughness" => %{"baseColorFactor" => [0.0, 0.0, 0.0, 1.0]}}] = json["materials"]
  end

  test "large primitives use 32-bit indices" do
    corners = for i <- 0..70_000, do: {{i / 1, 0.0, 0.0}, {0.0, 0.0, 1.0}}
    p = Scene.primitive(:paint, Enum.take(corners, 3 * div(length(corners), 3)))
    json = GLBHelper.json(GLB.encode(%Scene{nodes: [%Scene.Node{primitives: [p]}]}))
    ind = Enum.at(json["accessors"], hd(hd(json["meshes"])["primitives"])["indices"])
    assert ind["componentType"] == 5125
  end

  test "write! writes the file, and the palette has the roles" do
    path = Path.join(System.tmp_dir!(), "world_glb_test/one.glb")
    GLB.write!(path, %Scene{nodes: [box_node("a")]})
    assert File.read!(path) |> binary_part(0, 4) == "glTF"
    assert Map.has_key?(GLB.palette(), "tire")
  end

  test "gl_frame keeps a turn a turn" do
    f = GLB.gl_frame(Frame.turn({0.3, 0.4, 0.5}, 33))
    assert_in_delta World.Vec.dot(World.Vec.cross(f.x, f.y), f.z), 1.0, 1.0e-9
  end
end
