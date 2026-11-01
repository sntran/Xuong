defmodule World.Vehicles.Van.BodyShop do
  @moduledoc """
  The first station of the line of a van (`World.Vehicles.Van`): the body
  in white.

  At the near level the body is of sheets on the hull: the nose, the
  fenders and the floor of the engine bay, the firewall, and from there
  to the back the sheets of the sides, the roof and the floor, 3 cm
  thick, with the openings (`World.Vehicles.Van.Openings`) cut: the
  windshield, the front doors, the sliding door, the rear doors, the
  windows of the body, and the arches of the wheels. Inside are the
  floors, the wells of the wheels and the pillar behind the front door
  at the right side. At the mid and far levels the body is closed.
  """
  alias World.Detail
  alias World.Vehicles.{Corners, Hull, Wheels}
  alias World.Vehicles.Van.{Kit, Openings}

  @station "body_shop"

  # The engine bay: from the back of the grille (d = 0.2) to the firewall
  # (d = 0.62), between the fenders (x from -0.6 to 0.6), over its floor
  # (z = 0.5).
  @bay {0.2, 0.62, 0.6, 0.5}

  # The cab floor (z) from the firewall to the back of the front doors:
  # by eye from the photos of the cab with the doors open.
  @cab_floor 0.6

  @doc "The body of a van, with its ports: `hood`, and a corner at each wheel."
  def body(van) do
    %{h: h, m: m} = van
    {d0, d1} = Hull.span(h)
    {b0, b1, bx, bz} = @bay
    side = fn x -> fn _ -> [x] end end

    nose = [
      Hull.skin(h, d0, b0, :paint),
      Hull.skin(h, b0, b1, :paint, clip: side.({:x_min, bx})),
      Hull.skin(h, b0, b1, :paint, clip: side.({:x_max, -bx})),
      Hull.skin(h, b0, b1, :paint, clip: side.({:z_max, bz}))
    ]

    cab_and_cargo =
      if Detail.level() == :near do
        firewall = Hull.skin(h, b1, b1 + 0.02, :paint)

        sheets =
          for s <- [1, -1],
              do:
                Hull.shell(h, b1, d1, :paint,
                  side: s,
                  step: 0.5,
                  holes: Openings.body_holes(van, s),
                  edges: Openings.edges(van)
                )

        [firewall | List.flatten(sheets)]
      else
        [Hull.skin(h, b1, d1, :paint)]
      end

    {f, wb, [tf, tr]} = {m["front"], m["wheelbase"], m["track"]}
    rz = Wheels.tire_radius(m["tire"])

    corners =
      for {name, x, d} <- [
            {"front_right", tf / 2, f},
            {"front_left", -tf / 2, f},
            {"rear_right", tr / 2, f + wb},
            {"rear_left", -tr / 2, f + wb}
          ],
          do: Corners.corner_port("corner_#{name}", {x, h.length - d, rz})

    Kit.part(@station, "body_" <> m["make"], :body, nose ++ cab_and_cargo, [Kit.origin() | corners],
      sources: van.make["openings"]["sources"]
    )
  end

  @doc """
  The parts inside the body, only at the near level: the floor of the
  cab and of the cargo area (plywood, or a rubber mat in the passenger
  van), the wells of the wheels, and the pillar behind the front door at
  the right side. Its ports are the mounting points of the seats
  (`mounts/1`).
  """
  def inside(van) do
    %{h: h, m: m, l: l} = van
    {_, f1} = Openings.front_door_span(van)
    {s0, _} = Openings.sliding_door_span(van)
    hw = Hull.half_width(h, (f1 + s0) / 2)
    floor = m["floor"]

    floors = [
      Hull.skin(h, 0.62, f1 + 0.05, :dark,
        clip: fn _ -> [{:z_min, @cab_floor - 0.02}, {:z_max, @cab_floor}] end,
        sides: 8
      ),
      Hull.skin(h, f1, l - 0.01, if(length(van.rows) > 1, do: :dark, else: :plywood),
        sides: 8,
        clip: fn d ->
          # Between the wells of the wheels, the floor is narrower.
          side =
            if Hull.arch(h, d),
              do: [{:x_max, Hull.half_width(h, d) - 0.3}, {:x_min, 0.3 - Hull.half_width(h, d)}],
              else: []

          [{:z_min, floor - 0.02}, {:z_max, floor} | side]
        end
      )
    ]

    wells =
      for {ad, az, r} <- h.arches, s <- [1, -1] do
        x0 = Hull.half_width(h, ad) - 0.3
        x1 = Hull.half_width(h, ad) - 0.03

        arc = fn radius ->
          for i <- 0..12, a = :math.pi() * i / 12, do: {l - ad + radius * :math.cos(a), az + radius * :math.sin(a)}
        end

        ring = fn x -> for {y, z} <- arc.(r + 0.03) ++ Enum.reverse(arc.(r)), do: {s * x, y, z} end
        World.Shape.rings([ring.(x0), ring.(x1)], :black)
      end

    # The pillar goes to 2.36 m, but not out through the side, which
    # leans in over the belt.
    top = min(2.36, lean_in(Hull.half(h, (f1 + s0) / 2), hw - 0.06) - 0.01)
    pillar = World.Shape.box({hw - 0.14, l - (s0 + 0.06), 0.42}, {hw - 0.06, l - (f1 - 0.04), top}, :paint)

    Kit.part(@station, "inside_" <> m["make"], :body, [pillar | floors ++ wells], [Kit.origin() | mounts(van)],
      detail: :near,
      sources: [
        "The floor of the cargo area at #{floor} m (the model); the floor of the cab, the wells of the wheels and the pillar behind the front door: by eye from the photos of the van with the doors open."
      ]
    )
  end

  @doc """
  The mounting points of the seats on the floors, from the seats of the
  make: `seat_driver` and `seat_passenger` on the floor of the cab, and
  `row_2` to `row_N` on the floor of the cargo area. Each port is under
  the center of the cushion, with the axis up and `up` to the front.
  """
  def mounts(van) do
    %{m: m, l: l, f: f} = van
    seats = van.make["seats"]
    at = fn name, x, d, z -> Kit.port(name, {x / 1, l - (f + d), z / 1}, {0, 0, 1}, {0, 1, 0}) end
    %{"x" => x, "d" => d} = seats["front"]

    [at.("seat_driver", -x, d, @cab_floor), at.("seat_passenger", x, d, @cab_floor)] ++
      for {row, i} <- Enum.with_index(seats["rows"], 2), do: at.("row_#{i}", row["x"], row["d"], m["floor"])
  end

  # The z where the right half of a section (`World.Vehicles.Hull.half/2`)
  # comes in past `x` at the top: the side leans in over the belt.
  defp lean_in(half, x) do
    half
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn [{x0, z0}, {x1, z1}] -> if x0 >= x and x1 < x, do: z0 + (z1 - z0) * (x0 - x) / (x0 - x1) end)
  end
end
