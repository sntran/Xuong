defmodule World.GLB do
  @moduledoc """
  The writer of GLB (glTF 2.0, binary) for a `World.Scene`.

  - The axes: a point (x, y, z) of World is (-x, z, y) in glTF: +Y up and
    the front to +Z. This is a turn, not a mirror, so each triangle keeps
    the order of its corners.
  - One glTF material for each role, from `priv/palette.json` or from the
    `materials` of the scene. Its name is its role.
  - The same scene gives the same bytes.
  """
  alias World.{Frame, Scene, Vec}
  @external_resource palette_path = Path.join([__DIR__, "..", "..", "priv", "palette.json"])
  @palette palette_path |> File.read!() |> JSON.decode!() |> Map.fetch!("roles")

  # The atom of each role, made here from the palette (a role in an
  # order must be one of them: an order makes no new atom).
  @roles Map.new(Map.keys(@palette), &{&1, String.to_atom(&1)})

  @doc "The palette: a map of each role to its color, roughness and metalness."
  def palette, do: @palette

  @doc "The atom of a role of the palette (by its name), or nil."
  def role(name), do: Map.get(@roles, name)

  @doc "The GLB of a scene, as a binary."
  def encode(%Scene{} = scene) do
    {json, bin} = gltf(scene)
    json_bin = pad(JSON.encode!(json), " ")
    bin = pad(bin, <<0>>)
    total = 12 + 8 + byte_size(json_bin) + if(bin == <<>>, do: 0, else: 8 + byte_size(bin))

    chunk_bin = if bin == <<>>, do: <<>>, else: <<byte_size(bin)::little-32, "BIN", 0, bin::binary>>

    <<"glTF", 2::little-32, total::little-32, byte_size(json_bin)::little-32, "JSON", json_bin::binary,
      chunk_bin::binary>>
  end

  @doc "Write the GLB of a scene to a file."
  def write!(path, %Scene{} = scene) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, encode(scene))
  end

  # --- The JSON and the buffer ------------------------------------------------

  defp gltf(%Scene{nodes: nodes} = scene) do
    roles = nodes |> Enum.flat_map(& &1.primitives) |> Enum.map(& &1.material) |> Enum.uniq() |> Enum.sort()
    mat_index = roles |> Enum.with_index() |> Map.new()
    buf = %{bin: <<>>, views: [], accessors: [], images: [], image_of: %{}}

    # The roles with a normal texture: their primitives have tangents.
    bumpy =
      for {role, spec} <- scene.materials,
          Enum.any?(spec, &(to_string(elem(&1, 0)) == "normal_image")),
          into: MapSet.new(),
          do: role

    {meshes, node_mesh, buf} =
      nodes
      |> Enum.with_index()
      |> Enum.reduce({[], %{}, buf}, fn
        {%{primitives: []}, _i}, acc ->
          acc

        {node, i}, {meshes, map, buf} ->
          # The morph targets: each primitive of a mesh has all of them (a
          # primitive with no move for a target has a target of zeros);
          # when a target of the mesh moves the normals, each target of
          # each primitive has its normals.
          names = Enum.find_value(node.primitives, & &1.targets) |> then(&(&1 && Enum.map(&1, fn t -> elem(t, 0) end)))
          normals? = Enum.any?(node.primitives, fn p -> Enum.any?(List.wrap(p.targets), &(tuple_size(&1) == 3)) end)
          {prims, buf} = Enum.map_reduce(node.primitives, buf, &primitive(&1, &2, mat_index, {names, normals?}, bumpy))

          mesh =
            %{"name" => node.name, "primitives" => prims}
            |> put_some("weights", names && Enum.map(names, fn _ -> 0.0 end))
            |> put_some("extras", names && %{"targetNames" => names})

          {[mesh | meshes], Map.put(map, i, length(meshes)), buf}
      end)

    {skins, buf} = Enum.map_reduce(scene.skins, buf, &skin/2)
    {animations, buf} = Enum.map_reduce(scene.animations, buf, &animation/2)
    {materials, buf} = Enum.map_reduce(roles, buf, &material(&1, &2, scene.materials))

    children =
      nodes
      |> Enum.with_index()
      |> Enum.filter(&(elem(&1, 0).parent != nil))
      |> Enum.group_by(&elem(&1, 0).parent, &elem(&1, 1))

    roots = for {n, i} <- Enum.with_index(nodes), n.parent == nil, do: i

    json_nodes =
      for {n, i} <- Enum.with_index(nodes) do
        {qx, qy, qz, qw} = Frame.quaternion(gl_frame(n.frame))

        %{"name" => n.name, "translation" => tuple3(gl(n.frame.at)), "rotation" => [qx, qy, qz, qw]}
        |> put_some("mesh", node_mesh[i])
        |> put_some("children", children[i])
        |> put_some("skin", n.skin)
        |> put_some("scale", if(n.scale == 1.0, do: nil, else: [n.scale, n.scale, n.scale]))
        |> put_some("extras", if(n.extras == %{}, do: nil, else: n.extras))
      end

    json =
      %{
        "asset" => %{"version" => "2.0", "generator" => "World"},
        "scene" => 0,
        "scenes" => [
          %{"name" => scene.name, "nodes" => roots}
          |> put_some("extras", if(scene.extras == %{}, do: nil, else: scene.extras))
        ],
        "nodes" => json_nodes,
        "materials" => materials
      }
      |> put_some("meshes", nonempty(Enum.reverse(meshes)))
      |> put_some("skins", nonempty(skins))
      |> put_some("animations", nonempty(animations))
      |> put_some("extensionsUsed", extensions(materials))
      |> put_some("images", nonempty(Enum.reverse(buf.images)))
      |> put_some("textures", nonempty(for {_, i} <- Enum.with_index(buf.images), do: %{"source" => i, "sampler" => 0}))
      |> put_some("samplers", if(buf.images == [], do: nil, else: [%{"magFilter" => 9729, "minFilter" => 9987}]))
      |> put_some("accessors", nonempty(Enum.reverse(buf.accessors)))
      |> put_some("bufferViews", nonempty(Enum.reverse(buf.views)))
      |> put_some("buffers", if(buf.bin == <<>>, do: nil, else: [%{"byteLength" => byte_size(pad(buf.bin, <<0>>))}]))

    {json, buf.bin}
  end

  defp primitive(%Scene.Primitive{} = p, buf, mat_index, {names, normals?}, bumpy) do
    {pos, buf} = floats(buf, p.positions, "VEC3", 34962, true, &gl/1)
    {nor, buf} = floats(buf, p.normals, "VEC3", 34962, false, &gl/1)
    attrs = %{"POSITION" => pos, "NORMAL" => nor}

    {attrs, buf} =
      if p.uvs, do: with_attr(attrs, "TEXCOORD_0", floats(buf, p.uvs, "VEC2", 34962, false)), else: {attrs, buf}

    {attrs, buf} =
      if p.uvs && MapSet.member?(bumpy, p.material),
        do: with_attr(attrs, "TANGENT", floats(buf, tangents(p), "VEC4", 34962, false)),
        else: {attrs, buf}

    {attrs, buf} =
      if p.joints, do: with_attr(attrs, "JOINTS_0", ushorts(buf, p.joints)), else: {attrs, buf}

    {attrs, buf} =
      if p.weights, do: with_attr(attrs, "WEIGHTS_0", floats(buf, p.weights, "VEC4", 34962, false)), else: {attrs, buf}

    # The colors of the vertices: sRGB 0 to 255 in, linear 0 to 1 out;
    # with a fourth number, the alpha (0 to 1) of each vertex.
    {attrs, buf} =
      case p.colors do
        nil ->
          {attrs, buf}

        [{_, _, _, _} | _] ->
          linear =
            for {r, g, b, a} <- p.colors,
                do: {srgb_to_linear(r / 255), srgb_to_linear(g / 255), srgb_to_linear(b / 255), a / 1}

          with_attr(attrs, "COLOR_0", floats(buf, linear, "VEC4", 34962, false))

        _ ->
          linear =
            for {r, g, b} <- p.colors, do: {srgb_to_linear(r / 255), srgb_to_linear(g / 255), srgb_to_linear(b / 255)}

          with_attr(attrs, "COLOR_0", floats(buf, linear, "VEC3", 34962, false))
      end

    # The length of the fur of each point (m), for an app that draws fur:
    # an attribute of the application (its name starts with _).
    {attrs, buf} =
      if p.fur,
        do: with_attr(attrs, "_FUR", floats(buf, Enum.map(p.fur, &{&1 / 1}), "SCALAR", 34962, false)),
        else: {attrs, buf}

    # The direction of the fur of each point (a unit vector along the skin,
    # at rest, in the axes of glTF: the joints turn it as the normal).
    {attrs, buf} =
      if p.fur_dirs,
        do: with_attr(attrs, "_FUR_DIR", floats(buf, Enum.map(p.fur_dirs, &gl(Vec.float(&1))), "VEC3", 34962, false)),
        else: {attrs, buf}

    {ind, buf} = indices(buf, p.indices, length(p.positions))

    {targets, buf} =
      Enum.map_reduce(names || [], buf, fn name, buf ->
        t = p.targets |> List.wrap() |> Enum.find(&(elem(&1, 0) == name))
        {acc, buf} = target(buf, t && elem(t, 1), length(p.positions))

        if normals? do
          {normal, buf} = target(buf, t && tuple_size(t) == 3 && elem(t, 2), length(p.positions))
          {%{"POSITION" => acc, "NORMAL" => normal}, buf}
        else
          {%{"POSITION" => acc}, buf}
        end
      end)

    # A collection after each primitive (World.Detail.collect/1).
    World.Detail.collect(
      {%{"attributes" => attrs, "indices" => ind, "material" => Map.fetch!(mat_index, p.material)}
       |> put_some("targets", names && targets), buf}
    )
  end

  # The tangent of each point, in the axes of glTF, for a normal texture:
  # the direction of +u on the surface, at a right angle to the normal,
  # and a sign (1 or -1): the cross product of the normal and the tangent,
  # times the sign, points to -v (up in the image: green is up in a
  # normal texture of glTF). A point with no
  # direction of u (no area of UV) takes a direction at a right angle to
  # its normal.
  defp tangents(%Scene.Primitive{} = p) do
    pos = p.positions |> Enum.map(&gl/1) |> List.to_tuple()
    uv = List.to_tuple(p.uvs)

    sums =
      p.indices
      |> Enum.chunk_every(3)
      |> Enum.reduce(%{}, fn [i, j, k], acc ->
        {e1, e2} = {Vec.sub(elem(pos, j), elem(pos, i)), Vec.sub(elem(pos, k), elem(pos, i))}
        {{u0, v0}, {u1, v1}, {u2, v2}} = {elem(uv, i), elem(uv, j), elem(uv, k)}
        {du1, dv1, du2, dv2} = {u1 - u0, v1 - v0, u2 - u0, v2 - v0}
        det = du1 * dv2 - du2 * dv1

        if abs(det) < 1.0e-12 do
          acc
        else
          t = Vec.scale(Vec.sub(Vec.scale(e1, dv2), Vec.scale(e2, dv1)), 1 / det)
          b = Vec.scale(Vec.sub(Vec.scale(e2, du1), Vec.scale(e1, du2)), 1 / det)

          Enum.reduce([i, j, k], acc, fn v, acc ->
            Map.update(acc, v, {t, b}, fn {t0, b0} -> {Vec.add(t0, t), Vec.add(b0, b)} end)
          end)
        end
      end)

    for {n, i} <- Enum.with_index(Enum.map(p.normals, &gl/1)) do
      {t, b} = Map.get(sums, i, {{0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}})
      t = Vec.sub(t, Vec.scale(n, Vec.dot(n, t)))

      t =
        if Vec.len(t) > 1.0e-9,
          do: Vec.norm(t),
          else: Vec.norm(Vec.cross(n, if(abs(elem(n, 0)) < 0.9, do: {1.0, 0.0, 0.0}, else: {0.0, 1.0, 0.0})))

      {x, y, z} = t
      {x, y, z, if(Vec.dot(Vec.cross(n, t), b) > 0, do: -1.0, else: 1.0)}
    end
  end

  # A morph target: the moves of the points (or of the normals) that move
  # (sparse: their indices and their moves), the others zero. A target
  # with no move has no data.
  defp target(buf, moves, count) do
    pairs = if is_map(moves), do: Enum.sort(moves), else: Enum.with_index(moves || [], fn m, i -> {i, m} end)
    moved = for {i, m} <- pairs, Vec.len(m) > 1.0e-7, do: {i, gl(Vec.float(m))}
    vals = [{0.0, 0.0, 0.0} | Enum.map(moved, &elem(&1, 1))]
    bound = fn f -> for k <- 0..2, do: vals |> Enum.map(&f32(elem(&1, k))) |> f.() end

    acc = %{
      "componentType" => 5126,
      "count" => count,
      "type" => "VEC3",
      "min" => bound.(&Enum.min/1),
      "max" => bound.(&Enum.max/1)
    }

    case moved do
      [] ->
        {length(buf.accessors), %{buf | accessors: [acc | buf.accessors]}}

      _ ->
        iv = length(buf.views)
        buf = add_view(buf, for({i, _} <- moved, into: <<>>, do: <<i::little-32>>), nil)
        vv = length(buf.views)

        buf =
          add_view(
            buf,
            for(
              {_, {x, y, z}} <- moved,
              into: <<>>,
              do: <<x::little-float-32, y::little-float-32, z::little-float-32>>
            ),
            nil
          )

        sparse = %{
          "count" => length(moved),
          "indices" => %{"bufferView" => iv, "componentType" => 5125},
          "values" => %{"bufferView" => vv}
        }

        {length(buf.accessors), %{buf | accessors: [Map.put(acc, "sparse", sparse) | buf.accessors]}}
    end
  end

  defp with_attr(attrs, key, {acc, buf}), do: {Map.put(attrs, key, acc), buf}

  defp skin(%{joints: joints, inverse_bind: frames} = s, buf) do
    mats = for f <- frames, do: Frame.matrix(gl_frame(f))
    {acc, buf} = matrices(buf, mats)

    {%{"joints" => joints, "inverseBindMatrices" => acc}
     |> put_some("skeleton", Map.get(s, :skeleton))
     |> put_some("name", Map.get(s, :name)), buf}
  end

  # An animation: channels of rotations (frames), translations (points) or
  # the weights of the morph targets (a list for each time) of nodes, at
  # times in seconds.
  defp animation(%{name: name, channels: channels}, buf) do
    {pairs, buf} =
      channels
      |> Enum.with_index()
      |> Enum.map_reduce(buf, fn {%{node: node, path: path, times: times, values: values}, i}, buf ->
        {input, buf} = scalars(buf, times)

        {output, buf} =
          case path do
            :rotation -> floats(buf, for(f <- values, do: Frame.quaternion(gl_frame(f))), "VEC4", nil, false)
            :translation -> floats(buf, Enum.map(values, &gl/1), "VEC3", nil, false)
            :weights -> floats(buf, for(ws <- values, w <- ws, do: {w / 1}), "SCALAR", nil, false)
          end

        {{%{"input" => input, "output" => output, "interpolation" => "LINEAR"},
          %{"sampler" => i, "target" => %{"node" => node, "path" => Atom.to_string(path)}}}, buf}
      end)

    {%{"name" => name, "samplers" => Enum.map(pairs, &elem(&1, 0)), "channels" => Enum.map(pairs, &elem(&1, 1))}, buf}
  end

  # The extensions that the materials use.
  defp extensions(materials) do
    transform? =
      Enum.any?(materials, fn m ->
        get_in(m, ["pbrMetallicRoughness", "baseColorTexture", "extensions"]) ||
          get_in(m, ["normalTexture", "extensions"])
      end)

    names = for m <- materials, {name, _} <- Map.get(m, "extensions", %{}), uniq: true, do: name
    nonempty(Enum.sort(if(transform?, do: ["KHR_texture_transform" | names], else: names)))
  end

  # A texture of an image. Two materials with the same image share it. A
  # texture that repeats (`scale`: the times in one unit of UV) has a
  # transform (KHR_texture_transform).
  defp texture(buf, {mime, data} = file, scale) do
    {image, buf} =
      case buf.image_of do
        %{^file => image} ->
          {image, buf}

        _ ->
          view = length(buf.views)
          buf = add_view(buf, data, nil)
          image = length(buf.images)

          {image,
           %{
             buf
             | images: [%{"bufferView" => view, "mimeType" => mime} | buf.images],
               image_of: Map.put(buf.image_of, file, image)
           }}
      end

    texture = %{"index" => image}

    texture =
      if scale,
        do: Map.put(texture, "extensions", %{"KHR_texture_transform" => %{"scale" => [scale, scale]}}),
        else: texture

    {texture, buf}
  end

  defp material(role, buf, overrides) do
    spec =
      Map.get(overrides, role) || Map.get(@palette, Atom.to_string(role)) ||
        %{"color" => [154, 161, 170], "roughness" => 0.6, "metalness" => 0.0}

    spec = Map.new(spec, fn {k, v} -> {to_string(k), v} end)
    [r, g, b] = spec["color"]
    color = for c <- [r, g, b], do: Float.round(srgb_to_linear(c / 255), 5)

    alpha = Map.get(spec, "alpha", 1.0) / 1

    pbr = %{
      "baseColorFactor" => color ++ [alpha],
      "roughnessFactor" => spec["roughness"] / 1,
      "metallicFactor" => spec["metalness"] / 1
    }

    # The color of the spec is a factor of the texture: white by
    # default, the color of a hair, or a tint of clothes.
    {pbr, buf} =
      case spec["image"] do
        nil ->
          {pbr, buf}

        file ->
          {texture, buf} = texture(buf, file, spec["image_scale"])
          {Map.put(pbr, "baseColorTexture", texture), buf}
      end

    material = %{
      "name" => Atom.to_string(role),
      "pbrMetallicRoughness" => pbr,
      "doubleSided" => Map.get(spec, "double_sided", false)
    }

    # Small bumps (the pores of the skin) are a normal texture.
    {material, buf} =
      case spec["normal_image"] do
        nil ->
          {material, buf}

        file ->
          {texture, buf} = texture(buf, file, spec["normal_image_scale"])
          {Map.put(material, "normalTexture", Map.put(texture, "scale", Map.get(spec, "normal_scale", 1.0) / 1)), buf}
      end

    # Skin is not plastic: light goes in and comes out red at the edges
    # (sheen, KHR_materials_sheen), and its reflection is less strong
    # (KHR_materials_specular).
    extensions =
      %{}
      |> put_some(
        "KHR_materials_sheen",
        if(sheen = spec["sheen"],
          do: %{
            "sheenColorFactor" => for(c <- sheen, do: Float.round(srgb_to_linear(c / 255), 5)),
            "sheenRoughnessFactor" => Map.get(spec, "sheen_roughness", 0.5) / 1
          }
        )
      )
      |> put_some("KHR_materials_specular", if(f = spec["specular"], do: %{"specularFactor" => f / 1}))

    material = if extensions == %{}, do: material, else: Map.put(material, "extensions", extensions)

    # Glass shows what is behind it; hair has holes (MASK); the eyebrows
    # and the eyelashes have soft strands (BLEND).
    material =
      cond do
        spec["alpha_mode"] == "MASK" -> Map.merge(material, %{"alphaMode" => "MASK", "alphaCutoff" => 0.5})
        spec["alpha_mode"] == "BLEND" -> Map.put(material, "alphaMode", "BLEND")
        alpha < 1.0 -> Map.put(material, "alphaMode", "BLEND")
        true -> material
      end

    {material, buf}
  end

  defp srgb_to_linear(c) when c <= 0.04045, do: c / 12.92
  defp srgb_to_linear(c), do: :math.pow((c + 0.055) / 1.055, 2.4)

  # --- Accessors ---------------------------------------------------------------

  # The values go straight into the binary, and the bounds come from one
  # pass: no list of the values in the axes of glTF, no columns.
  defp floats(buf, vals, type, target, bounds?, conv \\ & &1) do
    data = for v <- vals, x <- Tuple.to_list(conv.(v)), into: <<>>, do: <<x::little-float-32>>
    acc = %{"componentType" => 5126, "count" => length(vals), "type" => type}

    acc =
      if bounds? do
        {lo, hi} = bounds(data, tuple_size(hd(vals)))
        Map.merge(acc, %{"min" => lo, "max" => hi})
      else
        acc
      end

    add_accessor(buf, data, target, acc)
  end

  # The least and the most of each column of a binary of floats.
  defp bounds(data, n) do
    size = 4 * n
    <<first::binary-size(^size), _::binary>> = data
    start = for <<x::little-float-32 <- first>>, do: x

    for <<row::binary-size(^size) <- data>>, reduce: {start, start} do
      {lo, hi} ->
        xs = for <<x::little-float-32 <- row>>, do: x
        {Enum.zip_with(lo, xs, &min/2), Enum.zip_with(hi, xs, &max/2)}
    end
  end

  defp scalars(buf, times) do
    data = for t <- times, into: <<>>, do: <<t / 1::little-float-32>>
    ts = Enum.map(times, &f32(&1 / 1))

    add_accessor(buf, data, nil, %{
      "componentType" => 5126,
      "count" => length(times),
      "type" => "SCALAR",
      "min" => [Enum.min(ts)],
      "max" => [Enum.max(ts)]
    })
  end

  defp ushorts(buf, vals) do
    data = for v <- vals, x <- Tuple.to_list(v), into: <<>>, do: <<x::little-16>>
    add_accessor(buf, data, 34962, %{"componentType" => 5123, "count" => length(vals), "type" => "VEC4"})
  end

  defp matrices(buf, mats) do
    data = for m <- mats, x <- m, into: <<>>, do: <<x / 1::little-float-32>>
    add_accessor(buf, data, nil, %{"componentType" => 5126, "count" => length(mats), "type" => "MAT4"})
  end

  defp indices(buf, idx, count) do
    {data, type} =
      if count <= 65_535,
        do: {for(i <- idx, into: <<>>, do: <<i::little-16>>), 5123},
        else: {for(i <- idx, into: <<>>, do: <<i::little-32>>), 5125}

    add_accessor(buf, data, 34963, %{"componentType" => type, "count" => length(idx), "type" => "SCALAR"})
  end

  defp add_accessor(buf, data, target, acc) do
    view = length(buf.views)
    buf = add_view(buf, data, target)
    {length(buf.accessors), %{buf | accessors: [Map.put(acc, "bufferView", view) | buf.accessors]}}
  end

  defp add_view(buf, data, target) do
    bin = pad(buf.bin, <<0>>)
    view = put_some(%{"buffer" => 0, "byteOffset" => byte_size(bin), "byteLength" => byte_size(data)}, "target", target)
    %{buf | bin: bin <> data, views: [view | buf.views]}
  end

  # --- The axes of glTF --------------------------------------------------------

  @doc "A point or a direction in the axes of glTF."
  def gl({x, y, z}), do: {-x, z, y}

  @doc "A frame in the axes of glTF."
  def gl_frame(%Frame{x: x, y: y, z: z, at: at}),
    do: %Frame{x: World.Vec.neg(gl(x)), y: gl(z), z: gl(y), at: gl(at)}

  defp tuple3({x, y, z}), do: [x, y, z]

  defp f32(x),
    do:
      (
        <<y::little-float-32>> = <<x::little-float-32>>
        y
      )

  defp nonempty([]), do: nil
  defp nonempty(list), do: list
  defp put_some(map, _key, nil), do: map
  defp put_some(map, key, value), do: Map.put(map, key, value)

  defp pad(bin, byte) do
    case rem(byte_size(bin), 4) do
      0 -> bin
      r -> bin <> :binary.copy(byte, 4 - r)
    end
  end
end
