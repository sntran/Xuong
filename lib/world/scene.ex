defmodule World.Scene do
  @moduledoc """
  A scene for the GLB writer: a list of nodes (each with its parent, its
  frame and its primitives), skins and animations. `World.Build` makes it
  from a model; `World.GLB` writes it.

  The points and the frames are in the axes of World (x to the right
  side, y to the front, z up). The writer turns them to the axes of glTF.
  """
  alias World.{Frame, Vec}
  defstruct name: "model", extras: %{}, nodes: [], skins: [], animations: [], materials: %{}

  defmodule Node do
    @moduledoc """
    A node: its name, the index of its parent (or nil), its frame relative
    to the parent, and its scale (the same on each axis, after the frame:
    the size of the head of a person).
    """
    defstruct name: "node", parent: nil, frame: %World.Frame{}, scale: 1.0, primitives: [], extras: %{}, skin: nil
  end

  defmodule Primitive do
    @moduledoc """
    The triangles of one material: points, normals, an index list, and
    optional UV, joints (4 for each point), weights (4 for each point),
    colors (`{r, g, b}`, 0 to 255, for each point), the length of the
    fur of each point (m) and the direction of the fur of each point (a
    unit vector along the skin, at rest), and the morph targets (a list of
    `{name, moves}` or `{name, moves, normals}`, a move for each point and
    a change of each normal: the shapes of a face). The moves (or the
    changes) can also be a map of the index of a point to its move: the
    points not in the map do not move (a shape of the face moves few of
    the points of a body).
    """
    defstruct material: :paint,
              positions: [],
              normals: [],
              indices: [],
              uvs: nil,
              joints: nil,
              weights: nil,
              colors: nil,
              fur: nil,
              fur_dirs: nil,
              targets: nil
  end

  @doc """
  A primitive from the corners of `World.Mesh.triangles/2` (three for
  each triangle). Corners with the same point and normal share an index.
  """
  def primitive(material, corners) do
    {indices, {_, verts, _}} =
      Enum.map_reduce(corners, {%{}, [], 0}, fn {p, n}, {seen, verts, count} ->
        key = {round6(p), round6(n)}

        case seen do
          %{^key => i} -> {i, {seen, verts, count}}
          _ -> {count, {Map.put(seen, key, count), [key | verts], count + 1}}
        end
      end)

    verts = Enum.reverse(verts)

    %Primitive{
      material: material,
      positions: Enum.map(verts, &elem(&1, 0)),
      normals: Enum.map(verts, &elem(&1, 1)),
      indices: indices
    }
  end

  defp round6({x, y, z}), do: {Float.round(x / 1, 6), Float.round(y / 1, 6), Float.round(z / 1, 6)}

  @doc "The number of triangles of a scene."
  def triangles(%__MODULE__{nodes: nodes}) do
    nodes |> Enum.flat_map(& &1.primitives) |> Enum.map(&div(length(&1.indices), 3)) |> Enum.sum()
  end

  @doc """
  The frame of each node in the axes of the scene, by index. The frame of
  a node with a scale has the scale in its axes.
  """
  def world_frames(%__MODULE__{nodes: nodes}) do
    nodes
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {n, i}, acc ->
      local = scaled(n.frame, n.scale)
      Map.put(acc, i, if(n.parent == nil, do: local, else: Frame.compose(acc[n.parent], local)))
    end)
  end

  defp scaled(frame, 1.0), do: frame
  defp scaled(%Frame{x: x, y: y, z: z} = f, s), do: %{f | x: Vec.scale(x, s), y: Vec.scale(y, s), z: Vec.scale(z, s)}

  @doc """
  The box of all points of the scene, in its axes: `{min, max}`. The
  points of a skinned mesh move with their bones.
  """
  def bounds(%__MODULE__{nodes: nodes, skins: skins} = scene) do
    frames = world_frames(scene)

    nodes
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {%{skin: nil} = n, i} -> for p <- n.primitives, pt <- p.positions, do: Frame.point(frames[i], pt)
      {n, _} -> skinned(n, Enum.at(skins, n.skin), frames)
    end)
    |> Vec.bounds()
  end

  defp skinned(node, skin, frames) do
    bones =
      skin.joints
      |> Enum.zip(skin.inverse_bind)
      |> Enum.map(fn {j, ib} -> Frame.compose(frames[j], ib) end)
      |> List.to_tuple()

    for p <- node.primitives, {pt, js, ws} <- Enum.zip([p.positions, p.joints, p.weights]) do
      Enum.zip(Tuple.to_list(js), Tuple.to_list(ws))
      |> Enum.map(fn {j, w} -> Vec.scale(Frame.point(elem(bones, j), pt), w) end)
      |> Enum.reduce(&Vec.add/2)
    end
  end
end
