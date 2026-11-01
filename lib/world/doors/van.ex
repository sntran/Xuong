defmodule World.Doors.Van do
  @moduledoc """
  The doors of a van, from the doors factory (`World.Doors`): each door
  is an assembly of the kind `:door`, made to the
  numbers of the order of the van (`World.Vehicles.Van.Order`): its
  panel, the glass of its window (a window of the order), and the mirror
  of a front door. The line of the van (`World.Vehicles.Van.Closures`)
  hangs each door on its hinges or its rail.

  A door at the near level fills its opening in the body, with a gap of
  4 mm around it; at the mid level it is on the closed body; at the far
  level only the mirrors show (the glass of the windows is on the body).
  """
  alias World.{Assembly, Detail, Shape, Vec}
  alias World.Vehicles.Hull
  alias World.Vehicles.Van.{Kit, Openings, Trim}
  @station "doors"
  @gap 0.004

  @doc """
  A front door at a side (1 the right, -1 the left), with its port
  `hinge` at its front edge.
  """
  def front(van, s) do
    %{h: h, l: l, f: f} = van
    {d0, d1} = Openings.front_door_span(van)
    hinge = front_hinge(van, s)
    window = fn d -> Openings.door_window(van, d) end

    {panel, glass} =
      case Detail.level() do
        :far ->
          {[], []}

        _ ->
          o = out()

          panel =
            Hull.shell(h, d0, d1, :paint,
              side: s,
              thickness: 0.05,
              offset: o,
              step: 0.1,
              clip: fn d -> Openings.front_door(van, d, @gap) || [{:z_min, 9.0}] end,
              holes: fn d -> holes([window.(d)]) end,
              edges: [d0 + @gap, d1 - @gap, d0 + 0.04, d1 - 0.06]
            )

          glass =
            Hull.shell(h, d0 + 0.04, d1 - 0.06, :glass_dark,
              side: s,
              thickness: 0.008,
              offset: glass_out(),
              step: 0.1,
              clip: fn d -> window.(d) || [{:z_min, 9.0}] end
            )

          [{_, _, af} | _] = h.arches
          [b0, b1] = Trim.band(van)

          band =
            Hull.skin(h, f + af - 0.02, d1 - @gap, :trim,
              offset: o + 0.006,
              sides: 12,
              step: 0.1,
              clip: fn d -> Kit.mirror([{:x_min, Hull.half_width(h, d) - 0.06}, {:z_min, b0}, {:z_max, b1}], s) end
            )

          hw = Hull.half_width(h, 2.0)
          {xa, xb} = Enum.min_max([s * hw, s * (hw + 0.025)])
          handle = Shape.box({xa, l - 2.1, 1.15}, {xb, l - 1.94, 1.185}, :black)
          {panel ++ [band, handle], glass}
      end

    name = if s == 1, do: "front_door_right", else: "front_door_left"
    sources = van.make["openings"]["sources"] |> Enum.take(1)

    door(name, Kit.part(@station, "front_door_panel", :door, panel, [hinge, Kit.origin()], sources: sources), sources)
    |> add("glass", Kit.part(@station, "front_door_glass", :glass, glass, [Kit.origin()]))
    |> add("mirror", Kit.part(@station, "mirror", :mirror, mirror(van, s), [Kit.origin()]))
  end

  @doc "The sliding door at the right side, with its port `slide` on its rail."
  def sliding(van) do
    %{h: h, l: l} = van
    {s0, s1} = Openings.sliding_door_span(van)
    hw = Hull.half_width(h, s0 + 0.15)
    window = Openings.slider_window(van)

    {panel, glass} =
      case Detail.level() do
        :far ->
          {[], []}

        _ ->
          o = out()

          hole = fn d ->
            if window, do: [Openings.side_window(van, d, elem(window, 0), elem(window, 1), elem(window, 2))], else: []
          end

          panel =
            Hull.shell(h, s0, s1, :paint,
              thickness: 0.05,
              offset: o,
              step: 0.1,
              clip: fn d -> Openings.sliding_door(van, d, @gap) || [{:z_min, 9.0}] end,
              holes: fn d -> holes(hole.(d)) end,
              edges: [s0 + @gap, s1 - @gap | if(window, do: [elem(window, 0), elem(window, 1)], else: [])]
            )

          glass =
            case window do
              nil ->
                []

              {w0, w1, c} ->
                Hull.shell(h, w0, w1, :glass_dark,
                  thickness: 0.008,
                  offset: glass_out(),
                  step: 0.1,
                  clip: fn d -> Openings.side_window(van, d, w0, w1, c) || [{:z_min, 9.0}] end
                )
            end

          [b0, b1] = Trim.band(van)

          band =
            Hull.skin(h, s0 + @gap, s1 - @gap, :trim,
              offset: o + 0.006,
              sides: 12,
              step: 0.1,
              clip: fn d -> [{:x_min, Hull.half_width(h, d) - 0.06}, {:z_min, b0}, {:z_max, b1}] end
            )

          handle = Shape.box({hw + o, l - s0 - 0.25, 1.15}, {hw + o + 0.025, l - s0 - 0.09, 1.185}, :black)
          {panel ++ [band, handle], glass}
      end

    slide = slide(van)
    sources = van.make["openings"]["sources"] |> Enum.slice(1, 1)

    door(
      "sliding_door",
      Kit.part(@station, "sliding_door_panel", :door, panel, [slide, Kit.origin()], sources: sources),
      sources
    )
    |> add("glass", Kit.part(@station, "sliding_door_glass", :glass, glass, [Kit.origin()]))
  end

  @doc "The port `hinge` of a front door, at its front edge."
  def front_hinge(%{h: h, l: l} = van, s) do
    {d0, _} = Openings.front_door_span(van)
    Kit.port("hinge", {s * Hull.half_width(h, d0 + 0.02), l - d0 - 0.02, 1.0}, {0, 0, s}, {0, 1, 0})
  end

  @doc "The port `hinge` of a rear door, at its outer edge."
  def rear_hinge(van, s) do
    {_, hw, _, _} = Openings.rear(van)
    Kit.port("hinge", {s * hw, 0.0, 1.5}, {0, 0, s}, {0, 1, 0})
  end

  @doc "The port `slide` of the sliding door, on its rail: it slides back, and out from the body."
  def slide(van) do
    %{h: h, l: l} = van
    {s0, s1} = Openings.sliding_door_span(van)
    hw = Hull.half_width(h, s0 + 0.15)
    Kit.port("slide", {hw, l - (s0 + s1) / 2, 1.4}, Vec.norm({0.1, -1.0, 0.0}), {0, 0, 1})
  end

  @doc "A rear door at a side (1 the right, -1 the left), with its port `hinge` at its outer edge."
  def rear(van, s) do
    %{h: h} = van
    {_, d1} = Hull.span(h)
    {r0, _, _, _} = Openings.rear(van)
    hinge = rear_hinge(van, s)
    window = fn d -> Openings.rear_window(van, d) end

    {panel, glass} =
      case Detail.level() do
        :far ->
          {[], []}

        _ ->
          o = out()

          panel =
            Hull.shell(h, r0, d1, :paint,
              side: s,
              thickness: 0.03,
              offset: o,
              step: 0.05,
              clip: fn d -> Openings.rear_doors(van, d, @gap) end,
              holes: fn d -> holes([window.(d)]) end
            )

          glass =
            if Openings.window(van, "rear_doors"),
              do:
                Hull.shell(h, r0, d1, :glass_dark,
                  side: s,
                  thickness: 0.008,
                  offset: glass_out(),
                  step: 0.05,
                  clip: window
                ),
              else: []

          handle = if s == 1, do: [Shape.box({0.05, -0.03, 1.12}, {0.2, -0.01, 1.16}, :black)], else: []
          {panel ++ handle, glass}
      end

    name = if s == 1, do: "rear_door_right", else: "rear_door_left"
    sources = van.make["openings"]["sources"] |> Enum.slice(2, 1)

    door(name, Kit.part(@station, "rear_door_panel", :door, panel, [hinge, Kit.origin()], sources: sources), sources)
    |> add("glass", Kit.part(@station, "rear_door_glass", :glass, glass, [Kit.origin()]))
  end

  # A door: its panel at the root, of the kind `:door` (the doors factory
  # makes it, `World.Places.family_of/1`).
  defp door(name, panel, sources), do: Assembly.new(name, panel, root: "panel", kind: :door, sources: sources)

  defp add(door, name, part), do: Assembly.add(door, name, part, at: "origin", port: "origin")

  # Out from the body: 0 at the near level (the door is in its opening),
  # a little at the mid level (on the closed body).
  defp out, do: if(Detail.level() == :near, do: 0.0, else: 0.004)

  # The glass of a door: a little in from the door in its opening (near),
  # or on the door (mid).
  defp glass_out, do: if(Detail.level() == :near, do: -0.004, else: 0.008)

  # The holes of a door for its windows: only at the near level; at the
  # mid level the glass is on the door.
  defp holes(windows), do: if(Detail.level() == :near, do: Enum.reject(windows, &is_nil/1), else: [])

  # A mirror on the front door: a tall black head (0.48 m) on two arms,
  # 0.2 m out from the side, with its glass at the back.
  defp mirror(%{h: h, l: l, f: f}, s) do
    hw_m = Hull.half_width(h, f + 0.17)
    ym = l - f - 0.17
    round_head = if Detail.level() == :near, do: [round: 0.12, smooth: 1], else: []
    x0 = s * (hw_m + 0.02)
    x1 = s * (hw_m + 0.204)
    {xa, xb} = {min(x0, x1), max(x0, x1)}

    [
      Shape.box({xa, ym - 0.045, 1.24}, {xb, ym + 0.045, 1.72}, :black, round_head),
      Shape.box({min(xa, xb - 0.17), ym - 0.051, 1.27}, {max(xb, xa + 0.17), ym - 0.045, 1.69}, :glass_dark),
      Shape.box({min(s * hw_m, x0), ym - 0.02, 1.33}, {max(s * hw_m, x0), ym + 0.02, 1.37}, :black),
      Shape.box({min(s * hw_m, x0), ym - 0.02, 1.6}, {max(s * hw_m, x0), ym + 0.02, 1.64}, :black)
    ]
  end
end
