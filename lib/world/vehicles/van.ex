defmodule World.Vehicles.Van do
  @moduledoc """
  The vans of DIY and of Phượt, built as on the line of the maker, from
  their data (`priv/data/vans.json`): the hull (`World.Vehicles.Hull`)
  from the traces of the side and the numbers of the maker, then the
  stations of the line.

  1. The body shop (`World.Vehicles.Van.BodyShop`): the body of sheets on
     the hull, with the openings of the doors and the windows
     (`World.Vehicles.Van.Openings`).
  2. The closures (`World.Vehicles.Van.Closures`): the hood and the doors
     on their hinges and rails, with the mirrors.
  3. The paint: the role `paint` of the body and the doors (Oxford
     White, unless the order gives a color).
  4. The trim (`World.Vehicles.Van.Trim`): the glass, the black plastic,
     the lamps, the grille, the small parts, the dash and the seats.
  5. The chassis (`World.Vehicles.Van.Chassis`): the engine bay and the
     wheels.
  6. The upfit (`World.Vehicles.Van.Upfit`): the items of DIY on the
     roof.

  Each part has its station in its `params`, so the list of the parts is
  the build sheet of the van. The near level is the van of the line,
  with real openings and the cab inside; the mid level has a closed
  body with the doors on it; the far level has the closed body only.

  A point of the van is at `d` back from its front; the parts are made
  with the back of the van at y = 0, and the assembly moves it to its
  center. The numbers of the parts come from the photos and the drawings
  in the sources of the make (`d` and `z` in meters).
  """
  alias World.{Assembly, Frame}
  alias World.Vehicles.{Hull, Wheels}
  alias World.Vehicles.Van.{BodyShop, Chassis, Closures, Order, Trim, Upfit}

  @external_resource data_path = Path.join([__DIR__, "..", "..", "..", "priv", "data", "vans.json"])
  @data data_path |> File.read!() |> JSON.decode!()

  # The white of the van (Oxford White): its color by eye from the photos.
  @white %{"color" => [240, 241, 238], "roughness" => 0.32, "metalness" => 0.05}

  @doc "The names of the models of vans."
  def models, do: @data["models"] |> Map.keys() |> Enum.sort()

  # The sizes that an order can give, and how far each can go from the
  # size of the model (the height: down only to the traces, see `sizes/1`).
  @sizes %{"length" => 0.05, "width" => 0.05, "height" => 0.3}

  @doc """
  The data of a model, with its make. The `openings` of a model (a
  standard roof has lower doors) replace those of its make: each key of
  a map, or the full value of the key. An order (a map) replaces more:
  its `size` (`length`, `width`, `height`, in meters; nil for the size
  of the model) and its `doors` (`World.Vehicles.Van.Order`).
  """
  def model(name, order \\ %{}) do
    m = Map.fetch!(@data["models"], name)
    m = for {k, v} <- order["size"] || %{}, Map.has_key?(@sizes, k), v != nil, into: m, do: {k, v / 1}
    own = Map.get(m, "openings", %{})

    make =
      Map.update!(
        Map.fetch!(@data["makes"], m["make"]),
        "openings",
        &Map.merge(&1, own, fn _k, a, b -> merge(a, b) end)
      )

    m = Map.put(m, "make_data", make)
    if Map.has_key?(order, "doors"), do: Order.put_doors(m, order["doors"]), else: m
  end

  defp merge(%{} = a, %{} = b), do: Map.merge(a, b)
  defp merge(_a, b), do: b

  @doc """
  The sizes that an order can give to a model: `{min, max}` of its
  `length`, `width` and `height`, in meters. The default of each is the
  size of the model (the size of the US market). The height goes down
  only to the top of its traces (less 0.01 m): under it, the shape of
  the roof is not known.
  """
  def sizes(name) do
    m = model(name)
    top = m["make_data"]["traces"][m["roof"]]["top"]

    Map.new(@sizes, fn
      {"height", d} -> {"height", {Float.round(min(top - 0.01, m["height"]), 3), Float.round(m["height"] + d, 3)}}
      {k, d} -> {k, {Float.round(m[k] - d, 3), Float.round(m[k] + d, 3)}}
    end)
  end

  @doc "The hull of a model, with the sizes of an order (`model/2`)."
  def hull(name, order \\ %{}) do
    m = model(name, order)
    make = m["make_data"]
    t = make["traces"][m["roof"]]
    h = make["hull"]
    {height, top} = {m["height"] / 1, t["top"] / 1}

    # The points over 2 m stretch to the height of the model.
    z = fn
      "top" -> height
      z when z > 2.0 -> 2.0 + (z - 2.0) * (height - 2.0) / (top - 2.0)
      z -> z / 1
    end

    line = fn pts -> for [d, zz] <- pts, do: {d / 1, z.(zz)} end
    {f, wb} = {m["front"] / 1, m["wheelbase"] / 1}
    r = Wheels.tire_radius(m["tire"])
    [af, ar] = h["arches"]

    Hull.new(
      length: m["length"] / 1,
      width: m["width"] / 1,
      top: height,
      front: line.(make["front"] ++ t["roof"]),
      back: line.(t["back"]),
      sill: h["sill"] / 1,
      arches: [{f, r, af / 1}, {f + wb, r, ar / 1}],
      belt: h["belt"] / 1,
      lean: h["lean"] / 1,
      edge: h["edge"] / 1,
      crown: List.to_tuple(Enum.map(h["crown"], &(&1 / 1))),
      nose: List.to_tuple(Enum.map(h["nose"], &(&1 / 1))),
      tail: List.to_tuple(Enum.map(h["tail"], &(&1 / 1)))
    )
  end

  # The half length of each item on the roof, along the van.
  @roof_items %{fan: 0.286, solar: 0.861}

  @doc "The half length of an item on the roof (`:fan`, `:solar`), along the van."
  def roof_item(kind), do: Map.fetch!(@roof_items, kind)

  @doc """
  The flat part of the roof of a model, with the sizes of an order: the
  first and the last `d` (from the front) where an item can be.
  """
  def roof_span(name, order \\ %{}) do
    h = hull(name, order)
    {d0, d1} = Hull.span(h)
    flat = Enum.find(Hull.stations(h, d0, d1, 0.01), &(Hull.z_high(h, &1) >= h.top - 1.0e-6))
    {flat, h.length - Hull.back(h, h.top)}
  end

  @doc """
  A van from the line. The options: `name` of the assembly, `windows`
  (a preset: `cargo`, the default, the windows of the cab only; `crew`:
  the windows of the second row too; `passenger`: the windows all
  around; or a list of windows, `World.Vehicles.Van.Order`), `rows` (the
  rows of seats behind the front seats; by default from the preset),
  `doors` (the numbers of the doors), `engine_bay` (the items of DIY in
  the bay: `:dc_charger`, `:second_alternator`), `roof` (the items on
  the roof: `{:fan, d}` and `{:solar, d}`, at `d` from the front),
  `size` (the `length`, the `width` and the `height` of the van, over
  those of the model: `sizes/1`).
  """
  def build(model_name, opts \\ []) do
    van = order(model_name, opts)

    Assembly.new(Keyword.get(opts, :name, "van_" <> model_name), BodyShop.body(van),
      root: "body",
      kind: :vehicle,
      sources: van.m["sources"] ++ van.make["sources"],
      materials: %{paint: @white},
      place: Frame.move({0.0, -van.l / 2, 0.0})
    )
    |> Assembly.add("inside", BodyShop.inside(van), at: "origin", port: "origin")
    |> Closures.hang(van)
    |> Trim.fit(van)
    |> Chassis.marry(van, Keyword.get(opts, :engine_bay, []))
    |> Upfit.fit(van, Keyword.get(opts, :roof, []))
  end

  @doc """
  The errors of an order of a model: its sizes (`sizes/1`), its doors, its
  windows and its rows (`World.Vehicles.Van.Order.check/4`). The order
  is a map of `size`, `doors`, `windows` and `rows`.
  """
  def check(name, order) do
    limits = sizes(name)

    sizes =
      for {k, v} <- Enum.sort(order["size"] || %{}),
          v != nil,
          {min, max} = limits[k],
          v < min or v > max,
          do: {"options.size.#{k}", "must be from #{min} to #{max} m for the model #{name}"}

    if sizes == [],
      do: Order.check(model(name, Map.take(order, ["size"])), order["doors"], order["windows"], order["rows"]),
      else: sizes
  end

  # The order on the line: the model with the sizes and the doors of the
  # order, its make, its hull, its windows and its rows of seats.
  defp order(model_name, opts) do
    order = %{"size" => Keyword.get(opts, :size, %{}), "doors" => Keyword.get(opts, :doors, %{})}
    m = model(model_name, order)
    h = hull(model_name, order)
    windows = Keyword.get(opts, :windows, :cargo)

    %{
      m: m,
      make: m["make_data"],
      h: h,
      l: h.length,
      f: m["front"] / 1,
      glass: Order.windows(m, windows),
      rows: Order.rows(m, windows, Keyword.get(opts, :rows))
    }
  end
end
