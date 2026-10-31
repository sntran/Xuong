defmodule World.People.Data do
  @moduledoc """
  The data of MakeHuman (CC0) in `priv/makehuman`: the base mesh, the
  targets of the body, the skeleton "game_engine" with its weights, and
  the assets (skins, eyes, eyebrows, eyelashes, hair, clothes, low-poly
  bodies). `scripts/makehuman.py` makes the folder.

  The units of MakeHuman are decimeters, with +Y up and the front to +Z.
  Each function reads its file once, then keeps the data in
  `:persistent_term`.
  """

  @doc "The folder of the data (in `priv/`, so that a release has it)."
  def dir, do: Path.join(:code.priv_dir(:world), "makehuman")

  @doc """
  The base mesh: `%{points: tuple of {x, y, z}, uvs: tuple of {u, v},
  groups: %{name => [face]}}`. A face is a list of `{point, uv}` indices.
  """
  def base, do: cached(:base, fn -> parse_obj(read_gz("base.obj.gz")) end)

  @doc "The skeleton: a map of each bone to its head, tail, parent and roll."
  def rig, do: cached(:rig, fn -> JSON.decode!(read_gz("rig.json.gz")) end)

  @doc "The weights: a map of each bone to a list of `[point, weight]`."
  def weights, do: cached(:weights, fn -> read_gz("weights.json.gz") |> JSON.decode!() |> Map.fetch!("weights") end)

  @doc "The targets, by name (see `parse_targets/1` and `target/1`)."
  def targets, do: cached(:targets, fn -> parse_targets(read_gz("targets.bin.gz")) end)

  @doc "The units of the expressions of the mouth (`expressions.bin.gz`), as `targets/0`."
  def expressions, do: cached(:expressions, fn -> parse_targets(read_gz("expressions.bin.gz")) end)

  @doc "The list of the assets (`assets.json`)."
  def assets, do: cached(:assets, fn -> File.read!(Path.join(dir(), "assets.json")) |> JSON.decode!() end)

  @doc """
  An asset by its kind and name: its mesh (as `base/0`), its fit to the
  body, the path of its texture (or nil), the mean color of the texture,
  the mean of a gray texture (`gray`, a hair: its color is the factor of
  its material), and if it is transparent.
  """
  def asset(kind, name) do
    cached({:asset, kind, name}, fn ->
      entry = get_in(assets(), [kind, name]) || raise ArgumentError, "no asset #{kind}/#{name}"
      folder = Path.join(dir(), kind)

      %{
        name: name,
        mesh: if(entry["obj"], do: parse_obj(read_gz(Path.join(kind, entry["obj"])))),
        fit: if(entry["fit"], do: parse_fit(read_gz(Path.join(kind, entry["fit"])))),
        texture: if(entry["texture"], do: Path.join(folder, entry["texture"])),
        color: Map.get(entry, "color", [128, 128, 128]),
        gray: entry["gray"],
        transparent: Map.get(entry, "transparent", false)
      }
    end)
  end

  # A parse makes much garbage. A short process parses and puts the
  # value in `:persistent_term`: its heap goes at its end, and the caller
  # gets the value with no copy. An error in the parse is raised again in
  # the caller.
  defp cached(key, fun) do
    k = {__MODULE__, key}

    case :persistent_term.get(k, nil) do
      nil ->
        {pid, ref} =
          spawn_monitor(fn ->
            try do
              :persistent_term.put(k, fun.())
            catch
              kind, reason -> exit({:raise, kind, reason, __STACKTRACE__})
            end
          end)

        receive do
          {:DOWN, ^ref, :process, ^pid, :normal} -> :persistent_term.get(k)
          {:DOWN, ^ref, :process, ^pid, {:raise, kind, reason, stack}} -> :erlang.raise(kind, reason, stack)
        end

      value ->
        value
    end
  end

  defp read_gz(path), do: :zlib.gunzip(File.read!(Path.join(dir(), path)))

  @doc "Parse the text of an OBJ file: points, UV and faces by group."
  def parse_obj(text) do
    {ps, uvs, groups, _} =
      text
      |> String.split("\n")
      |> Enum.reduce({[], [], %{}, "default"}, fn line, {ps, uvs, groups, g} = acc ->
        case String.split(line) do
          ["v", x, y, z | _] -> {[{num(x), num(y), num(z)} | ps], uvs, groups, g}
          ["vt", u, v | _] -> {ps, [{num(u), num(v)} | uvs], groups, g}
          ["g", name | _] -> {ps, uvs, groups, name}
          ["usemtl" | _] -> acc
          ["f" | corners] -> {ps, uvs, Map.update(groups, g, [face(corners)], &[face(corners) | &1]), g}
          _ -> acc
        end
      end)

    %{
      points: ps |> Enum.reverse() |> List.to_tuple(),
      uvs: uvs |> Enum.reverse() |> List.to_tuple(),
      groups: Map.new(groups, fn {k, fs} -> {k, Enum.reverse(fs)} end)
    }
  end

  defp face(corners) do
    for c <- corners do
      case String.split(c, "/") do
        [v, t | _] when t != "" -> {String.to_integer(v) - 1, String.to_integer(t) - 1}
        [v | _] -> {String.to_integer(v) - 1, nil}
      end
    end
  end

  defp num(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  @doc """
  Parse a fit file (`.mhclo` or `.proxy`): the three scales, a reference
  for each point of the asset, and the points of the body that the asset
  hides.
  """
  def parse_fit(text) do
    lines = String.split(text, "\n")

    {fit, _} =
      Enum.reduce(lines, {%{scales: %{}, refs: [], delete: []}, :head}, fn line, {fit, mode} ->
        words = String.split(line)

        cond do
          words == [] or String.starts_with?(line, "#") ->
            {fit, mode}

          hd(words) == "verts" ->
            {fit, :verts}

          hd(words) == "delete_verts" ->
            {fit, :delete}

          mode == :head and hd(words) in ["x_scale", "y_scale", "z_scale"] ->
            {put_scale(fit, words), mode}

          mode == :verts and length(words) == 9 ->
            {%{fit | refs: [ref9(words) | fit.refs]}, mode}

          mode == :verts and length(words) == 1 ->
            {%{fit | refs: [{[String.to_integer(hd(words))], [1.0], {0.0, 0.0, 0.0}} | fit.refs]}, mode}

          mode == :delete ->
            {%{fit | delete: [words | fit.delete]}, mode}

          # A line of words between "verts" and the first reference (as
          # "material") does not end the references.
          true ->
            {fit, if(mode == :verts and fit.refs != [], do: :tail, else: mode)}
        end
      end)

    delete = fit.delete |> Enum.reverse() |> List.flatten() |> ranges()
    %{fit | refs: fit.refs |> Enum.reverse() |> List.to_tuple(), delete: MapSet.new(delete)}
  end

  defp put_scale(fit, [axis, a, b, d]),
    do: put_in(fit, [:scales, axis], {String.to_integer(a), String.to_integer(b), num(d)})

  defp ref9(words) do
    [v1, v2, v3 | rest] = words
    [w1, w2, w3, d1, d2, d3] = Enum.map(rest, &num/1)
    {[String.to_integer(v1), String.to_integer(v2), String.to_integer(v3)], [w1, w2, w3], {d1, d2, d3}}
  end

  # "1355 - 1388 1393" is 1355 to 1388, and 1393.
  defp ranges(words), do: ranges(words, [])

  defp ranges([a, "-", b | rest], acc),
    do: ranges(rest, Enum.to_list(String.to_integer(a)..String.to_integer(b)) ++ acc)

  defp ranges([a | rest], acc), do: ranges(rest, [String.to_integer(a) | acc])
  defp ranges([], acc), do: acc

  @doc """
  Parse the binary targets (format XTG2 of `scripts/makehuman.py`): a map
  of each name to its columns, not decoded yet (`target/1` decodes one).
  """
  def parse_targets(<<"XTG2", count::little-32, rest::binary>>) do
    {targets, <<>>} =
      Enum.map_reduce(1..count//1, rest, fn _, <<len::little-16, name::binary-size(len), n::little-32, rest::binary>> ->
        size = 2 * n

        <<idx::binary-size(^size), dx::binary-size(^size), dy::binary-size(^size), dz::binary-size(^size),
          rest::binary>> = rest

        {{name, {idx, dx, dy, dz}}, rest}
      end)

    Map.new(targets)
  end

  @doc "A target by its name: a list of `{point, {dx, dy, dz}}`, in decimeters."
  def target(name), do: decode(:target, targets(), name)

  @doc "A unit of an expression by its name (`units/ORIGIN/mouth-UNIT`), as `target/1`."
  def expression(name), do: decode(:expression, expressions(), name)

  defp decode(kind, table, name) do
    cached({kind, name}, fn ->
      {idx, dx, dy, dz} = Map.fetch!(table, name)
      indices = Enum.scan(for(<<d::little-16 <- idx>>, do: d), &(&1 + &2))
      [xs, ys, zs] = for b <- [dx, dy, dz], do: for(<<v::little-signed-16 <- b>>, do: v * 0.0025)
      Enum.zip_with([indices, xs, ys, zs], fn [i, x, y, z] -> {i, {x, y, z}} end)
    end)
  end
end
