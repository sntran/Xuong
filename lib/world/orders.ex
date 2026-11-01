defmodule World.Orders do
  @moduledoc """
  The factory (`docs/factory.md`): an order in, the files of a model out.

  An order is a map (from JSON):

  - `"blueprint"`: the name of a blueprint (`World.Orders.Blueprints`);
  - `"options"`: the options of the blueprint;
  - `"colors"`: a color `#rrggbb` for a material role (`"paint"`);
  - `"joints"`: the value of a joint at rest, in degrees or meters
    (`{"hood": 50}`);
  - `"targets"`: the point of the end of a limb of a figure, `[x, y, z]`
    in meters in the axes of the figure (`{"arm_r": [0.3, 0.4, 1.3]}`).
    The full order has this key only when it has a target: the hash of
    an order with no target stays the same.

  `check/1` gives the full order: each option with its value, and the
  keys in one order. `hash/1` is the name of its files: the same order
  gives the same hash, and the same files.
  """
  alias World.{Build, Detail, GLB, Log, Run}
  alias World.Orders.{Blueprint, Blueprints}
  @keys ~w(blueprint options colors joints targets)
  @levels %{"near" => :near, "mid" => :mid, "far" => :far}
  @files ~w(glb log replay parts receipt)

  @doc "The names of the levels of detail."
  def levels, do: Map.keys(@levels) |> Enum.sort()

  @doc """
  Check an order. Gives `{:ok, order}`, the full order, or `{:error,
  errors}`: each error is a map with its `"path"` and its `"message"`.
  """
  def check(order) when is_map(order) do
    case full(order) do
      {:ok, full} -> {:ok, full}
      {:error, errors} -> {:error, for({path, message} <- errors, do: %{"path" => path, "message" => message})}
    end
  end

  def check(_order), do: {:error, [%{"path" => "", "message" => "must be an object"}]}

  defp full(order) do
    unknown = for key <- Enum.sort(Map.keys(order)), key not in @keys, do: {key, "is not a key of an order"}

    with [] <- unknown,
         {:ok, blueprint} <- blueprint(order["blueprint"]),
         {:ok, options} <- Blueprint.check_options(blueprint.options, Map.get(order, "options", %{}), "options"),
         [] <- if(blueprint.check, do: blueprint.check.(options), else: []),
         {:ok, colors} <- colors(Map.get(order, "colors", %{})),
         {:ok, joints} <- joints(Map.get(order, "joints", %{})),
         {:ok, targets} <- targets(Map.get(order, "targets", %{})) do
      full = %{"blueprint" => blueprint.name, "options" => options, "colors" => colors, "joints" => joints}
      {:ok, if(targets == %{}, do: full, else: Map.put(full, "targets", targets))}
    else
      errors when is_list(errors) -> {:error, errors}
      {:error, errors} -> {:error, errors}
    end
  end

  defp blueprint(name) do
    case Blueprints.fetch(name) do
      {:ok, b} -> {:ok, b}
      :error -> {:error, [{"blueprint", "must be one of: #{Enum.join(Blueprints.names(), ", ")}"}]}
    end
  end

  defp colors(colors) when is_map(colors) do
    roles = GLB.palette() |> Map.keys() |> Enum.sort()
    color = Blueprint.option("color", :color)

    errors =
      Enum.flat_map(Enum.sort(colors), fn {role, c} ->
        if role in roles,
          do: elem_errors(Blueprint.value(color, c, "colors.#{role}")),
          else: [{"colors.#{role}", "must be a role: #{Enum.join(roles, ", ")}"}]
      end)

    if errors == [], do: {:ok, Map.new(colors, fn {k, v} -> {k, String.downcase(v)} end)}, else: {:error, errors}
  end

  defp colors(_), do: {:error, [{"colors", "must be an object"}]}

  defp joints(joints) when is_map(joints) do
    errors =
      for {name, v} <- Enum.sort(joints), not is_number(v), do: {"joints.#{name}", "must be a number"}

    if errors == [], do: {:ok, Map.new(joints, fn {k, v} -> {k, v / 1} end)}, else: {:error, errors}
  end

  defp joints(_), do: {:error, [{"joints", "must be an object"}]}

  defp targets(targets) when is_map(targets) do
    errors =
      for {name, v} <- Enum.sort(targets),
          not match?([x, y, z] when is_number(x) and is_number(y) and is_number(z), v),
          do: {"targets.#{name}", "must be a point: [x, y, z] in meters"}

    if errors == [], do: {:ok, Map.new(targets, fn {k, v} -> {k, Enum.map(v, &(&1 / 1))} end)}, else: {:error, errors}
  end

  defp targets(_), do: {:error, [{"targets", "must be an object"}]}

  defp elem_errors({:ok, _}), do: []
  defp elem_errors({:error, errors}), do: errors

  @doc "The hash of a full order: 32 hex digits of its SHA-256."
  def hash(order), do: :crypto.hash(:sha256, encode(order)) |> Base.encode16(case: :lower) |> binary_part(0, 32)

  @doc """
  The JSON of a value with the keys of each object in order: the same
  value gives the same bytes.
  """
  def encode(map) when is_map(map) do
    pairs =
      for {k, v} <- Enum.sort_by(map, fn {k, _} -> to_string(k) end), do: [JSON.encode!(to_string(k)), ?:, encode(v)]

    IO.iodata_to_binary([?{, Enum.intersperse(pairs, ?,), ?}])
  end

  def encode(list) when is_list(list),
    do: IO.iodata_to_binary([?[, Enum.intersperse(Enum.map(list, &encode/1), ?,), ?]])

  def encode(value), do: JSON.encode!(value)

  @doc "The files of an order."
  def files, do: @files

  # The URL of each file of a placed order: the suffix of /o/HASH (the
  # names that the Worker serves, handler.js), the level and the file.
  @urls ~w(glb mid.glb far.glb parts.json receipt.json log.json replay.glb)

  @doc """
  Place an order (`POST /orders`, and the tool `place_order` of
  `World.MCP`): check it, and keep the full order in the store
  (`World.Orders.Store`), so that its files can build later at their
  URLs. `origin` is the start of the URLs (`https://world.mkfifo.com`).

  Gives `{:ok, %{"hash", "order", "files", "replay"}}`, `{:error,
  errors}` as `check/1`, or `{:error, :store}` when the store failed.
  """
  def place(order, origin) do
    with {:ok, full} <- check(order) do
      hash = hash(full)

      case World.Orders.Store.put(hash, encode(full)) do
        :ok ->
          files = Map.new(@urls, &{&1, "#{origin}/o/#{hash}.#{&1}"})
          {:ok, %{"hash" => hash, "order" => full, "files" => files, "replay" => "#{origin}/replay.html?order=#{hash}"}}

        :error ->
          {:error, :store}
      end
    end
  end

  @doc """
  Build a file of an order at a level (`"near"`, `"mid"` or `"far"`). The
  files (`files/0`):

  - `"glb"`: the model. The people of the world build it (`World.Run`):
    the foreman makes the files with the pose and the colors of the order.
  - `"log"`: the log of a run of the order, in JSON (`World.Log`).
  - `"replay"`: the model with each part in a node of its own, with the id
    of its task, for the replay of the log.
  - `"parts"`: the list of the parts. `"receipt"`: the receipt.

  Gives `{:ok, binary}`, or `{:error, errors}` as `check/1`.
  """
  def build(order, level, file) do
    with {:ok, order} <- check(order),
         {:ok, lvl} <- level(level),
         :ok <- file(file) do
      {:ok, blueprint} = Blueprints.fetch(order["blueprint"])

      # The item and its scene are functions: in a run of the world, the
      # foreman makes the item, so the memory holds one item only (the edge
      # has 128 MB).
      item = fn -> Detail.with(lvl, fn -> blueprint.build.(order["options"]) end) end

      scene = fn item, opts ->
        targets = Map.new(Map.get(order, "targets", %{}), fn {k, [x, y, z]} -> {k, {x, y, z}} end)
        s = Build.scene(item, [level: lvl, pose: order["joints"], targets: targets] ++ opts)
        %{s | materials: Map.merge(s.materials, materials(order["colors"]))}
      end

      with :ok <- known(order, fn opts -> scene.(item.(), opts) end) do
        {:ok, make(file, order, lvl, item, scene)}
      end
    end
  end

  defp make(file, order, _lvl, item, scene) when file in ["glb", "log"] do
    {glb, log} = world(order, item, scene)
    if file == "glb", do: glb, else: log
  end

  defp make("replay", _order, _lvl, item, scene), do: GLB.encode(scene.(item.(), split: true))
  defp make("parts", _order, _lvl, item, _scene), do: parts(item.())
  defp make("receipt", order, lvl, item, scene), do: receipt(order, lvl, scene.(item.(), []))

  # A run of the world for the order: the files of the model and the log,
  # with the time and the memory of the run (run_done).
  defp world(order, item, scene) do
    run = Run.start()
    hash = hash(order)
    order = fn -> Run.order(run, item, hash, files: &GLB.encode(scene.(&1, []))) end
    {:ok, result} = Run.measure(run, hash, order)
    log = Run.log(run)
    Run.stop(run)
    {result.glb, Log.to_json(log)}
  end

  # A joint of the order must be a joint of the model, and a target a
  # limb of the model.
  defp known(order, scene) do
    names = for key <- ~w(joints targets), name <- Map.keys(Map.get(order, key, %{})), do: {key, name}

    if names == [] do
      :ok
    else
      extras = scene.([]).extras
      what = %{"joints" => {"joints", "a joint"}, "targets" => {"limbs", "a limb"}}

      errors =
        for {key, name} <- Enum.sort(names),
            {extra, noun} = what[key],
            name not in extras[extra],
            do: %{"path" => "#{key}.#{name}", "message" => "is not #{noun}: #{Enum.join(extras[extra], ", ")}"}

      if errors == [], do: :ok, else: {:error, errors}
    end
  end

  defp file(file) do
    if file in @files,
      do: :ok,
      else: {:error, [%{"path" => "file", "message" => "must be one of: #{Enum.join(@files, ", ")}"}]}
  end

  defp level(name) do
    case Map.fetch(@levels, name) do
      {:ok, l} -> {:ok, l}
      :error -> {:error, [%{"path" => "level", "message" => "must be one of: #{Enum.join(levels(), ", ")}"}]}
    end
  end

  # A color of an order keeps the roughness and the metalness of its role.
  defp materials(colors) do
    Map.new(colors, fn {role, "#" <> hex} ->
      <<r::8, g::8, b::8>> = Base.decode16!(hex, case: :lower)
      {String.to_existing_atom(role), Map.put(GLB.palette()[role], "color", [r, g, b])}
    end)
  end

  defp parts(item), do: encode(%{"name" => item.name, "parts" => Build.parts(item)})

  defp receipt(order, level, scene) do
    encode(%{
      "order" => order,
      "hash" => hash(order),
      "level" => Atom.to_string(level),
      "world" => to_string(Application.spec(:world, :vsn)),
      "name" => scene.extras["name"],
      "kind" => scene.extras["kind"],
      "size" => scene.extras["size"],
      "joints" => scene.extras["joints"],
      "limbs" => scene.extras["limbs"],
      "sources" => scene.extras["sources"]
    })
  end
end
