defmodule World.Vehicles.Van.Order do
  @moduledoc """
  The order of a van (`World.Vehicles.Van`): its doors, its windows and
  its rows of seats, as numbers over those of its model.

  - `doors`: `front` (`back`, the edge behind the front axle; `top`),
    `sliding` (`from` and `to` behind the front axle; `top`) and `rear`
    (`height` of the opening over the floor), in meters. The doors
    factory makes each door to these numbers (`World.Openings.Van`).
  - `windows`: a preset (`cargo`, `crew`, `passenger`) or a list of
    windows. Each window has its place (`at`: `left` and `right` in the
    sides of the body, `slider` in the sliding door, `rear_doors` in the
    rear doors), and `from`, `to` (behind the front axle), `bottom` and
    `top` (over the ground), in meters. A place has one window or none.
  - `rows`: the rows of seats behind the front seats (the rows of the
    make that go in the body). By default: 1 for the preset crew, all
    for the preset passenger, and none else.

  A number that the order does not give is the number of the model, in
  the limits of the van (`limits/2`): a window of the make that is a
  guess (the windows of the Transit on a Sprinter) moves into its door
  or its side.
  """

  @presets ~w(cargo crew passenger)
  @places ~w(left right slider rear_doors)

  @doc "The presets of the windows."
  def presets, do: @presets

  @doc "The places of a window."
  def places, do: @places

  # --- The doors --------------------------------------------------------------------------

  @doc """
  The numbers of the doors of a model (`m`, the data of `World.Vehicles.Van.model/2`
  with no doors of an order): `%{"front" => %{"back", "top"}, "sliding"
  => %{"from", "to", "top"}, "rear" => %{"height"}}`.
  """
  def doors(m) do
    o = m["make_data"]["openings"]
    outline = o["front_door"]
    s = o["sliding_door"]

    %{
      "front" => %{"back" => Enum.max(for [x, _] <- outline, do: x), "top" => Enum.max(for [_, z] <- outline, do: z)},
      "sliding" => %{"from" => s["from"], "to" => s["to"], "top" => List.last(s["z"])},
      "rear" => %{"height" => m["rear_door"]}
    }
  end

  @doc """
  The limits of the numbers of the doors of a model, with the doors of an
  order (`now`, all the numbers of `doors/1`): `{min, max}` of each number. A door moves only a little from that of the
  model, and stays in the body: the front door ends before the sliding
  door, the sliding door ends before the arch of the rear wheel, the
  rear doors end under the roof.
  """
  def door_limits(m, now) do
    d = doors(m)
    wb = m["wheelbase"] / 1
    [_, ar] = m["make_data"]["hull"]["arches"]
    room = m["height"] - m["floor"] - 0.04
    near = fn v, a, b -> {v - a, v + b} end

    %{
      "front" => %{
        "back" => cap(near.(d["front"]["back"], 0.2, 0.2), now["sliding"]["from"] - 0.02),
        "top" => near.(d["front"]["top"], 0.15, 0.15)
      },
      "sliding" => %{
        "from" => floor_at(near.(d["sliding"]["from"], 0.3, 0.3), now["front"]["back"] + 0.02),
        "to" => cap(near.(d["sliding"]["to"], 0.3, 0.3), wb - ar),
        "top" => near.(d["sliding"]["top"], 0.4, 0.3)
      },
      "rear" => %{"height" => cap(near.(d["rear"]["height"], 0.4, 0.4), room)}
    }
  end

  @doc """
  The model with the doors of an order: the numbers that the order gives,
  and the others of the model, each in its limits.
  """
  def put_doors(m, given) do
    d = doors(m)

    given =
      for {k, v} <- given || %{},
          v != nil,
          into: %{},
          do: {k, for({f, x} <- v || %{}, x != nil, into: %{}, do: {f, x / 1})}

    wanted = Map.new(d, fn {k, v} -> {k, Map.merge(v, Map.get(given, k, %{}))} end)
    limits = door_limits(m, wanted)

    now =
      Map.new(wanted, fn {k, v} ->
        {k, Map.new(v, fn {f, x} -> {f, if(Map.has_key?(given[k] || %{}, f), do: x, else: clamp(x, limits[k][f]))} end)}
      end)

    o = m["make_data"]["openings"]
    {back, top} = {d["front"]["back"], d["front"]["top"]}

    outline =
      for [x, z] <- o["front_door"],
          do: [if(x == back, do: now["front"]["back"], else: x), if(z == top, do: now["front"]["top"], else: z)]

    [z0, _] = o["sliding_door"]["z"]
    s = %{"from" => now["sliding"]["from"], "to" => now["sliding"]["to"], "z" => [z0, now["sliding"]["top"]]}
    o = %{o | "front_door" => outline, "sliding_door" => Map.merge(o["sliding_door"], s)}

    m
    |> Map.put("rear_door", now["rear"]["height"])
    |> put_in(["make_data", "openings"], o)
  end

  # --- The windows ------------------------------------------------------------------------

  @doc """
  The windows of an order (a preset, or a list of windows), each with all
  its numbers: `%{"at", "from", "to", "bottom", "top"}` (no `from` and
  `to` for the rear doors). `m` has the doors of the order.
  """
  def windows(m, preset) when is_atom(preset), do: windows(m, Atom.to_string(preset))
  def windows(m, preset) when preset in @presets, do: windows(m, preset_list(m, preset))

  def windows(m, list) when is_list(list) do
    for w <- list do
      at = w["at"]
      given = for {k, v} <- w, k != "at", v != nil, into: %{}, do: {k, v / 1}
      limits = window_limits(m, at)

      defaults =
        Map.new(window_defaults(m, at), fn {k, v} -> {k, Map.get(given, k, clamp(v, limits[k]))} end)

      Map.put(defaults, "at", at)
    end
  end

  # The windows of a preset: crew has the window of the second row at the
  # left, the window of the sliding door and those of the rear doors;
  # passenger has the windows all around.
  defp preset_list(_m, "cargo"), do: []

  defp preset_list(m, "crew") do
    [seam | _] = m["make_data"]["windows"]["side"]["seams"]
    [%{"at" => "left", "to" => seam}, %{"at" => "slider"}, %{"at" => "rear_doors"}]
  end

  defp preset_list(_m, "passenger"), do: for(at <- @places, do: %{"at" => at})

  defp window_defaults(m, at) do
    w = m["make_data"]["windows"]
    o = m["make_data"]["openings"]
    [z0, z1] = w["side"]["z"]
    qe = m["quarter_end"] / 1

    case at do
      "left" ->
        %{"from" => w["side"]["from"], "to" => qe, "bottom" => z0, "top" => z1}

      "right" ->
        %{
          "from" => max(hd(w["side"]["seams"]), o["sliding_door"]["to"] + 0.03),
          "to" => qe,
          "bottom" => z0,
          "top" => z1
        }

      "slider" ->
        %{"from" => w["slider"]["from"], "to" => o["sliding_door"]["to"] - 0.03, "bottom" => z0, "top" => z1}

      "rear_doors" ->
        %{"bottom" => hd(w["rear_doors"]["z"]), "top" => List.last(w["rear_doors"]["z"])}
    end
    |> Map.new(fn {k, v} -> {k, v / 1} end)
  end

  @doc """
  The limits of the numbers of a window at a place: `{min, max}` of
  `from`, `to`, `bottom` and `top`. A window is in the side behind the
  front door (left) or the sliding door (right), up to the end of the
  quarter of the model; in the sliding door; or in the rear doors, under
  the top of their opening.
  """
  def window_limits(m, at) do
    o = m["make_data"]["openings"]
    qe = m["quarter_end"] / 1
    {fb, s0, s1} = {Enum.max(for [x, _] <- o["front_door"], do: x), o["sliding_door"]["from"], o["sliding_door"]["to"]}
    side = %{"bottom" => {0.9, m["height"] - 0.45}, "top" => {1.1, m["height"] - 0.25}}

    case at do
      "left" ->
        Map.merge(side, %{"from" => {fb + 0.1, qe - 0.3}, "to" => {fb + 0.4, qe}})

      "right" ->
        Map.merge(side, %{"from" => {s1 + 0.03, qe - 0.3}, "to" => {s1 + 0.33, qe}})

      "slider" ->
        Map.merge(side, %{
          "from" => {s0 + 0.05, s1 - 0.33},
          "to" => {s0 + 0.35, s1 - 0.03},
          "top" => {1.1, List.last(o["sliding_door"]["z"]) - 0.1}
        })

      "rear_doors" ->
        %{
          "bottom" => {o["rear_doors"]["bottom"] + 0.2, m["floor"] + m["rear_door"] - 0.25},
          "top" => {o["rear_doors"]["bottom"] + 0.4, m["floor"] + m["rear_door"] - 0.05}
        }
    end
  end

  # --- The seats --------------------------------------------------------------------------

  @doc """
  The rows of seats behind the front seats: the rows of the make that go
  in the body (a seat is 0.5 m deep behind the center of its cushion, and
  the rear doors are 0.1 m thick), as many as the order asks.
  """
  def rows(m, windows, count) do
    l = m["length"] / 1
    fit = Enum.filter(m["make_data"]["seats"]["rows"], &(m["front"] + &1["d"] + 0.5 <= l - 0.1))
    count = count || default_rows(windows, length(fit))
    Enum.take(fit, count)
  end

  @doc "The most rows of seats that go in the body of a model."
  def room(m), do: length(rows(m, [], 99))

  defp default_rows(w, _) when w in [:crew, "crew"], do: 1
  defp default_rows(w, n) when w in [:passenger, "passenger"], do: n
  defp default_rows(_, _), do: 0

  # --- The check --------------------------------------------------------------------------

  @doc """
  The errors of the doors, the windows and the rows of an order of a
  model (`m` with the sizes of the order): a number out of its limits,
  two windows at one place, a window shorter than 0.3 m or lower than
  0.2 m, more rows than the body has room for. Each error is `{path,
  message}`.
  """
  def check(m, doors, windows, rows) do
    limits = door_limits(m, merged(m, doors))

    door_errors =
      for {k, v} <- Enum.sort(doors || %{}),
          v != nil,
          {f, x} <- Enum.sort(v),
          x != nil,
          {a, b} = limits[k][f],
          x < a - 1.0e-9 or x > b + 1.0e-9,
          do: {"options.doors.#{k}.#{f}", out(a, b)}

    m = put_doors(m, doors)
    window_errors = if is_list(windows), do: window_errors(m, windows), else: []
    room = room(m)

    row_errors =
      if rows != nil and rows > room,
        do: [{"options.rows", "must be at most #{room}: the rows that go in the body"}],
        else: []

    door_errors ++ window_errors ++ row_errors
  end

  defp window_errors(m, list) do
    twice =
      for {w, i} <- Enum.with_index(list),
          Enum.count(Enum.take(list, i), &(&1["at"] == w["at"])) > 0,
          do: {"options.windows.#{i}", "must be at another place: one window at #{w["at"]}"}

    numbers =
      for {w, i} <- Enum.with_index(list),
          limits = window_limits(m, w["at"]),
          {f, x} <- Enum.sort(w),
          f != "at",
          x != nil,
          Map.has_key?(limits, f),
          {a, b} = limits[f],
          x < a - 1.0e-9 or x > b + 1.0e-9,
          do: {"options.windows.#{i}.#{f}", out(a, b)}

    spans =
      for {w, i} <- Enum.with_index(windows(m, list)),
          message <- [
            if(w["at"] != "rear_doors" and w["to"] - w["from"] < 0.3, do: "must be 0.3 m long or more"),
            if(w["top"] - w["bottom"] < 0.2, do: "must be 0.2 m high or more")
          ],
          message != nil,
          do: {"options.windows.#{i}", message}

    twice ++ numbers ++ spans
  end

  # The numbers of the doors of an order over those of the model.
  defp merged(m, given) do
    d = doors(m)

    Map.new(d, fn {k, v} ->
      {k, Map.merge(v, for({f, x} <- (given || %{})[k] || %{}, x != nil, into: %{}, do: {f, x / 1}))}
    end)
  end

  defp out(a, b), do: "must be from #{Float.round(a, 3)} to #{Float.round(b, 3)} m for this van"

  defp clamp(x, {a, b}), do: x |> max(a) |> min(b)
  defp cap({a, b}, c), do: {a, min(b, c)}
  defp floor_at({a, b}, c), do: {max(a, c), b}
end
