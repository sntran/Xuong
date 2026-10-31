defmodule World.Build do
  @moduledoc """
  The build of a model (a part or an assembly) into a `World.Scene`, at a
  level of detail and in a pose, and the list of its parts.

  - The parts that connect with `:fixed` go into the node of their
    parent. Each joint (`:hinge`, `:slide`) is a node: its frame is the
    port of its parent, and it turns or moves along its own z axis (the
    y axis in glTF).
  - The levels (`docs/format.md`, "The levels of detail"): `:near` has
    each part; `:mid` drops the parts shorter than 2 cm or thinner than
    3 mm, and the parts `inside`; `:far` drops the parts shorter than
    10 cm or thinner than 1 cm. Each level smooths one step less. The
    root part of the model stays at each level. A part with `detail: :low`
    is only in mid and far: it stands in for many small parts (one wall
    in place of its bricks).
  """
  alias World.{Assembly, Detail, Figure, Frame, GLB, Joint, Mesh, Part, Port, Scene, Vec}
  alias World.Assembly.Connection

  @limits %{near: {0.0, 0.0}, mid: {0.02, 0.003}, far: {0.10, 0.01}}

  @doc """
  The scene of a model. The options: `level` (`:near`, `:mid` or `:far`),
  `pose` (a map of a joint name to its value: degrees or meters),
  `targets` (a map of a limb of a figure to the point of its end, in the
  axes of the figure: `World.Limb`), and
  `split` (`true`: each part in a node of its own, with the id of its task
  of `World.Plan.flat/1` in the `"task"` of its extras, for the replay of
  a run).
  """
  def scene(item, opts \\ []) do
    level = Keyword.get(opts, :level, :near)
    pose = Keyword.get(opts, :pose, %{})
    targets = Keyword.get(opts, :targets, %{})
    name = item.name
    root = %Scene.Node{name: name}

    acc =
      walk(
        keep_root(item),
        Frame.identity(),
        0,
        %{
          nodes: [root],
          parts: %{0 => []},
          skins: [],
          animations: [],
          materials: %{},
          joints: [],
          limbs: [],
          moves: %{},
          clips: [],
          targets: targets,
          path: name,
          prefix: ""
        },
        level,
        pose
      )

    {nodes, _} = finish(acc, Keyword.get(opts, :split, false))

    materials = Map.merge(Map.get(item, :materials, %{}), acc.materials)
    animations = join(acc.animations ++ Enum.map(acc.clips, &clip(&1, acc.moves)))
    scene = %Scene{name: name, nodes: nodes, skins: acc.skins, animations: animations, materials: materials}
    {lo, hi} = if Scene.triangles(scene) > 0, do: Scene.bounds(scene), else: {{0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}}
    size = Vec.sub(hi, lo)

    extras = %{
      "name" => name,
      "kind" => Atom.to_string(Map.get(item, :kind, :part)),
      "level" => Atom.to_string(level),
      "size" => for(v <- Tuple.to_list(size), do: Float.round(v / 1, 4)),
      "sources" => Map.get(item, :sources, []),
      "joints" => for(n <- nodes, n.extras["role"], do: n.name) ++ acc.joints,
      "limbs" => acc.limbs
    }

    %{scene | extras: Map.merge(extras, Map.get(item, :extras, %{}))}
  end

  @doc "Write the GLB of a model at a level, in a pose."
  def glb(item, opts \\ []), do: GLB.encode(scene(item, opts))

  # The root of the figure goes under the node; a skinned mesh stays a
  # root node (its bones place it).
  # The animations of the same name (the routine of each person of a
  # group) become one animation: an app plays them together.
  defp join(animations) do
    animations
    |> Enum.group_by(& &1.name)
    |> Enum.map(fn {name, [a | _] = all} ->
      {Enum.find_index(animations, &(&1 == a)), %{name: name, channels: Enum.flat_map(all, & &1.channels)}}
    end)
    |> Enum.sort()
    |> Enum.map(&elem(&1, 1))
  end

  defp figure_parent(0, _, node, _), do: node
  defp figure_parent(_, %{parent: nil}, _, _), do: nil
  defp figure_parent(_, %{parent: p}, _, offset), do: p + offset

  # Walk the tree of a model. A part goes into the list of its node; a
  # node of an assembly goes into the node of its parent, or into a new
  # node for a joint.
  # A figure (a person) brings its own nodes, skin, animations and
  # materials: its root goes at the frame, under the node. The values of
  # its joints have the path of its node in front ("rider/elbow_l"), but
  # not for a figure that is the model.
  defp walk(%Figure{} = f, frame, node, acc, level, pose) do
    values =
      for {k, v} <- pose,
          String.starts_with?(k, acc.prefix),
          into: %{},
          do: {String.replace_prefix(k, acc.prefix, ""), v}

    targets =
      for {k, v} <- acc.targets,
          String.starts_with?(k, acc.prefix),
          into: %{},
          do: {String.replace_prefix(k, acc.prefix, ""), v}

    f = Figure.pose(f, Map.take(values, Figure.values(f)), Map.take(targets, Figure.limbs(f)))
    offset = length(acc.nodes)
    skins = length(acc.skins)

    nodes =
      for {n, i} <- Enum.with_index(f.nodes) do
        %{
          n
          | parent: figure_parent(i, n, node, offset),
            frame: if(i == 0, do: Frame.compose(frame, n.frame), else: n.frame),
            skin: n.skin && n.skin + skins
        }
      end

    %{
      acc
      | nodes: acc.nodes ++ nodes,
        parts: Map.merge(acc.parts, Map.new(offset..(offset + length(nodes) - 1), &{&1, []})),
        skins:
          acc.skins ++
            for(s <- f.skins, do: %{s | joints: Enum.map(s.joints, &(&1 + offset)), skeleton: s.skeleton + offset}),
        animations:
          acc.animations ++
            for(a <- f.animations, do: %{a | channels: Enum.map(a.channels, &%{&1 | node: &1.node + offset})}),
        materials: Map.merge(acc.materials, f.materials),
        joints: acc.joints ++ Enum.map(Figure.values(f), &(acc.prefix <> &1)),
        limbs: acc.limbs ++ Enum.map(Figure.limbs(f), &(acc.prefix <> &1))
    }
    |> props(f, offset, level, pose)
  end

  defp walk(%Part{} = p, frame, node, acc, level, _pose) do
    if keep?(p, level), do: update_in(acc.parts[node], &[{frame, p, acc.path} | &1]), else: acc
  end

  defp walk(
         %Assembly{nodes: [{root, root_item, nil} | rest], place: place, clips: clips},
         frame,
         node,
         acc,
         level,
         pose
       ) do
    frame = Frame.compose(frame, place)
    acc = %{acc | clips: acc.clips ++ clips}
    # The path of a node is its id in World.Plan.flat/1: the names of the
    # nodes of the smaller assemblies, with "/" between them.
    prefix = acc.prefix
    at = fn acc, name -> %{acc | path: prefix <> name, prefix: prefix <> name <> "/"} end
    places = %{root => {node, frame, length(acc.nodes)}}
    acc = acc |> at.(root) |> then(&walk(root_item, frame, node, &1, level, pose))

    {acc, _} =
      Enum.reduce(rest, {acc, places}, fn {name, item, %Connection{} = c}, {acc, places} ->
        a = %Assembly{nodes: [{root, root_item, nil} | rest], place: Frame.identity()}
        {parent_node, port} = attach(a, c, places)

        acc = at.(acc, name)

        if c.kind == :fixed do
          f = Frame.compose(port, Assembly.placement(c, item, 0.0))
          {walk(item, f, parent_node, acc, level, pose), Map.put(places, name, {parent_node, f, length(acc.nodes)})}
        else
          # The name of a joint is its own name: three.js removes "/" from
          # the names of nodes. Two joints of a model cannot have one name.
          if Enum.any?(acc.nodes, &(&1.name == name)), do: raise(ArgumentError, "two joints have the name #{name}")
          j = Joint.new(name, c.kind, role: c.role, limits: c.limits)
          value = Joint.clamp(j, nil, Map.get(pose, name, 0.0) / 1)

          joint = %Scene.Node{
            name: name,
            parent: parent_node,
            frame: Frame.compose(port, motion(c.kind, value)),
            extras: Map.put(Joint.extras(j), "axis", [0.0, 1.0, 0.0])
          }

          id = length(acc.nodes)

          acc = %{
            acc
            | nodes: acc.nodes ++ [joint],
              parts: Map.put(acc.parts, id, []),
              moves: Map.put(acc.moves, name, {id, port, j})
          }

          f = Assembly.placement(c, item, 0.0)
          {walk(item, f, id, acc, level, pose), Map.put(places, name, {id, f, length(acc.nodes)})}
        end
      end)

    %{acc | prefix: prefix}
  end

  # The props of a figure: each in the node of the bone of its port (or
  # of the root of the figure).
  defp props(acc, %Figure{props: props} = f, offset, level, pose) do
    Enum.reduce(props, acc, fn {port, item, item_port}, acc ->
      {node, frame} = on_figure(f, offset, port)
      walk(item, Frame.compose(frame, Frame.invert(Assembly.item_port_frame(item, item_port))), node, acc, level, pose)
    end)
  end

  # The node and the frame in it of a port of a figure whose first node
  # is `offset`: a port on a bone is in the node of the bone.
  defp on_figure(f, offset, port) do
    case Figure.port!(f, port) do
      %Port{bone: nil} = p -> {offset, Port.frame(p)}
      %Port{bone: bone} = p -> {offset + Figure.bone_node(f, bone), Port.frame(p)}
    end
  end

  # The node of the parent of a connection, and the frame of its port in
  # that node. A port on a bone of a figure is in the node of the bone.
  defp attach(%Assembly{nodes: nodes} = a, %Connection{to: to, at: at} = c, places) do
    {parent_node, parent_frame, first} = Map.fetch!(places, to)

    case List.keyfind(nodes, to, 0) do
      {_, %Figure{} = f, _} when is_binary(at) ->
        if Figure.port!(f, at).bone,
          do: on_figure(f, first, at),
          else: {parent_node, Frame.compose(parent_frame, port_in_node(a, c))}

      _ ->
        {parent_node, Frame.compose(parent_frame, port_in_node(a, c))}
    end
  end

  # The frame of the port `at` of the node `to`, in the axes of that node.
  defp port_in_node(%Assembly{nodes: nodes}, %Connection{to: to, at: at}) do
    {_, item, _} = List.keyfind(nodes, to, 0)
    Assembly.item_port_frame(item, at)
  end

  # A clip of the joints of an assembly: at each time of a key, the value
  # of each joint of the clip (from its keys, in a line between two keys,
  # and the first or the last value out of them). A hinge gives a turn of
  # its node, a slide a move.
  defp clip(%{name: name, keys: keys}, moves) do
    times = Enum.map(keys, &elem(&1, 0))
    names = keys |> Enum.flat_map(fn {_, joints} -> Map.keys(joints) end) |> Enum.uniq() |> Enum.sort()

    channels =
      for joint <- names do
        {id, port, j} = moves[joint]
        points = for {t, joints} <- keys, Map.has_key?(joints, joint), do: {t, joints[joint]}
        frames = for t <- times, do: Frame.compose(port, motion(j.kind, Joint.clamp(j, nil, between(points, t))))

        if j.kind == :slide,
          do: %{node: id, path: :translation, times: times, values: Enum.map(frames, & &1.at)},
          else: %{node: id, path: :rotation, times: times, values: frames}
      end

    %{name: name, channels: channels}
  end

  defp between(points, t) do
    case Enum.split_while(points, fn {pt, _} -> pt <= t end) do
      {[], [{_, v} | _]} -> v
      {before, []} -> elem(List.last(before), 1)
      {before, [{t1, v1} | _]} -> then(List.last(before), fn {t0, v0} -> v0 + (v1 - v0) * (t - t0) / (t1 - t0) end)
    end
  end

  # The motion of a joint: a turn around its z axis, or a move along it.
  defp motion(:hinge, deg), do: Frame.turn({0.0, 0.0, 1.0}, deg)
  defp motion(:slide, d), do: Frame.move({0.0, 0.0, d})

  defp finish(%{nodes: nodes, parts: parts}, false) do
    nodes =
      for {n, i} <- Enum.with_index(nodes),
          do: %{n | primitives: n.primitives ++ primitives(Enum.reverse(parts[i]))}

    {nodes, parts}
  end

  # Each part in a node of its own, under the node of its joint.
  defp finish(%{nodes: nodes, parts: parts}, true) do
    split =
      for {_, i} <- Enum.with_index(nodes), {f, p, path} <- Enum.reverse(parts[i]) do
        %Scene.Node{name: path, parent: i, extras: %{"task" => path}, primitives: primitives([{f, p, path}])}
      end

    {nodes ++ split, parts}
  end

  # One material at a time: the corners of one material are live, not
  # the corners of all the parts, and a full collection after each
  # primitive keeps the peak low (`World.Detail.collect/1`).
  defp primitives(parts) do
    parts
    |> Enum.flat_map(fn {f, p, _} -> for m <- p.shapes, do: {m.material, {f, m}} end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {mat, shapes} ->
      # The triangles of a mesh, kept for the next part with the same
      # mesh (a bolt), for this material only.
      {corners, _} =
        Enum.flat_map_reduce(shapes, %{}, fn {f, m}, memo ->
          tris = Map.get_lazy(memo, m, fn -> Mesh.triangles(m) end)
          {place(tris, f), Map.put(memo, m, tris)}
        end)

      mat |> Scene.primitive(corners) |> Detail.collect()
    end)
  end

  defp place(corners, f), do: for({p, n} <- corners, do: {Frame.point(f, p), Frame.dir(f, n)})

  # The root part of a model stays at each level: a small model (a
  # switch of 7 cm) keeps its body at far.
  defp keep_root(%Part{detail: nil} = p), do: %{p | detail: :always}

  defp keep_root(%Assembly{nodes: [{root, item, nil} | rest]} = a),
    do: %{a | nodes: [{root, keep_root(item), nil} | rest]}

  defp keep_root(item), do: item

  defp keep?(%Part{shapes: []}, _), do: true
  defp keep?(%Part{detail: :always}, _), do: true
  defp keep?(%Part{detail: :low}, level), do: level != :near
  defp keep?(%Part{}, :near), do: true
  defp keep?(%Part{detail: :near}, _), do: false
  defp keep?(%Part{inside: true}, _), do: false

  defp keep?(%Part{} = p, level) do
    {long, thin} = Map.fetch!(@limits, level)
    {lo, hi} = Part.bounds(p)
    sides = Tuple.to_list(Vec.sub(hi, lo))
    Enum.max(sides) >= long and Enum.min(sides) >= thin
  end

  @doc "The list of the parts of a model, each with its count, in the order of the names."
  def parts(item) do
    item
    |> all_parts()
    |> Enum.frequencies_by(&{&1.name, &1.kind, &1.params, &1.sources})
    |> Enum.map(fn {{name, kind, params, sources}, count} ->
      %{"name" => name, "kind" => Atom.to_string(kind), "count" => count, "params" => params, "sources" => sources}
    end)
    # Two parts can have one name with other params: all the fields fix the order.
    |> Enum.sort_by(&{&1["name"], &1["kind"], &1["params"], &1["sources"]})
  end

  # A part with no shapes is a mark (the origin of a build), and a part of
  # the low levels stands in for other parts: not things to buy.
  defp all_parts(%Part{shapes: []}), do: []
  defp all_parts(%Part{detail: :low}), do: []
  defp all_parts(%Part{} = p), do: [p]

  defp all_parts(%Figure{} = f),
    do: [
      %Part{name: f.name, kind: f.kind, params: f.params, sources: f.sources}
      | Enum.flat_map(f.props, fn {_, item, _} -> all_parts(item) end)
    ]

  defp all_parts(%Assembly{nodes: nodes}), do: Enum.flat_map(nodes, fn {_, item, _} -> all_parts(item) end)
end
