defmodule World.Buildings do
  @moduledoc """
  Houses from their materials, as a builder makes them:

  - a wall of masonry (bricks or concrete blocks) in running bond, with
    its joints of mortar, its openings, a lintel over each opening, and a
    gable;
  - a wall of wood studs (2x4 at 16 in), with a king stud, a jack stud
    and a header at each opening, a sill and cripples under a window, OSB
    sheathing and lap siding;
  - a gable roof of rafters (2x6 at 24 in) and a ridge board, with OSB
    and clay tiles or metal panels;
  - doors and windows that open.

  At near each brick, stud and tile is a part: the list of the parts
  counts what a builder buys. At mid and far a solid wall and a solid roof
  stand in for them (`detail: :low`).

  The axes of a wall: along x from 0 to its length, its outside face at
  y = 0 and its inside face at y = its thickness, z up. An opening is
  `{kind, x, width, z, height}` in the axes of its wall (the rough
  opening), with the kind `:door`, `:window` or `:hole`.
  """
  alias World.{Assembly, Frame, Kit, Part, Shape, Vec}
  alias World.Materials.{Construction, Stock}
  import Kit, only: [inch: 1, same: 4]

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  # The opts to put an item with its x along `x` and its z along `z`.
  defp at(name, p, x, z), do: [at: Part.port(name, p, z, Vec.cross(z, x)), port: @o]

  defp mark(name), do: Part.new(name, :mark, [], [@o])

  # --- The intervals of a wall --------------------------------------------------

  # The free parts of [a, b] after the cut of the intervals in `cuts`.
  defp free(a, b, cuts) do
    cuts
    |> Enum.sort()
    |> Enum.reduce([{a, b}], fn {c0, c1}, segs ->
      Enum.flat_map(segs, fn {s0, s1} ->
        Enum.filter([{s0, min(s1, c0)}, {max(s0, c1), s1}], fn {u, v} -> v - u > 1.0e-6 end)
      end)
    end)
  end

  # The cuts of the openings (and their lintels) in a band of z.
  defp cuts(holes, z0, z1), do: for({x0, x1, h0, h1} <- holes, h0 < z1 - 1.0e-6 and h1 > z0 + 1.0e-6, do: {x0, x1})

  # Solid boxes of a wall with holes: one band for each pair of heights.
  defp solid(length, z_top, holes, {y0, y1}, material) do
    breaks =
      ([0.0, z_top] ++ Enum.flat_map(holes, fn {_, _, h0, h1} -> [h0, h1] end))
      |> Enum.filter(&(&1 >= 0 and &1 <= z_top))
      |> Enum.uniq()
      |> Enum.sort()

    for [z0, z1] <- Enum.chunk_every(breaks, 2, 1, :discard), {a, b} <- free(0.0, length, cuts(holes, z0, z1)) do
      Shape.box({a, y0, z0}, {b, y1, z1}, material)
    end
  end

  # --- A wall of masonry ----------------------------------------------------------

  @doc """
  A wall of masonry: `unit` is a name of `World.Materials.Construction.units/0`.
  The options: `wythes` (1 or 2), `openings`, and `gable` (the rise of a
  gable over the top of the wall, centered on the wall).
  """
  def masonry_wall(name, unit, length, height, opts \\ []) do
    u = Construction.unit(unit)
    {pl, ph} = {u.l + u.joint, u.h + u.joint}
    wythes = Keyword.get(opts, :wythes, 1)
    thick = wythes * u.w + (wythes - 1) * u.joint
    openings = Keyword.get(opts, :openings, [])
    rise = Keyword.get(opts, :gable, 0.0)
    courses = round(height / ph)
    z_top = courses * ph

    # Each opening and its lintel: the lintel is 150 mm longer at each end
    # and two courses high, on the course over the opening.
    lintels =
      for {_, x, w, z, h} <- openings do
        zl = Float.ceil((z + h) / ph) * ph
        {max(x - 0.15, 0.0), min(x + w + 0.15, length), zl, zl + 2 * ph}
      end

    holes = for({_, x, w, z, h} <- openings, do: {x, x + w, z, z + h}) ++ lintels

    gable_courses = round(rise / ph)

    units =
      for k <- 0..(courses + gable_courses - 1),
          z = k * ph,
          # The span of the course: the whole wall, or a part of the gable.
          {s0, s1} = span(length, z + ph, z_top, rise),
          s1 - s0 > 0.04,
          {a, b} <- free(s0, s1, Enum.map(cuts(holes, z, z + ph), fn {c0, c1} -> {c0 - u.joint, c1 + u.joint} end)),
          n <- floor((a + rem(k, 2) * pl / 2) / pl)..ceil((b + rem(k, 2) * pl / 2) / pl)//1,
          x0 = n * pl - rem(k, 2) * pl / 2,
          p0 = max(x0, a),
          p1 = min(x0 + u.l, b),
          p1 - p0 > 0.03,
          i <- 0..(wythes - 1) do
        {p0, i * (u.w + u.joint), z, p1 - p0}
      end

    # One part for each length of unit: the whole unit and its cuts.
    parts =
      units
      |> Enum.map(&round(elem(&1, 3) * 1000))
      |> Enum.uniq()
      |> Map.new(&{&1, Construction.masonry(unit, if(abs(&1 / 1000 - u.l) < 0.001, do: nil, else: &1 / 1000))})

    children =
      for {{x, y, z, l}, i} <- Enum.with_index(units) do
        part = %{parts[round(l * 1000)] | detail: :near}
        {"u#{i}", part, at("u#{i}", {x, y, z}, {1, 0, 0}, {0, 0, 1})}
      end

    lintel_parts =
      for {{x0, x1, z0, z1}, i} <- Enum.with_index(lintels) do
        {"lintel_#{i + 1}", Construction.lintel(x1 - x0, thick, z1 - z0 - u.joint),
         at("lintel_#{i + 1}", {x0, 0.0, z0}, {1, 0, 0}, {0, 0, 1})}
      end

    # The mortar behind the faces of the units, and the solid wall of the
    # low levels.
    mortar =
      solid(length, z_top, holes, {0.006, thick - 0.006}, :mortar) ++
        gable_prism(length, z_top, rise, {0.006, thick - 0.006}, :mortar)

    low =
      solid(length, z_top, holes, {0.0, thick}, u.material) ++
        gable_prism(length, z_top, rise, {0.0, thick}, u.material)

    Assembly.new(name, mark(name),
      root: "origin",
      kind: :wall,
      sources: [u.source, "Running bond, joints of mortar of 10 mm."]
    )
    |> Assembly.add_all(children ++ lintel_parts)
    |> Assembly.add("mortar", Part.new("mortar", :mortar, mortar, [@o], detail: :near), at: @o, port: @o)
    |> Assembly.add("wall_low", Part.new("#{name}_low", :wall, low, [@o], detail: :low), at: @o, port: @o)
  end

  # The span of a course with its top at `z`: the whole wall up to its top,
  # then a gable that narrows to its ridge.
  defp span(length, z, z_top, _rise) when z <= z_top + 1.0e-6, do: {0.0, length}
  defp span(length, z, z_top, rise), do: {length / 2 * (z - z_top) / rise, length - length / 2 * (z - z_top) / rise}

  defp gable_prism(_length, _z_top, rise, _ys, _material) when rise <= 0, do: []

  defp gable_prism(length, z_top, rise, {y0, y1}, material) do
    [
      Shape.prism([{0.0, 0.0}, {length, 0.0}, {length / 2, rise}], y1 - y0, material,
        frame: Frame.new({0.0, y1, z_top}, {0, -1, 0}, {0, 0, 1})
      )
    ]
  end

  # --- A wall of wood studs -------------------------------------------------------

  @doc """
  A wall of 2x4 studs at 16 in, with a bottom plate and a double top
  plate, OSB of 7/16 in and lap siding outside. `height` is the height of
  the frame. The options: `openings`, and `gable` (the rise of a gable,
  with its studs and its siding).
  """
  def stud_wall(name, length, height, opts \\ []) do
    {t, w} = Stock.table(:lumber, "2x4")
    openings = Keyword.get(opts, :openings, [])
    rise = Keyword.get(opts, :gable, 0.0)
    oc = inch(16)
    stud_len = height - 3 * t

    # The places of the common studs, then the studs of the openings.
    grid = (Enum.map(0..trunc((length - t) / oc), &max(&1 * oc - t / 2, 0.0)) ++ [length - t]) |> Enum.uniq()
    blocked = for {_, x, ow, _, _} <- openings, do: {x - 2 * t, x + ow + 2 * t}
    common = Enum.reject(grid, fn x -> Enum.any?(blocked, fn {a, b} -> x + t > a and x < b end) end)

    stud = Stock.lumber("2x4", stud_len) |> inside()
    flat = fn n, x, len, z -> {n, Stock.lumber("2x4", len) |> inside(), at(n, {x, 0.0, z}, {1, 0, 0}, {0, 0, 1})} end

    # The bottom plate stops at each door.
    doors = for {:door, x, ow, _, _} <- openings, do: {x, x + ow}

    framing =
      for({{a, b}, i} <- Enum.with_index(free(0.0, length, doors), 1), do: flat.("plate_bottom_#{i}", a, b - a, 0.0)) ++
        [flat.("plate_top_1", 0.0, length, height - 2 * t), flat.("plate_top_2", 0.0, length, height - t)] ++
        for({x, i} <- Enum.with_index(common, 1), do: {"stud_#{i}", stud, stud_at("stud_#{i}", x, t, w)}) ++
        Enum.flat_map(Enum.with_index(openings, 1), fn {o, i} -> opening_framing(o, i, t, w, height) end)

    gable_studs =
      if rise > 0 do
        for {x, i} <- Enum.with_index(Enum.filter(grid, &(&1 > 0.05 and &1 < length - t - 0.05)), 1) do
          h = rise * (1 - abs(x + t / 2 - length / 2) / (length / 2)) - 0.02
          {"gable_stud_#{i}", Stock.lumber("2x4", max(h, 0.05)) |> inside(), stud_at("gable_stud_#{i}", x, height, w)}
        end
      else
        []
      end

    holes = for {_, x, ow, z, oh} <- openings, do: {x, x + ow, z, z + oh}

    sheathing =
      solid(length, height, holes, {-0.011, 0.0}, :plywood) ++
        gable_prism(length, height, rise, {-0.011, 0.0}, :plywood)

    sheets = sheet_count(length, height, rise, holes)

    siding = siding(length, height, rise, holes)
    low = solid(length, height, holes, {-0.03, w}, :siding) ++ gable_prism(length, height, rise, {-0.03, w}, :siding)

    Assembly.new(name, mark(name),
      root: "origin",
      kind: :wall,
      sources: [
        "2x4 studs at 16 in (IRC R602.3), a double top plate, a header of two 2x8 over each opening; OSB of 7/16 in; lap siding of 8 in with 6 1/2 in of exposure."
      ]
    )
    |> Assembly.add_all(framing ++ gable_studs)
    |> Assembly.add(
      "sheathing",
      Part.new("osb_7_16", :sheathing, sheathing, [@o],
        params: %{"sheets_4x8" => sheets},
        inside: true,
        sources: ["OSB of 7/16 in, in sheets of 4 by 8 ft."]
      ),
      at: @o,
      port: @o
    )
    |> Assembly.add_all(for {s, i} <- Enum.with_index(siding, 1), do: {"siding_#{i}", s, [at: @o, port: @o]})
    |> Assembly.add("wall_low", Part.new("#{name}_low", :wall, low, [@o], detail: :low), at: @o, port: @o)
  end

  defp inside(%Part{} = p), do: %{p | inside: true}

  # A stud stands at x, from z: its thin side along x, its wide side
  # across the wall.
  defp stud_at(name, x, z, w), do: at(name, {x, w, z}, {0, 0, 1}, {1, 0, 0})

  # The studs of an opening: the king studs, the jack studs, the header,
  # the cripples over it; for a window the sill and the cripples under it.
  defp opening_framing({kind, x, ow, z, oh}, i, t, w, height) do
    hd = inch(7.25)
    top = height - 2 * t
    head_z = z + oh
    v = fn n, xx, len, zz -> {n, Stock.lumber("2x4", len) |> inside(), stud_at(n, xx, zz, w)} end

    kings = [v.("king_#{i}_a", x - 2 * t, top - t, t), v.("king_#{i}_b", x + ow + t, top - t, t)]
    jacks = [v.("jack_#{i}_a", x - t, head_z - t, t), v.("jack_#{i}_b", x + ow, head_z - t, t)]

    header =
      for {y, k} <- [{t, "a"}, {w, "b"}] do
        {"header_#{i}_#{k}", Stock.lumber("2x8", ow + 2 * t) |> inside(),
         at("header_#{i}_#{k}", {x - t, y, head_z}, {1, 0, 0}, {0, -1, 0})}
      end

    above = top - (head_z + hd)

    # Cripples over the header, when there is room for them.
    cripples_top =
      for c <- [x + ow * 0.25, x + ow * 0.75], above > 0.04 do
        v.("cripple_#{i}_#{round(c * 1000)}", c - t / 2, above, head_z + hd)
      end

    sill =
      if kind == :window and z > t do
        [{"sill_#{i}", Stock.lumber("2x4", ow) |> inside(), at("sill_#{i}", {x, 0.0, z - t}, {1, 0, 0}, {0, 0, 1})}] ++
          for c <- [x + ow * 0.25, x + ow * 0.75],
              do: v.("cripple_#{i}_low_#{round(c * 1000)}", c - t / 2, z - 2 * t, t)
      else
        []
      end

    kings ++ jacks ++ header ++ cripples_top ++ sill
  end

  # The count of the sheets of 4 by 8 ft: each grid cell of a sheet with a
  # part of the wall in it is a sheet to buy.
  defp sheet_count(length, height, rise, holes) do
    {sw, sh} = {inch(48), inch(96)}
    top = fn x -> height + rise * max(0.0, 1 - abs(x - length / 2) / (length / 2)) end

    whole = fn i, j ->
      Enum.any?(holes, fn {a, b, c, d} ->
        i * sw >= a and min((i + 1) * sw, length) <= b and j * sh >= c and min((j + 1) * sh, height) <= d
      end)
    end

    Enum.count(
      for i <- 0..trunc(length / sw),
          j <- 0..trunc((height + rise) / sh),
          i * sw < length - 0.01,
          j * sh < top.(min(i * sw + sw / 2, length)) - 0.01,
          not whole.(i, j),
          do: {i, j}
    )
  end

  # Lap siding: boards of 8 in with 6 1/2 in of exposure, cut around the
  # openings. Each board is a part (the list counts the pieces).
  defp siding(length, height, rise, holes) do
    exp = inch(6.5)
    rows = trunc((height + rise) / exp)

    for k <- 0..(rows - 1),
        z = k * exp,
        {s0, s1} = if(z + exp <= height, do: {0.0, length}, else: span(length, z + exp, height, max(rise, 1.0e-6))),
        s1 - s0 > 0.1,
        {a, b} <- free(s0, s1, cuts(holes, z, z + exp)),
        b - a > 0.05 do
      board =
        Shape.cage(
          [
            {a, -0.024, z},
            {b, -0.024, z},
            {b, -0.011, z},
            {a, -0.011, z},
            {a, -0.016, z + inch(8) - 0.004},
            {b, -0.016, z + inch(8) - 0.004},
            {b, -0.011, z + inch(8) - 0.004},
            {a, -0.011, z + inch(8) - 0.004}
          ],
          :siding
        )

      Part.new("lap_siding_8in", :siding, [board], [@o],
        detail: :near,
        sources: ["Lap siding of 8 in, 6 1/2 in of exposure."]
      )
    end
  end

  # --- The roof ---------------------------------------------------------------------

  @doc """
  A gable roof over walls of `length` (along x) and `depth` (along y),
  centered on x = 0 and y = 0, on the top of the walls at z = 0: rafters
  of 2x6 at 24 in and a ridge board of 2x8, OSB, and a `cover` of `:tile`
  or `:metal`. `pitch` is the rise over the run; `overhang` is beyond each
  wall.
  """
  def gable_roof(name, length, depth, pitch, overhang, cover) do
    {t, w} = Stock.table(:lumber, "2x6")
    a = :math.atan(pitch)
    {c, s} = {:math.cos(a), :math.sin(a)}
    run = depth / 2
    ridge_z = run * pitch
    rafter_len = (run + overhang) / c

    xs =
      for(k <- 0..trunc((length + 2 * overhang - t) / inch(24)), do: -length / 2 - overhang + k * inch(24)) ++
        [length / 2 + overhang - t]

    rafters =
      for {x, i} <- Enum.with_index(Enum.uniq(xs)), {side, sy} <- [{"f", 1}, {"b", -1}] do
        down = {0.0, sy * c, -s}
        {z_dir, x0} = if sy > 0, do: {{1, 0, 0}, x}, else: {{-1, 0, 0}, x + t}

        {"rafter_#{side}_#{i + 1}", Stock.lumber("2x6", rafter_len) |> inside(),
         at("rafter_#{side}_#{i + 1}", {x0, 0.0, ridge_z}, down, z_dir)}
      end

    ridge =
      {"ridge", Stock.lumber("2x8", length + 2 * overhang) |> inside(),
       at("ridge", {-length / 2 - overhang, t / 2, ridge_z - inch(7.25) + w / c}, {1, 0, 0}, {0, -1, 0})}

    # The roof planes: on the top of the rafters, from the ridge down.
    top = w / c
    width = length + 2 * overhang + 0.1

    plane = fn sy, thick, material ->
      n = {0.0, sy * s, c}
      x_dir = {sy * 1.0, 0.0, 0.0}
      origin = if sy > 0, do: {-width / 2, 0.0, ridge_z + top}, else: {width / 2, 0.0, ridge_z + top}

      Shape.box({0.0, 0.0, 0.0}, {width, rafter_len + 0.02, thick}, material,
        frame: Frame.new(origin, n, Vec.cross(n, x_dir))
      )
    end

    osb =
      Part.new("osb_7_16_roof", :sheathing, [plane.(1, 0.011, :plywood), plane.(-1, 0.011, :plywood)], [@o],
        inside: true,
        params: %{"sheets_4x8" => 2 * ceil(width / inch(96)) * ceil((rafter_len + 0.02) / inch(48))},
        sources: ["OSB of 7/16 in, in sheets of 4 by 8 ft."]
      )

    low =
      Part.new(
        "#{name}_low",
        :roof,
        [
          plane.(1, 0.05, if(cover == :tile, do: :tile, else: :roof_metal)),
          plane.(-1, 0.05, if(cover == :tile, do: :tile, else: :roof_metal))
        ],
        [@o],
        detail: :low
      )

    fascia =
      for sy <- [1, -1] do
        y = sy * (run + overhang)
        z = ridge_z - (run + overhang) * pitch
        Shape.box({-width / 2, min(y, y + sy * 0.02), z - 0.02}, {width / 2, max(y, y + sy * 0.02), z + w / c}, :white)
      end

    covering = roof_cover(cover, width, rafter_len, ridge_z + top + 0.011, s, c)

    Assembly.new(name, mark(name),
      root: "origin",
      kind: :roof,
      sources: ["Rafters of 2x6 at 24 in, a ridge board of 2x8, a pitch of #{pitch * 12} in 12."]
    )
    |> Assembly.add_all(rafters ++ [ridge])
    |> Assembly.add("osb", osb, at: @o, port: @o)
    |> Assembly.add("fascia", Part.new("fascia_1x8", :trim, fascia, [@o]), at: @o, port: @o)
    |> Assembly.add_all(covering)
    |> Assembly.add("roof_low", low, at: @o, port: @o)
  end

  # The cover of the roof on its two planes: tiles in rows, or metal
  # panels from the ridge to the eave.
  defp roof_cover(:metal, width, len, z, s, c) do
    count = ceil(width / 0.9144)

    panel = fn k ->
      %{Construction.metal_panel(Float.round(len + 0.05, 2), min(0.9144, width - k * 0.9144)) | detail: :near}
    end

    # A port with the axis on the normal of the plane and `up` down the
    # slope: the panel lies across x (to -x on the back plane).
    for sy <- [1, -1], k <- 0..(count - 1) do
      x = -width / 2 + k * 0.9144
      name = "panel_#{if sy > 0, do: "f", else: "b"}_#{k + 1}"
      {name, panel.(k), [at: Part.port(name, {sy * x, 0.0, z}, {0.0, sy * s, c}, {0.0, sy * c, -s}), port: @o]}
    end
  end

  defp roof_cover(:tile, width, len, z, s, c) do
    tile = %{Construction.roof_tile() | detail: :near}
    {across, down_step} = {0.28, 0.36}

    # The last row ends at the eave; the last tile of a row at the gable.
    rows = ceil((len - 0.424) / down_step) + 1
    cols = floor((width - 0.335) / across) + 1

    for sy <- [1, -1], i <- 0..(cols - 1), j <- 0..(rows - 1) do
      {n, down} = {{0.0, sy * s, c}, {0.0, sy * c, -s}}
      # Each row lies a little over the row under it (down the slope).
      p =
        {sy * (-width / 2 + i * across), 0.0, z}
        |> Vec.add(Vec.scale(down, j * down_step))
        |> Vec.add(Vec.scale(n, 0.004 * (rows - j)))

      name = "tile_#{if sy > 0, do: "f", else: "b"}_#{i}_#{j}"
      {name, tile, [at: Part.port(name, p, n, down), port: @o]}
    end
  end

  # --- Windows (the doors come from the doors factory, `World.Doors`) ----------------------

  @doc """
  A window of `w` by `h` (the rough opening) for a wall of `depth`: a
  frame of vinyl and a casement sash that opens out (-y), or a fixed
  pane. Its origin is at the bottom left of the rough opening.
  """
  def window(name, w, h, depth, kind \\ :casement) do
    f = 0.05
    {y0, y1} = {0.005, 0.085}

    # The frame, and the stool under it on the inside.
    frame = [
      Shape.box({0.006, y0, 0.006}, {f, y1, h - 0.006}, :white),
      Shape.box({w - f, y0, 0.006}, {w - 0.006, y1, h - 0.006}, :white),
      Shape.box({f, y0, 0.006}, {w - f, y1, f}, :white),
      Shape.box({f, y0, h - f}, {w - f, y1, h - 0.006}, :white),
      Shape.box({0.0, y1, 0.0}, {w, depth, 0.02}, :white)
    ]

    hinge_at = {f, y0 + 0.01, f}

    sash_shapes = [
      Shape.box({f, y0 + 0.01, f}, {f + 0.04, y0 + 0.05, h - f}, :white),
      Shape.box({w - f - 0.04, y0 + 0.01, f}, {w - f, y0 + 0.05, h - f}, :white),
      Shape.box({f + 0.04, y0 + 0.01, f}, {w - f - 0.04, y0 + 0.05, f + 0.04}, :white),
      Shape.box({f + 0.04, y0 + 0.01, h - f - 0.04}, {w - f - 0.04, y0 + 0.05, h - f}, :white),
      Shape.box({f + 0.04, y0 + 0.025, f + 0.04}, {w - f - 0.04, y0 + 0.035, h - f - 0.04}, :glass)
    ]

    base =
      Assembly.new(
        name,
        Part.new("window_frame_#{round(w / 0.0254)}x#{round(h / 0.0254)}", :frame, frame, [@o],
          params: %{"rough_opening" => [w, h]}
        ),
        root: "frame",
        kind: :window,
        sources: ["A vinyl window of #{round(w / 0.0254)} by #{round(h / 0.0254)} in (the rough opening)."]
      )

    sash =
      Part.new("window_sash_#{round(w / 0.0254)}x#{round(h / 0.0254)}", :sash, sash_shapes, [
        same("hinge", hinge_at, {0, 0, -1}, {0, 1, 0})
      ])

    if kind == :casement,
      do:
        Assembly.add(base, "sash_" <> name, sash,
          at: Kit.same("hinge", hinge_at, {0, 0, -1}, {0, 1, 0}),
          port: "hinge",
          kind: :hinge,
          role: :door,
          limits: [0, 90]
        ),
      else:
        Assembly.add(base, "sash_" <> name, sash, at: Kit.same("hinge", hinge_at, {0, 0, -1}, {0, 1, 0}), port: "hinge")
  end

  # --- The houses ------------------------------------------------------------------------

  @doc """
  A house: a slab of concrete, four walls, a gable roof along x, doors and
  windows. The options:

  - `length` (along x) and `depth` (along y), outside the walls;
  - `wall`: `{:masonry, unit, wythes}` or `:studs`, and `wall_height`;
  - `roof`: `:tile` or `:metal`, `pitch` (rise over run), `overhang`;
  - `openings`: a map of `:front`, `:back`, `:left`, `:right` to a list
    of `{:door, x, w, h}` (the slab) or `{:window, x, w, h, sill}` (the
    rough opening), with `x` the center along the wall, from its left
    when you look at it from outside.
  """
  def house(name, opts) do
    {l, d} = {opts[:length], opts[:depth]}
    slab = 0.1
    pitch = opts[:pitch]

    {thick, wall_top, build} =
      case opts[:wall] do
        {:masonry, unit, wythes} ->
          u = Construction.unit(unit)
          ph = u.h + u.joint
          top = round(opts[:wall_height] / ph) * ph

          {wythes * u.w + (wythes - 1) * u.joint, top,
           fn n, len, ops, rise -> masonry_wall(n, unit, len, top, wythes: wythes, openings: ops, gable: rise) end}

        :studs ->
          {_, w} = Stock.table(:lumber, "2x4")

          {w, opts[:wall_height],
           fn n, len, ops, rise -> stud_wall(n, len, opts[:wall_height], openings: ops, gable: rise) end}
      end

    side = d - 2 * thick

    # Each wall: its length, the point of its origin, and its x direction.
    walls = [
      {:front, l, {l / 2, d / 2, slab}, {-1, 0, 0}, 0.0},
      {:back, l, {-l / 2, -d / 2, slab}, {1, 0, 0}, 0.0},
      {:right, side, {l / 2, -d / 2 + thick, slab}, {0, 1, 0}, side / 2 * pitch},
      {:left, side, {-l / 2, d / 2 - thick, slab}, {0, -1, 0}, side / 2 * pitch}
    ]

    house =
      Assembly.new(
        name,
        Part.new(
          "slab_concrete",
          :slab,
          [Shape.box({-l / 2 - 0.1, -d / 2 - 0.1, 0.0}, {l / 2 + 0.1, d / 2 + 0.1, slab}, :concrete)],
          [@o],
          params: %{"area" => (l + 0.2) * (d + 0.2)}
        ),
        root: "slab",
        kind: :house,
        sources: Keyword.get(opts, :sources, [])
      )

    house =
      Enum.reduce(walls, house, fn {side_name, len, origin, x_dir, rise}, house ->
        items = Map.get(opts[:openings], side_name, [])

        # The rough openings, in the axes of the wall.
        holes =
          for item <- items do
            case item do
              {:door, x, w, h} ->
                {ro_w, ro_h} = World.Doors.prehung_opening(w, h)
                {:door, x - ro_w / 2, ro_w, 0.0, ro_h}

              {:window, x, w, h, sill} ->
                {:window, x - w / 2, w, sill, h}
            end
          end

        wall = build.("wall_#{side_name}", len, holes, rise)

        wall =
          Enum.reduce(Enum.with_index(Enum.zip(items, holes), 1), wall, fn {{item, {_, x, _, z, _}}, i}, wall ->
            n = "#{elem(item, 0)}_#{side_name}_#{i}"

            fill =
              case item do
                {:door, _, w, h} -> World.Doors.prehung(n, w, h, thick)
                {:window, _, w, h, _} -> window(n, w, h, thick)
              end

            Assembly.add(wall, n, fill, at: Part.port(n, {x, 0.0, z}, {0, 0, 1}, {0, 1, 0}), port: @o)
          end)

        Assembly.add(house, "wall_#{side_name}", wall, at("wall_#{side_name}", origin, x_dir, {0, 0, 1}))
      end)

    roof = gable_roof("roof", l, d, pitch, opts[:overhang], opts[:roof])
    Assembly.add(house, "roof", roof, at("roof", {0.0, 0.0, slab + wall_top}, {1, 0, 0}, {0, 0, 1}))
  end

  # --- The catalog ------------------------------------------------------------------------

  @doc "The models of houses and of their materials, as `{name, fun}`."
  def all do
    [
      {"brick_vn", &__MODULE__.brick_vn/0},
      {"brick_us_modular", &__MODULE__.brick_us/0},
      {"block_cmu_8in", &__MODULE__.block_cmu/0},
      {"roof_tile_clay", &__MODULE__.tile/0},
      {"door_prehung_36x80", &World.Doors.prehung_sample/0},
      {"window_casement_36x48", &__MODULE__.window_sample/0},
      {"wall_brick_sample", &__MODULE__.wall_brick_sample/0},
      {"wall_cmu_sample", &__MODULE__.wall_cmu_sample/0},
      {"wall_stud_sample", &__MODULE__.wall_stud_sample/0},
      {"house_brick_vn", &__MODULE__.house_brick_vn/0},
      {"cabin_wood_frame", &__MODULE__.cabin_wood_frame/0}
    ]
  end

  defp single(name, part), do: Assembly.new(name, part, root: "unit", kind: :material, sources: part.sources)

  @doc "A solid clay brick of Việt Nam (TCVN 1451): 220 by 105 by 60 mm."
  def brick_vn, do: single("brick_vn", Construction.masonry("brick_vn"))

  @doc "A modular brick (ASTM C216): 7 5/8 by 3 5/8 by 2 1/4 in."
  def brick_us, do: single("brick_us_modular", Construction.masonry("brick_us_modular"))

  @doc "A hollow concrete block of 8 in (ASTM C90)."
  def block_cmu, do: single("block_cmu_8in", Construction.masonry("cmu_8"))

  @doc "A clay roof tile (10 to the square meter)."
  def tile, do: single("roof_tile_clay", Construction.roof_tile())

  @doc "A casement window of 36 by 48 in (the rough opening), for a wall of 2x4."
  def window_sample, do: window("window_casement_36x48", inch(36), inch(48), inch(4.5))

  @doc "A wall of bricks of Việt Nam (one wythe, 110 mm): 2 m long, 1.5 m high, with a window."
  def wall_brick_sample,
    do: masonry_wall("wall_brick_sample", "brick_vn", 2.0, 1.5, openings: [{:window, 0.6, 0.8, 0.56, 0.6}])

  @doc "A wall of concrete blocks of 8 in: 2.4 m long, 1.6 m high, with a hole."
  def wall_cmu_sample, do: masonry_wall("wall_cmu_sample", "cmu_8", 2.4, 1.6, openings: [{:hole, 0.8, 0.8, 0.4, 0.6}])

  @doc "A wall of 2x4 studs: 8 ft long and 8 ft high, with a window of 36 by 48 in."
  def wall_stud_sample,
    do:
      stud_wall("wall_stud_sample", inch(96), inch(97.125),
        openings: [{:window, inch(30), inch(36), inch(36), inch(48)}]
      )

  @doc """
  A house of one floor of Việt Nam ("nhà cấp 4"): 6 by 4.2 m, walls of
  220 mm of bricks (two wythes), 3 m high, a roof of clay tiles at 26.6
  degrees with 0.5 m of overhang, a door and four windows.
  """
  def house_brick_vn do
    house("house_brick_vn",
      length: 6.0,
      depth: 4.2,
      wall: {:masonry, "brick_vn", 2},
      wall_height: 3.0,
      roof: :tile,
      pitch: 0.5,
      overhang: 0.5,
      openings: %{
        front: [{:window, 1.1, 1.0, 1.2, 0.91}, {:door, 3.0, 0.9, 2.1}, {:window, 4.9, 1.0, 1.2, 0.91}],
        back: [{:window, 3.0, 1.0, 1.2, 0.91}],
        left: [{:window, 1.9, 0.8, 1.0, 1.05}]
      },
      sources: [
        "A house of one floor of Việt Nam (nhà cấp 4): walls of 220 mm of solid bricks (TCVN 1451) in two wythes, a roof of clay tiles. The plan is an example, not of a real house."
      ]
    )
  end

  @doc """
  A cabin of 16 by 12 ft: walls of 2x4 studs at 16 in, 8 ft high, OSB
  and lap siding, a metal roof at 4 in 12 with 1 ft of overhang, a door of
  36 by 80 in and four windows of 36 by 48 in.
  """
  def cabin_wood_frame do
    window = fn x -> {:window, x, inch(36), inch(48), inch(36)} end

    house("cabin_wood_frame",
      length: inch(192),
      depth: inch(144),
      wall: :studs,
      wall_height: inch(97.125),
      roof: :metal,
      pitch: 4 / 12,
      overhang: inch(12),
      openings: %{
        front: [window.(inch(36)), {:door, inch(96), inch(36), inch(80)}, window.(inch(156))],
        back: [window.(inch(96))],
        right: [window.(inch(66))]
      },
      sources: [
        "A cabin of 16 by 12 ft with a frame of 2x4 studs (IRC R602), a metal roof. The plan is an example, not of a real cabin."
      ]
    )
  end
end
