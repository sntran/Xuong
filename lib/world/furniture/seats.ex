defmodule World.Furniture.Seats do
  @moduledoc """
  Seats and benches, built as a real seat is built: a base that bolts to
  the floor, the cushion on the base, the back on its hinge, and a
  headrest for each place. A bench is a seat with more places. A vehicle
  or a room puts a seat on a port of its floor; the seats of two vans
  differ only in their options.

  The axes of a seat: x across, y to its front, z up. The port `floor` is
  at the origin, on the floor under the center of the cushion, with the
  axis up (+z) and `up` to the front (+y).

  The nodes of a seat named `driver`:

  - `driver_base`: the root. A pedestal (`base: :pedestal`) or the
    legs of a bench (`base: :legs`).
  - `driver_seat`: the cushion. With `track: travel`, it is a joint
    (`:slide`, role `slide`) that moves along y from `-travel / 2` to
    `travel / 2` (meters).
  - `driver_back`: the back. With `recline: [min, max]`, it is a joint
    (`:hinge`, role `recline`): a value more than 0 turns the back to
    the rear (degrees).
  - `driver_head_1` (to `driver_head_N`): the headrests on the back.
  """
  alias World.{Assembly, Part, Shape}

  @defaults [
    place_width: 0.5,
    depth: 0.5,
    height: 0.45,
    cushion: 0.12,
    back: 0.55,
    thickness: 0.1,
    rake: 12,
    base: :legs,
    track: nil,
    recline: nil,
    headrest: true,
    material: :seat,
    sources: []
  ]

  @doc """
  A seat for one person: a bench with one place on a pedestal. The
  options are as for `bench/3`.
  """
  def seat(name, opts \\ []), do: bench(name, 1, Keyword.put_new(opts, :base, :pedestal))

  @doc """
  A bench with `places` places. The options (lengths in meters, angles in
  degrees):

  - `place_width` (0.5), `depth` of the cushion (0.5), `height` of the
    top of the cushion above the floor (0.45), `cushion` thickness (0.12);
  - `back`: the height of the back above the cushion (0.55), its
    `thickness` (0.1), and its `rake` back from the vertical at rest (12);
  - `base`: `:legs` (the default) or `:pedestal`;
  - `track`: the travel of the cushion on its track, or `nil` (fixed);
  - `recline`: the limits of the back, or `nil` (fixed);
  - `headrest` (true), `material` of the cushion and the back (`:seat`),
    `sources`.
  """
  def bench(name, places, opts \\ []) do
    o = Map.new(Keyword.merge(@defaults, opts))
    w = places * o.place_width
    zb = o.height - o.cushion
    hinge = {0.0, -o.depth / 2 + 0.06, o.height - 0.02}
    params = %{"places" => places, "width" => w, "height" => o.height, "depth" => o.depth}

    base =
      Part.new(name <> "_base", :seat_base, base(o.base, w, o.depth, zb), [
        Part.port("floor", {0, 0, 0}, {0, 0, 1}, {0, 1, 0}),
        Part.port("track", {0, 0, zb}, {0, 1, 0}, {0, 0, 1})
      ])

    cushion =
      Part.new(name <> "_cushion", :cushion, cushion(o, w, zb), [
        Part.port("track", {0, 0, zb}, {0, 1, 0}, {0, 0, 1}),
        Part.port("hinge", hinge, {1, 0, 0}, {0, 0, 1})
      ])

    {back, heads} = back(o, w, hinge, places)

    asm =
      Assembly.new(name, base,
        root: name <> "_base",
        kind: :seat,
        sources: o.sources,
        extras: %{"params" => params}
      )
      |> Assembly.add(name <> "_seat", cushion, [at: "track", port: "track"] ++ track(o.track))
      |> Assembly.add(
        name <> "_back",
        Part.new(name <> "_back", :seat_back, back, [Part.port("hinge", hinge, {1, 0, 0}, {0, 0, 1})]),
        [to: name <> "_seat", at: "hinge", port: "hinge"] ++ recline(o.recline)
      )

    if o.headrest do
      heads
      |> Enum.with_index(1)
      |> Enum.reduce(asm, fn {{shapes, at}, i}, asm ->
        port = Part.port("post", at, {0, 0, 1}, {0, 1, 0})

        Assembly.add(asm, "#{name}_head_#{i}", Part.new("headrest", :headrest, shapes, [port]),
          to: name <> "_back",
          at: port,
          port: "post"
        )
      end)
    else
      asm
    end
  end

  defp track(nil), do: []
  defp track(travel), do: [kind: :slide, role: :slide, limits: [-travel / 2, travel / 2]]

  defp recline(nil), do: []
  defp recline(limits), do: [kind: :hinge, role: :recline, limits: limits]

  # A pedestal: a box under the cushion with the two rails of the track.
  defp base(:pedestal, w, d, zb) do
    rails =
      for s <- [1, -1] do
        x = s * (w / 2 - 0.1)
        Shape.box({x - 0.015, -d / 2 + 0.04, zb - 0.03}, {x + 0.015, d / 2 - 0.04, zb}, :steel)
      end

    [Shape.box({-w / 2 + 0.06, -d / 2 + 0.05, 0.0}, {w / 2 - 0.06, d / 2 - 0.08, zb - 0.03}, :black) | rails]
  end

  # The legs of a bench: a frame at each end, with a rail at the front
  # and at the back.
  defp base(:legs, w, d, zb) do
    {y0, y1, t} = {-d / 2 + 0.06, d / 2 - 0.08, 0.03}

    ends =
      for s <- [1, -1], x = s * (w / 2 - 0.06), y <- [y0, y1] do
        Shape.box({x - t / 2, y - t / 2, 0.0}, {x + t / 2, y + t / 2, zb}, :black)
      end

    sides =
      for s <- [1, -1],
          x = s * (w / 2 - 0.06),
          do: Shape.box({x - t / 2, y0 - t / 2, zb - t}, {x + t / 2, y1 + t / 2, zb}, :black)

    rails =
      for y <- [y0, y1], do: Shape.box({-w / 2 + 0.06, y - t / 2, zb - t}, {w / 2 - 0.06, y + t / 2, zb}, :black)

    ends ++ sides ++ rails
  end

  # The cushion: its front is a little higher than its back.
  defp cushion(o, w, zb) do
    {x0, x1, y0, y1} = {-w / 2, w / 2, -o.depth / 2, o.depth / 2}
    {zt, zf} = {o.height - 0.02, o.height}

    Shape.cage(
      [{x0, y0, zb}, {x1, y0, zb}, {x1, y1, zb}, {x0, y1, zb}, {x0, y0, zt}, {x1, y0, zt}, {x1, y1, zf}, {x0, y1, zf}],
      o.material,
      round: 0.2
    )
  end

  # The back, from its hinge up at the rake, and the place of the
  # headrest of each place on its top.
  defp back(o, w, {_, yh, zh}, places) do
    lean = :math.tan(o.rake * :math.pi() / 180)
    {x0, x1, t, zt} = {-w / 2, w / 2, o.thickness, zh + o.back}
    top = yh - o.back * lean

    back =
      Shape.cage(
        [{x0, yh - t, zh}, {x1, yh - t, zh}, {x1, yh, zh}, {x0, yh, zh}] ++
          [{x0, top - t, zt}, {x1, top - t, zt}, {x1, top, zt}, {x0, top, zt}],
        o.material,
        round: 0.2
      )

    heads =
      for i <- 1..places do
        x = x0 + o.place_width * (i - 0.5)
        y = top - t / 2
        {z0, z1} = {zt + 0.05, zt + 0.23}
        dy = 0.23 * lean

        posts =
          for dx <- [-0.07, 0.07],
              do: Shape.box({x + dx - 0.006, y - 0.006, zt - 0.01}, {x + dx + 0.006, y + 0.006, z0}, :steel)

        pad =
          Shape.cage(
            [{x - 0.13, y - 0.05, z0}, {x + 0.13, y - 0.05, z0}, {x + 0.13, y + 0.04, z0}, {x - 0.13, y + 0.04, z0}] ++
              [
                {x - 0.13, y - 0.05 - dy, z1},
                {x + 0.13, y - 0.05 - dy, z1},
                {x + 0.13, y + 0.04 - dy, z1},
                {x - 0.13, y + 0.04 - dy, z1}
              ],
            o.material,
            round: 0.25
          )

        {[pad | posts], {x, y, zt}}
      end

    {[back], heads}
  end
end
