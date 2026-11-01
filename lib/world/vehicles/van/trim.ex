defmodule World.Vehicles.Van.Trim do
  @moduledoc """
  The fourth station of the line of a van (`World.Vehicles.Van`), after
  the paint: the glass in the openings of the body, the black plastic,
  the lamps, the grille, the small parts, and inside the dash and the
  seats.

  At the near level the glass is in its opening, flush with the body;
  at the mid and far levels it is on the closed body, and at the far
  level the glass of the doors is here too (the doors have no mesh).
  """
  alias World.{Assembly, Detail, Frame, Shape}
  alias World.Furniture.Seats
  alias World.Vehicles.Hull
  alias World.Vehicles.Van.{Kit, Openings}

  @station "trim"

  @doc "The van with its trim."
  def fit(asm, van) do
    asm
    |> Assembly.add("trim", plastic(van), at: "origin", port: "origin")
    |> Assembly.add("glass", glass(van), at: "origin", port: "origin")
    |> Assembly.add("lamps", lamps(van), at: "origin", port: "origin")
    |> Assembly.add("grille", grille(van), at: "origin", port: "origin")
    |> near(van)
  end

  defp near(asm, van) do
    if Detail.level() == :near do
      asm
      |> Assembly.add("details", small_parts(van), at: "origin", port: "origin")
      |> Assembly.add("cab", cab(van), at: "origin", port: "origin")
      |> seats(van)
    else
      asm
    end
  end

  # --- The glass --------------------------------------------------------------------------

  # The windshield, and the windows of the body behind the cab. At the far
  # level, also the windows of the doors.
  defp glass(van) do
    shapes =
      case Detail.level() do
        :near -> flush(van)
        level -> on_body(van, level)
      end

    Kit.part(@station, "glass_transit", :glass, shapes, [Kit.origin()],
      sources: if(van.windows == :cargo, do: [], else: van.make["windows"]["sources"])
    )
  end

  defp flush(van) do
    %{h: h} = van
    w = van.make["openings"]["windshield"]

    windshield =
      for s <- [1, -1] do
        Hull.shell(h, w["base"], Openings.windshield_top(van), :glass_dark,
          side: s,
          thickness: 0.008,
          offset: -0.004,
          step: 0.05,
          clip: fn d -> Openings.windshield(van, d) || [{:z_min, 9.0}] end
        )
      end

    windows =
      for s <- [1, -1], {d0, d1, c} <- Openings.side_windows(van, s) do
        Hull.shell(h, d0, d1, :glass_dark,
          side: s,
          thickness: 0.008,
          offset: -0.004,
          step: 0.05,
          clip: fn d -> Openings.side_window(van, d, d0, d1, c) || [{:z_min, 9.0}] end
        )
      end

    List.flatten(windshield ++ windows)
  end

  defp on_body(van, level) do
    %{h: h} = van
    w = van.make["openings"]["windshield"]
    step = %{mid: 0.1, far: 0.3}[level]

    windshield =
      Hull.skin(h, w["base"], Openings.windshield_top(van), :glass_dark,
        offset: %{mid: 0.01, far: 0.025}[level],
        sides: 16,
        step: 0.05,
        clip: fn d ->
          inset = Hull.half_width(h, d) - w["inset"]
          [{:z_min, Hull.z_high(h, d) - 0.04}, {:x_max, inset}, {:x_min, -inset}]
        end
      )

    region = fn d0, d1, planes, s ->
      Hull.skin(h, d0, d1, :glass_dark,
        offset: 0.006,
        sides: 8,
        step: step,
        clip: fn d -> Kit.mirror(planes.(d) || [{:z_min, 9.0}], s) end
      )
    end

    windows =
      for s <- [1, -1],
          {d0, d1, c} <- Openings.side_windows(van, s),
          do: region.(d0, d1, &Openings.side_window(van, &1, d0, d1, c), s)

    doors =
      if level == :far do
        {d0, d1} = Openings.front_door_span(van)
        cab = for s <- [1, -1], do: region.(d0, d1, &Openings.door_window(van, &1), s)

        slider =
          case Openings.slider_window(van) do
            nil -> []
            {w0, w1, c} -> [region.(w0, w1, &Openings.side_window(van, &1, w0, w1, c), 1)]
          end

        cab ++ slider ++ rear_glass(van)
      else
        []
      end

    [windshield | windows ++ doors]
  end

  # The glass of the rear doors on the closed body (the far level).
  defp rear_glass(%{windows: :cargo}), do: []

  defp rear_glass(van) do
    %{h: h} = van
    {r0, _, _, _} = Openings.rear(van)
    {_, d1} = Hull.span(h)

    for s <- [1, -1] do
      Hull.shell(h, r0, d1, :glass_dark,
        side: s,
        thickness: 0.008,
        offset: 0.008,
        step: 0.1,
        clip: &Openings.rear_window(van, &1)
      )
    end
    |> List.flatten()
  end

  # --- The black plastic ------------------------------------------------------------------

  # The bumpers, the band and the edge between the wheels, the flares
  # over the wheels, the strip at the base of the windshield. The doors
  # have their part of the band.
  defp plastic(van) do
    %{h: h, m: m, l: l, f: f} = van
    {d0, d1} = Hull.span(h)
    wb = m["wheelbase"]
    [{_, az, af}, {_, _, ar}] = h.arches
    {_, door1} = Openings.front_door_span(van)
    {s0, s1} = Openings.sliding_door_span(van)

    bumper_f =
      Hull.skin(h, d0 - 0.018, 0.56, :trim,
        offset: 0.018,
        sides: 20,
        step: 0.06,
        clip: fn d -> [{:z_max, 0.67 + 0.09 * min(1.0, (d - d0) / 0.25)}] end
      )

    bumper_r =
      Hull.skin(h, l - 0.34, d1 + 0.018, :trim,
        offset: 0.018,
        sides: 28,
        step: 0.06,
        clip: fn _ -> [{:z_max, 0.7}] end
      )

    # The band on the body: behind the front doors, and at the right side
    # not on the sliding door. The edge under 0.41 m: from wheel to wheel.
    band = fn s, d0, d1, z0, z1 ->
      Hull.skin(h, d0, d1, :trim,
        offset: 0.006,
        sides: if(Detail.level() == :near, do: 12, else: 8),
        step: 0.1,
        clip: fn d -> Kit.mirror([{:x_min, Hull.half_width(h, d) - 0.06}, {:z_min, z0}, {:z_max, z1}], s) end
      )
    end

    back = f + wb - ar + 0.02
    [b0, b1] = band(van)

    bands = [
      band.(-1, door1, back, b0, b1),
      band.(1, s1, back, b0, b1),
      band.(1, door1, s0, b0, b1),
      band.(1, f + af - 0.02, back, 0.0, 0.41),
      band.(-1, f + af - 0.02, back, 0.0, 0.41)
    ]

    flares =
      for {d, r} <- [{f, af}, {f + wb, ar}], s <- [1, -1] do
        hw = Hull.half_width(h, d)
        n = if Detail.level() == :near, do: 14, else: 6

        line =
          for i <- 0..n do
            a = (-78 + 156 * i / n) * :math.pi() / 180
            {s * (hw - 0.01), l - d + (r + 0.015) * :math.sin(a), az + (r + 0.015) * :math.cos(a)}
          end

        Shape.sweep(line, 0.03, :trim, sides: if(n == 14, do: 6, else: 4))
      end

    cowl =
      Hull.skin(h, 0.634, van.make["openings"]["windshield"]["base"], :trim,
        offset: 0.004,
        sides: 16,
        step: 0.05,
        clip: fn d -> [{:z_min, Hull.z_high(h, d) - 0.03}] end
      )

    # From far, only the bumpers show; from mid, not the strip at the
    # windshield.
    shapes =
      case Detail.level() do
        :far -> [bumper_f, bumper_r]
        :mid -> [bumper_f, bumper_r | bands ++ flares]
        :near -> [bumper_f, bumper_r, cowl | bands ++ flares]
      end

    Kit.part(@station, "trim_" <> m["make"], :trim, shapes, [Kit.origin()],
      sources: [
        "The black plastic of the Transit, from the photos of dealers: the front bumper from 0.29 to 0.76 m, the back bumper to 0.7 m and the lamps at the back from 0.7 to 1.355 m (the passenger van from the back: https://www.comvoy.com/work-van/starke-fl/new-2026-ford-transit-350-xl-passenger-van-23229223), the band from 0.5 to 0.78 m and the edge under 0.41 m between the wheels."
      ]
    )
  end

  @doc """
  The black band on the sides and the doors: `[bottom, top]` in meters,
  `trim.band` of the make, or 0.5 to 0.78 m (the Transit).
  """
  def band(van), do: get_in(van.make, ["trim", "band"]) || [0.5, 0.78]

  # --- The lamps --------------------------------------------------------------------------

  # The headlamps, the lamps at the back, the third stop lamp.
  defp lamps(%{h: h}) do
    {_, d1} = Hull.span(h)
    l = h.length

    # A headlamp: from the top corner of the grille (x = 0.6) back along
    # the fender to its amber tip at d = 0.7, from 0.93 to 1.22 m at the
    # front, and to 1.2 m at the tip.
    lamp = fn d0, d1, material, extra ->
      Kit.sides(
        h,
        d0,
        d1,
        material,
        fn d ->
          t = max(d - 0.1, 0.0) / 0.6
          [{:x_min, 0.6}, {:z_min, 0.93 + 0.27 * t}, {:z_max, 1.22 + 0.02 * t}]
        end,
        offset: 0.008 + extra,
        sides: 16,
        step: 0.05
      )
    end

    reflector =
      Kit.sides(
        h,
        0.02,
        0.5,
        :chrome,
        fn d ->
          t = max(d - 0.1, 0.0) / 0.6
          [{:x_min, 0.66}, {:z_min, 0.97 + 0.27 * t}, {:z_max, 1.18 + 0.02 * t}]
        end,
        offset: 0.011,
        sides: 16,
        step: 0.05
      )

    # A lamp at the back: on the corner pillar, from x = 0.09 m inside
    # the side, around the corner and 0.06 m along the side.
    hw = Hull.half_width(h, d1 - 0.01)

    # Its parts, from the photos: red at the bottom, the clear lamp of
    # the reverse in the middle, red at the top.
    {parts, ts} =
      if Detail.level() == :far,
        do: {[{[0.7, 0.803, 1.16, 1.355], :light_back}], [0.0, 1.0]},
        else:
          {[
             {[0.7, 0.803, 0.87], :light_back},
             {[0.87, 0.95, 1.05, 1.13], :light_front},
             {[1.13, 1.16, 1.26, 1.355], :light_back}
           ], [0.0, 0.25, 0.5, 0.75, 1.0]}

    back_lamp = fn s, zs, material ->
      for z <- zs do
        u = Hull.back(h, z)
        side = for t <- ts, do: {Hull.half_width(h, l - u - 0.06 * t) + 0.012, u - 0.015 + 0.075 * t}
        {xi, yi} = List.last(side)
        for {x, y} <- [{hw - 0.09, u - 0.015} | side] ++ [{xi - 0.05, yi}, {hw - 0.09, u + 0.03}], do: {s * x, y, z}
      end
      |> Shape.rings(material)
    end

    back = for s <- [1, -1], {zs, material} <- parts, do: back_lamp.(s, zs, material)

    # The third stop lamp: a black housing on the back edge of the roof,
    # 0.74 m wide, with a red lens of 0.4 m at its top (the photos of the
    # back of the van).
    stop = stop_lamp(h)

    Kit.part(
      @station,
      "lamps_transit",
      :light,
      case Detail.level() do
        :far -> lamp.(0.02, 0.7, :black, 0.0) ++ back ++ stop
        :mid -> lamp.(0.02, 0.7, :black, 0.0) ++ lamp.(0.56, 0.7, :orange, 0.002) ++ back ++ stop
        :near -> lamp.(0.02, 0.7, :black, 0.0) ++ reflector ++ lamp.(0.56, 0.7, :orange, 0.002) ++ back ++ stop
      end,
      [Kit.origin()],
      detail: :always
    )
  end

  # The housing and the lens of the third stop lamp. Its profile (y, z)
  # goes from the back face, under the edge of the roof, up over the
  # back of the roof; the two ends are at x = -0.37 and 0.37.
  defp stop_lamp(h) do
    top = h.top
    low = top - 0.09
    {ub, ut} = {Hull.back(h, low), Hull.back(h, top)}
    face = fn t -> {ub - 0.015 + (ut - 0.03 - ub + 0.015) * t, low + (top + 0.02 - low) * t} end
    {y0, z0} = face.(0.0)
    {y1, z1} = face.(1.0)
    housing = [{y0, z0}, {y1, z1}, {ut + 0.25, top + 0.02}, {ut + 0.25, top - 0.01}, {y0 + 0.06, z0}]

    {ya, za} = face.(0.55)
    {yb, zb} = face.(0.95)
    lens = [{ya - 0.005, za}, {yb - 0.005, zb}, {yb + 0.01, zb}, {ya + 0.01, za}]

    for {profile, w, material} <- [{housing, 0.37, :black}, {lens, 0.2, :light_back}] do
      Shape.rings(for(x <- [-w, w], do: for({y, z} <- profile, do: {x, y, z})), material)
    end
  end

  # --- The grille -------------------------------------------------------------------------

  # The grille (a hexagon) with the oval.
  defp grille(%{h: h}) do
    l = h.length

    grille =
      Hull.skin(h, -0.012, 0.2, :black,
        offset: 0.012,
        sides: 16,
        step: 0.02,
        clip: fn _ ->
          k = 0.125 / 0.49
          [{:z_min, 0.665}, {:z_max, 1.15}, {:le, 1.0, -k, 0.475 - 0.66 * k}, {:le, -1.0, -k, 0.475 - 0.66 * k}]
        end
      )

    oval = fn y, z, w, hh, material, depth ->
      Shape.loft(
        [
          {{0.0, y, z}, {1.0, 0.0, 0.0}, {0.0, 0.0, 1.0}, w, hh, 2.0},
          {{0.0, y + depth, z}, {1.0, 0.0, 0.0}, {0.0, 0.0, 1.0}, w, hh, 2.0}
        ],
        material,
        sides: 20
      )
    end

    yf = l - 0.098

    Kit.part(
      @station,
      "grille_transit",
      :trim,
      [grille, oval.(yf, 0.98, 0.165, 0.065, :chrome, 0.03), oval.(yf + 0.006, 0.98, 0.15, 0.055, :blue, 0.03)],
      [Kit.origin()],
      detail: :always,
      sources: [
        "The grille: a hexagon 1.2 m wide at its top and 0.95 m at its bottom, from 0.66 to 1.15 m, with the oval in its upper middle (the photos of dealers)."
      ]
    )
  end

  # --- The small parts --------------------------------------------------------------------

  # The small parts, only in the near level: the plates, the pockets of
  # the fog lamps, the vents of the hood, the rail of the sliding door,
  # the hinges of the rear doors.
  defp small_parts(van) do
    %{h: h, l: l} = van
    {d0, d1} = Hull.span(h)

    plates = [
      Shape.box({-0.155, l - d0 - 0.035, 0.45}, {0.155, l - d0 - 0.02, 0.6}, :white),
      Shape.box({-0.155, -0.03, 0.56}, {0.155, -0.022, 0.715}, :white)
    ]

    pockets =
      Kit.sides(h, 0.08, 0.32, :black, fn _ -> [{:x_min, 0.56}, {:z_min, 0.4}, {:z_max, 0.5}] end,
        offset: 0.024,
        sides: 8,
        step: 0.04
      )

    vents =
      for s <- [1, -1] do
        Hull.skin(h, 0.52, 0.575, :black,
          offset: 0.009,
          sides: 8,
          step: 0.02,
          clip: fn d -> Kit.mirror([{:z_min, Hull.z_high(h, d) - 0.012}, {:x_min, 0.12}, {:x_max, 0.44}], s) end
        )
      end

    {_, s1} = Openings.sliding_door_span(van)

    rail =
      Hull.skin(h, s1 + 0.03, l - 0.36, :dark,
        offset: 0.008,
        sides: 8,
        step: 0.1,
        clip: fn d -> [{:x_min, Hull.half_width(h, d) - 0.04}, {:z_min, 1.43}, {:z_max, 1.47}] end
      )

    hinges =
      for s <- [1, -1], z <- [0.6, 1.99] do
        x = s * (Hull.half_width(h, d1 - 0.02) - 0.05)
        u = Hull.back(h, z)
        Shape.box({x - 0.035, u - 0.016, z}, {x + 0.035, u + 0.03, z + 0.09}, :black)
      end

    Kit.part(@station, "details_transit", :trim, [rail | plates ++ pockets ++ vents ++ hinges], [Kit.origin()],
      sources: ["The vents of the hood and the rail of the sliding door at 1.45 m: from the photos of dealers."]
    )
  end

  # --- The cab ----------------------------------------------------------------------------

  # The dash and the steering wheel at the left. The seats are
  # `World.Furniture.Seats` on the mounting points of the floors
  # (`World.Vehicles.Van.BodyShop.mounts/1`).
  defp cab(van) do
    %{h: h, l: l, f: f} = van
    y = fn d -> l - d end
    hw = Hull.half_width(h, f + 0.5) - 0.05

    dash = Shape.box({-hw, y.(f + 0.35), 0.95}, {hw, y.(f - 0.15), 1.3}, :dark, round: 0.3, smooth: 1)

    rim =
      for i <- 0..16, a = 2 * :math.pi() * i / 16 do
        {-0.45 + 0.19 * :math.cos(a), y.(f + 0.5) + 0.06 * :math.sin(a), 1.32 + 0.17 * :math.sin(a)}
      end

    wheel = Shape.sweep(rim, 0.016, :black, sides: 6)

    column =
      Shape.cylinder(0.03, 0.3, :black,
        sides: 8,
        frame: Frame.new({-0.45, y.(f + 0.2), 1.2}, {0, -0.6, 0.35}, {0, 0, 1})
      )

    Kit.part(@station, "cab_transit", :dash, [dash, wheel, column], [Kit.origin()],
      detail: :near,
      sources: [
        "The dash and the steering wheel: by eye from the photos of the inside of a 2026 Transit passenger van (https://www.comvoy.com/work-van/fenton-mi/new-2026-ford-transit-350-xl-passenger-van-25226733)."
      ]
    )
  end

  # The two front seats on their tracks, and the rows of the crew van (the
  # first row) and of the passenger van (all the rows of the make).
  defp seats(asm, van) do
    %{"front" => front, "rows" => rows, "sources" => sources} = van.make["seats"]

    rows =
      case van.windows do
        :cargo -> []
        :crew -> Enum.take(rows, 1)
        :passenger -> rows
      end

    opts = fn data -> [place_width: data["place_width"], sources: sources] end

    fronts =
      for name <- ["driver", "passenger"] do
        seat =
          Seats.seat(
            name,
            opts.(front) ++ [height: front["height"], track: front["track"], recline: front["recline"]]
          )

        {name, seat, "seat_" <> name}
      end

    benches =
      for {row, i} <- Enum.with_index(rows, 2),
          do: {"row_#{i}", Seats.bench("row_#{i}", row["places"], opts.(row)), "row_#{i}"}

    Enum.reduce(fronts ++ benches, asm, fn {name, seat, mount}, asm ->
      Assembly.add(asm, name, Kit.station(seat, @station), to: "inside", at: mount, port: "floor")
    end)
  end
end
