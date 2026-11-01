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
  alias World.Vehicles.Van.{BodyShop, Chassis, Closures, Trim, Upfit}

  @external_resource data_path = Path.join([__DIR__, "..", "..", "..", "priv", "data", "vans.json"])
  @data data_path |> File.read!() |> JSON.decode!()

  # The white of the van (Oxford White): its color by eye from the photos.
  @white %{"color" => [240, 241, 238], "roughness" => 0.32, "metalness" => 0.05}

  @doc "The names of the models of vans."
  def models, do: @data["models"] |> Map.keys() |> Enum.sort()

  @doc """
  The data of a model, with its make. The `openings` of a model (a
  standard roof has lower doors) replace those of its make: each key of
  a map, or the full value of the key.
  """
  def model(name) do
    m = Map.fetch!(@data["models"], name)
    own = Map.get(m, "openings", %{})

    make =
      Map.update!(
        Map.fetch!(@data["makes"], m["make"]),
        "openings",
        &Map.merge(&1, own, fn _k, a, b -> merge(a, b) end)
      )

    Map.put(m, "make_data", make)
  end

  defp merge(%{} = a, %{} = b), do: Map.merge(a, b)
  defp merge(_a, b), do: b

  @doc "The hull of a model."
  def hull(name) do
    m = model(name)
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
  The flat part of the roof of a model: the first and the last `d` (from
  the front) where an item can be.
  """
  def roof_span(name) do
    h = hull(name)
    {d0, d1} = Hull.span(h)
    flat = Enum.find(Hull.stations(h, d0, d1, 0.01), &(Hull.z_high(h, &1) >= h.top - 1.0e-6))
    {flat, h.length - Hull.back(h, h.top)}
  end

  @doc """
  A van from the line. The options: `name` of the assembly, `windows`
  (`:cargo`, the default: the windows of the cab only; `:crew`: the
  windows of the second row too, and its seats; `:passenger`: the
  windows all around, and its rows of seats), `engine_bay` (the items of
  DIY in the bay: `:dc_charger`, `:second_alternator`), `roof` (the items
  on the roof: `{:fan, d}` and `{:solar, d}`, at `d` from the front).
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

  # The order on the line: the model, its make, its hull and its windows.
  defp order(model_name, opts) do
    m = model(model_name)
    h = hull(model_name)
    windows = Keyword.get(opts, :windows, :cargo)
    %{m: m, make: m["make_data"], h: h, l: h.length, f: m["front"] / 1, windows: windows}
  end
end
