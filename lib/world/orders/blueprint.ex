defmodule World.Orders.Blueprint do
  @moduledoc """
  A blueprint: a family of models with options (`docs/factory.md`). An
  order gives the options; the blueprint checks them, gives the default
  of each option that the order does not give, and builds the model.

  - `name`: the name of the blueprint in an order (`"person"`).
  - `doc`: what the blueprint builds.
  - `options`: a list of `World.Orders.Blueprint.Option`.
  - `build`: a function of the options (a map with a string key for each
    option) to a `World.Assembly` or a `World.Part`.
  - `check`: a function of the options to a list of errors, for the
    checks across options (a window must be in its wall). Each error is
    `{path, message}`.
  - `sources`: where the data of the blueprint comes from.
  """
  defstruct name: nil, doc: "", options: [], build: nil, check: nil, sources: []

  defmodule Option do
    @moduledoc """
    An option of a blueprint.

    - `type`: `:number`, `:integer`, `:choice`, `:boolean`, `:color`,
      `:list`, `:object`, or `:data` (any data of JSON that the function
      `check` checks: of the value and its path, to `{:ok, value}` or
      `{:error, errors}`).
    - `default`: the value when the order does not give one; `:required`
      when the order must give it.
    - `unit`: for a number (`"m"`, `"years"`).
    - `min`, `max`: the range of a number or an integer, and the most
      items of a list (`max`).
    - `values`: the values of a choice.
    - `item`: the option of each item of a list (its name is not used).
    - `presets`: the names of the presets of a list: the order can give
      the name in place of the list (the windows `"crew"` of a van), and
      the build makes the list of the preset.
    - `fields`: the options of an object.
    """
    defstruct name: nil,
              type: :number,
              default: :required,
              unit: nil,
              min: nil,
              max: nil,
              values: nil,
              item: nil,
              fields: nil,
              presets: nil,
              check: nil,
              doc: ""
  end

  @doc "An option: the name, the type, and the keys of `World.Orders.Blueprint.Option`."
  def option(name, type, opts \\ []), do: struct!(Option, [name: name, type: type] ++ opts)

  @doc """
  Check the options of an order (a map with string keys) against the
  options of a blueprint. Gives `{:ok, options}` with a value for each
  option, or `{:error, errors}`: each error is `{path, message}`, with
  the path from `prefix` (`"options.age"`).
  """
  def check_options(options, given, prefix) when is_map(given) do
    known = MapSet.new(options, & &1.name)

    unknown =
      for key <- Enum.sort(Map.keys(given)),
          not MapSet.member?(known, key),
          do: {"#{prefix}.#{key}", "is not an option"}

    {values, errors} =
      Enum.reduce(options, {%{}, unknown}, fn o, {values, errors} ->
        path = "#{prefix}.#{o.name}"

        case {Map.fetch(given, o.name), o.default} do
          {:error, :required} -> {values, errors ++ [{path, "is required"}]}
          {:error, default} -> {Map.put(values, o.name, default), errors}
          # The full order gives null for an option with no value by default.
          {{:ok, nil}, nil} -> {Map.put(values, o.name, nil), errors}
          {{:ok, raw}, _} -> put(values, errors, o.name, value(o, raw, path))
        end
      end)

    if errors == [], do: {:ok, values}, else: {:error, errors}
  end

  def check_options(_options, _given, prefix), do: {:error, [{prefix, "must be an object"}]}

  defp put(values, errors, name, {:ok, v}), do: {Map.put(values, name, v), errors}
  defp put(values, errors, _name, {:error, more}), do: {values, errors ++ more}

  @doc """
  The value of an option from an order. A number, an integer and a yes
  or no can also come as a string (from the query of a URL), and a list
  as a string of items with commas.
  """
  def value(%Option{type: :number} = o, raw, path) do
    case number(raw) do
      {:ok, x} -> range(o, x / 1, path)
      :error -> {:error, [{path, "must be a number"}]}
    end
  end

  def value(%Option{type: :integer} = o, raw, path) do
    case number(raw) do
      {:ok, x} when x == trunc(x) -> range(o, trunc(x), path)
      _ -> {:error, [{path, "must be an integer"}]}
    end
  end

  def value(%Option{type: :choice, values: values}, raw, path) do
    if raw in values, do: {:ok, raw}, else: {:error, [{path, "must be one of: #{Enum.join(values, ", ")}"}]}
  end

  def value(%Option{type: :boolean}, raw, path) do
    case raw do
      b when is_boolean(b) -> {:ok, b}
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ -> {:error, [{path, "must be true or false"}]}
    end
  end

  def value(%Option{type: :color}, raw, path) do
    if is_binary(raw) and Regex.match?(~r/^#[0-9a-fA-F]{6}$/, raw),
      do: {:ok, String.downcase(raw)},
      else: {:error, [{path, "must be a color #rrggbb"}]}
  end

  def value(%Option{type: :list, presets: [_ | _] = presets} = o, raw, path) when is_binary(raw) do
    if raw in presets, do: {:ok, raw}, else: value(%{o | presets: nil}, raw, path)
  end

  def value(%Option{type: :list} = o, raw, path) when is_binary(raw),
    do: value(o, if(raw == "", do: [], else: String.split(raw, ",")), path)

  def value(%Option{type: :list, item: item, max: max}, raw, path) when is_list(raw) do
    if max && length(raw) > max do
      {:error, [{path, "must have at most #{max} items"}]}
    else
      results = for {x, i} <- Enum.with_index(raw), do: value(item, x, "#{path}.#{i}")
      errors = for {:error, e} <- results, do: e

      if errors == [],
        do: {:ok, for({:ok, v} <- results, do: v)},
        else: {:error, List.flatten(errors)}
    end
  end

  def value(%Option{type: :list}, _raw, path), do: {:error, [{path, "must be a list"}]}
  def value(%Option{type: :object, fields: fields}, raw, path), do: check_options(fields, raw, path)
  def value(%Option{type: :data, check: check}, raw, path), do: check.(raw, path)

  defp number(x) when is_number(x), do: {:ok, x}

  defp number(s) when is_binary(s) do
    case Float.parse(s) do
      {x, ""} -> {:ok, x}
      _ -> :error
    end
  end

  defp number(_), do: :error

  defp range(%Option{min: min, max: max, unit: unit}, x, path) do
    if (min == nil or x >= min) and (max == nil or x <= max),
      do: {:ok, x},
      else: {:error, [{path, "must be from #{min} to #{max}#{if unit, do: " " <> unit}"}]}
  end

  @doc "A blueprint as JSON data (the page `/blueprints` of the factory)."
  def describe(%__MODULE__{} = b) do
    %{"name" => b.name, "doc" => b.doc, "options" => Enum.map(b.options, &describe_option/1), "sources" => b.sources}
  end

  defp describe_option(%Option{} = o) do
    %{
      "name" => o.name,
      "type" => Atom.to_string(o.type),
      "default" => if(o.default == :required, do: nil, else: o.default),
      "required" => o.default == :required,
      "unit" => o.unit,
      "min" => o.min,
      "max" => o.max,
      "values" => o.values,
      "presets" => o.presets,
      "item" => if(o.item, do: describe_option(o.item)),
      "fields" => if(o.fields, do: Enum.map(o.fields, &describe_option/1)),
      "doc" => o.doc
    }
    |> Map.reject(fn {_, v} -> v == nil end)
  end
end
