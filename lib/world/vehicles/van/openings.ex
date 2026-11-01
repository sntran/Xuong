defmodule World.Vehicles.Van.Openings do
  @moduledoc """
  The openings of the body of a van (`openings` of its make in
  `priv/data/vans.json`): where the body shop cuts the sheets, where the
  doors close, where the glass goes.

  An opening at a distance `d` from the front is a list of lines
  (`World.Vehicles.Hull.clip/2`) at the right side of the van, or nil where
  the opening is not. With a `gap`, the opening is that much smaller at
  each edge: a door in its opening, with a gap around it.
  """
  alias World.Vehicles.Hull

  # A side of the van is the sheet out from this line: a door or a window
  # cuts the side, not the floor or the roof.
  @side 0.25

  @doc "The windshield, from its base at the cowl to its top."
  def windshield(van, d) do
    w = van.make["openings"]["windshield"]

    if d >= w["base"] and d <= windshield_top(van),
      do: [{:x_max, Hull.half_width(van.h, d) - w["inset"]}, {:z_min, Hull.z_high(van.h, d) - 0.3}]
  end

  @doc "The `d` of the top of the windshield."
  def windshield_top(van) do
    top = van.make["openings"]["windshield"]["top"]
    Enum.find(Hull.stations(van.h, 0.81, 2.4, 0.01), &(Hull.z_high(van.h, &1) >= top))
  end

  @doc "The opening of a front door: its outline in the side (x from the front axle, and z)."
  def front_door(van, d, gap \\ 0.0) do
    case span(outline(van), d, gap) do
      nil -> nil
      {a, b} -> [{:x_min, Hull.half_width(van.h, d) - @side}, {:z_min, a + gap}, {:z_max, b - gap}]
    end
  end

  @doc "The first and the last `d` of a front door."
  def front_door_span(van) do
    ds = Enum.map(outline(van), &elem(&1, 0))
    {Enum.min(ds), Enum.max(ds)}
  end

  defp outline(van), do: for([x, z] <- van.make["openings"]["front_door"], do: {van.f + x, z / 1})

  @doc """
  The opening of the sliding door at the right side. Its top stays under
  the round edge of the roof, also for a van that an order makes lower.
  """
  def sliding_door(van, d, gap \\ 0.0) do
    {s0, s1} = sliding_door_span(van)
    [z0, z1] = van.make["openings"]["sliding_door"]["z"]
    z1 = min(z1, Hull.z_high(van.h, d) - van.h.edge - 0.01)

    if d >= s0 + gap and d <= s1 - gap,
      do: [{:x_min, Hull.half_width(van.h, d) - @side}, {:z_min, z0 + gap}, {:z_max, z1 - gap}]
  end

  @doc "The first and the last `d` of the sliding door."
  def sliding_door_span(van) do
    o = van.make["openings"]["sliding_door"]
    {van.f + o["from"], van.f + o["to"]}
  end

  @doc """
  The opening of the rear doors: from the center to the lamps at the
  back, from over the bumper to over the opening of the model. The back
  of the body is in its last 0.35 m.
  """
  def rear_doors(van, d, gap \\ 0.0) do
    {r0, hw, z0, z1} = rear(van)
    if d >= r0, do: [{:x_min, gap}, {:x_max, hw - gap}, {:z_min, z0 + gap}, {:z_max, z1 - gap}]
  end

  @doc "The rear doors: `{d where the back starts, half width, bottom, top}`."
  def rear(van) do
    o = van.make["openings"]["rear_doors"]
    {_, d1} = Hull.span(van.h)

    {van.l - 0.35, Hull.half_width(van.h, d1 - 0.01) - o["lamp"], o["bottom"] / 1,
     (van.m["floor"] + van.m["rear_door"] + o["over"]) / 1}
  end

  @doc "The window of the order at a place (`left`, `right`, `slider`, `rear_doors`), or nil."
  def window(van, at), do: Enum.find(van.glass, &(&1["at"] == at))

  @doc """
  The window of a rear door (the window `rear_doors` of the order): from
  the middle to its outer edge, with its outer corners cut on the line
  that touches their round corners.
  """
  def rear_window(van, d) do
    case window(van, "rear_doors") do
      nil -> nil
      g -> rear_window(van, d, g)
    end
  end

  defp rear_window(van, d, g) do
    {r0, _, _, _} = rear(van)
    w = van.make["windows"]["rear_doors"]
    {xo, [z0, z1]} = {w["x"] / 1, [g["bottom"], g["top"]]}
    cut = fn r -> r * (2 - :math.sqrt(2)) end

    if d >= r0,
      do: [
        {:x_min, 0.012},
        {:x_max, xo},
        {:z_min, z0},
        {:z_max, z1},
        {:le, 1.0, -1.0, xo - z0 - cut.(w["outer_bottom"])},
        {:le, 1.0, 1.0, xo + z1 - cut.(w["outer_top"])}
      ]
  end

  @doc """
  A window in the side, from `d0` to `d1`, with its round corners: `ft`,
  `fb` (at the front, the top and the bottom), `bt`, `bb` (at the back),
  and its bottom and top (`z`).
  """
  def side_window(van, d, d0, d1, corners) do
    [z0, z1] = Map.get(corners, :z, van.make["windows"]["side"]["z"])

    if d >= d0 and d <= d1 do
      {lo, hi} = edges(d - d0, d1 - d, z0, z1, corners)
      [{:x_min, Hull.half_width(van.h, d) - @side}, {:z_min, lo}, {:z_max, hi}]
    end
  end

  defp edges(f, b, z0, z1, c) do
    round = fn r, u -> if u < r, do: r - :math.sqrt(max(r * r - (r - u) * (r - u), 0.0)), else: 0.0 end
    get = &Map.get(c, &1, 0.0)
    {z0 + max(round.(get.(:fb), f), round.(get.(:bb), b)), z1 - max(round.(get.(:ft), f), round.(get.(:bt), b))}
  end

  @doc """
  The windows in the body behind the cab, at a side (1 the right, -1 the
  left): `{d0, d1, corners}`, from the windows `right` and `left` of the
  order. The window at the left has the round corner of the make at the
  front top; a window to the end of the quarter, those at the back.
  """
  def side_windows(van, s) do
    w = van.make["windows"]["side"]
    qe = van.m["quarter_end"]

    case window(van, if(s == 1, do: "right", else: "left")) do
      nil ->
        []

      g ->
        back = if g["to"] >= qe - 0.01, do: %{bt: w["back_top"], bb: w["back_bottom"]}, else: %{}
        front = if s == -1, do: %{ft: w["front_top"]}, else: %{}
        [{van.f + g["from"], van.f + g["to"], Map.merge(back, front) |> Map.put(:z, [g["bottom"], g["top"]])}]
    end
  end

  @doc "The window of the sliding door (the window `slider` of the order): `{d0, d1, corners}`, or nil."
  def slider_window(van) do
    case window(van, "slider") do
      nil ->
        nil

      g ->
        {van.f + g["from"], van.f + g["to"],
         %{ft: van.make["windows"]["slider"]["front_top"], z: [g["bottom"], g["top"]]}}
    end
  end

  # The window of the front door of the Transit (`door_window/2`): the
  # belt at 1.21 m at 1 m from the front, 0.19 m higher each 1.24 m to
  # the back, and the top at 1.98 m.
  @door_window %{"belt" => 1.21, "rise" => 0.19, "run" => 1.24, "top" => 1.98}

  @doc """
  The window of a front door: from the belt (at `belt` 1 m from the
  front, `rise` higher each `run` to the back) to its top (`top`, under
  the edge of the roof). The numbers are `door_window` of the openings
  of the make, those of the Transit by default.
  """
  def door_window(van, d) do
    {d0, d1} = front_door_span(van)
    w = Map.get(van.make["openings"], "door_window", @door_window)

    with true <- d >= d0 + 0.04 and d <= d1 - 0.06,
         {_, b} <- span(outline(van), d, 0.0),
         belt = w["belt"] + w["rise"] * (d - 1.0) / w["run"],
         top = Enum.min([w["top"], Hull.z_high(van.h, d) - 0.09, b - 0.05]),
         true <- top > belt + 0.02 do
      [{:x_min, Hull.half_width(van.h, d) - @side}, {:z_min, belt}, {:z_max, top}]
    else
      _ -> nil
    end
  end

  @doc "The holes of the body at a side (1 the right, -1 the left): a function of `d`."
  def body_holes(van, s) do
    windows = side_windows(van, s)

    fn d ->
      [
        windshield(van, d),
        front_door(van, d),
        if(s == 1, do: sliding_door(van, d)),
        rear_doors(van, d)
        | for({d0, d1, c} <- windows, do: side_window(van, d, d0, d1, c))
      ]
      |> Enum.reject(&is_nil/1)
    end
  end

  @doc "The `d` where an opening starts or ends."
  def edges(van) do
    {f0, f1} = front_door_span(van)
    {s0, s1} = sliding_door_span(van)
    {r0, _, _, _} = rear(van)
    w = van.make["openings"]["windshield"]
    windows = for s <- [1, -1], {d0, d1, _} <- side_windows(van, s), d <- [d0, d1], do: d
    [w["base"], windshield_top(van), f0, f1, s0, s1, r0 | windows]
  end

  # The z from the bottom to the top of a convex outline at `d`, in from
  # its front and its back by `gap`.
  defp span(outline, d, gap) do
    {d0, d1} = outline |> Enum.map(&elem(&1, 0)) |> Enum.min_max()

    if d >= d0 + gap and d <= d1 - gap do
      zs =
        for [{a, za}, {b, zb}] <- Enum.chunk_every(outline ++ [hd(outline)], 2, 1, :discard),
            a != b,
            d >= min(a, b) and d <= max(a, b),
            do: za + (zb - za) * (d - a) / (b - a)

      {Enum.min(zs), Enum.max(zs)}
    end
  end
end
