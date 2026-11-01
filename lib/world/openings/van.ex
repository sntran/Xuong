defmodule World.Openings.Van do
  @moduledoc """
  The doors and the windows of a van, from the openings factory
  (`World.Openings`). Each door is an assembly of the kind `:door`, made to the
  numbers of the order of the van (`World.Vehicles.Van.Order`): its
  panel, the glass of its window (a window of the order), and the mirror
  of a front door. The line of the van (`World.Vehicles.Van.Closures`)
  hangs each door on its hinges or its rail.

  A door at the near level fills its opening in the body, with a gap of
  4 mm around it; at the mid level it is on the closed body; at the far
  level only the mirrors and the glass show.

  The windows of the body (the windshield, and the windows at the left
  and the right side, `windshield/1`, `side/2`) are assemblies of the
  kind `:window`: the glass in its opening at the near level, flush with
  the body, or on the closed body at the mid and far levels.
  """
  alias World.{Assembly, Detail, Shape, Vec}
  alias World.Vehicles.Hull
  alias World.Vehicles.Van.{Kit, Trim}
  alias World.Vehicles.Van.Openings, as: Cuts
  @station "openings"
  @gap 0.004

  @doc """
  A front door at a side (1 the right, -1 the left), with its port
  `hinge` at its front edge.
  """
  def front(van, s) do
    %{h: h, l: l, f: f} = van
    {d0, d1} = Cuts.front_door_span(van)
    hinge = front_hinge(van, s)
    window = fn d -> Cuts.door_window(van, d) end

    {panel, glass} =
      case Detail.level() do
        :far ->
          {[], region(van, d0, d1, window, s, :far)}

        _ ->
          o = out()

          panel =
            Hull.shell(h, d0, d1, :paint,
              side: s,
              thickness: 0.05,
              offset: o,
              step: 0.1,
              clip: fn d -> Cuts.front_door(van, d, @gap) || [{:z_min, 9.0}] end,
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
    {s0, s1} = Cuts.sliding_door_span(van)
    hw = Hull.half_width(h, s0 + 0.15)
    window = Cuts.slider_window(van)

    {panel, glass} =
      case {Detail.level(), window} do
        {:far, nil} ->
          {[], []}

        {:far, {w0, w1, c}} ->
          {[], region(van, w0, w1, &Cuts.side_window(van, &1, w0, w1, c), 1, :far)}

        _ ->
          o = out()

          hole = fn d ->
            if window, do: [Cuts.side_window(van, d, elem(window, 0), elem(window, 1), elem(window, 2))], else: []
          end

          panel =
            Hull.shell(h, s0, s1, :paint,
              thickness: 0.05,
              offset: o,
              step: 0.1,
              clip: fn d -> Cuts.sliding_door(van, d, @gap) || [{:z_min, 9.0}] end,
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
                  clip: fn d -> Cuts.side_window(van, d, w0, w1, c) || [{:z_min, 9.0}] end
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
    {d0, _} = Cuts.front_door_span(van)
    Kit.port("hinge", {s * Hull.half_width(h, d0 + 0.02), l - d0 - 0.02, 1.0}, {0, 0, s}, {0, 1, 0})
  end

  @doc "The port `hinge` of a rear door, at its outer edge."
  def rear_hinge(van, s) do
    {_, hw, _, _} = Cuts.rear(van)
    Kit.port("hinge", {s * hw, 0.0, 1.5}, {0, 0, s}, {0, 1, 0})
  end

  @doc "The port `slide` of the sliding door, on its rail: it slides back, and out from the body."
  def slide(van) do
    %{h: h, l: l} = van
    {s0, s1} = Cuts.sliding_door_span(van)
    hw = Hull.half_width(h, s0 + 0.15)
    Kit.port("slide", {hw, l - (s0 + s1) / 2, 1.4}, Vec.norm({0.1, -1.0, 0.0}), {0, 0, 1})
  end

  @doc "A rear door at a side (1 the right, -1 the left), with its port `hinge` at its outer edge."
  def rear(van, s) do
    %{h: h} = van
    {_, d1} = Hull.span(h)
    {r0, _, _, _} = Cuts.rear(van)
    hinge = rear_hinge(van, s)
    window = fn d -> Cuts.rear_window(van, d) end

    {panel, glass} =
      case Detail.level() do
        :far ->
          {[], if(Cuts.window(van, "rear_doors"), do: rear_glass(van, r0, d1, s, 0.008, 0.1), else: [])}

        _ ->
          o = out()

          panel =
            Hull.shell(h, r0, d1, :paint,
              side: s,
              thickness: 0.03,
              offset: o,
              step: 0.05,
              clip: fn d -> Cuts.rear_doors(van, d, @gap) end,
              holes: fn d -> holes([window.(d)]) end
            )

          glass = if Cuts.window(van, "rear_doors"), do: rear_glass(van, r0, d1, s, glass_out(), 0.05), else: []

          handle = if s == 1, do: [Shape.box({0.05, -0.03, 1.12}, {0.2, -0.01, 1.16}, :black)], else: []
          {panel ++ handle, glass}
      end

    name = if s == 1, do: "rear_door_right", else: "rear_door_left"
    sources = van.make["openings"]["sources"] |> Enum.slice(2, 1)

    door(name, Kit.part(@station, "rear_door_panel", :door, panel, [hinge, Kit.origin()], sources: sources), sources)
    |> add("glass", Kit.part(@station, "rear_door_glass", :glass, glass, [Kit.origin()]))
  end

  # --- The windows of the body ----------------------------------------------------------

  @doc "The windshield: from its base at the cowl to its top."
  def windshield(van) do
    %{h: h} = van
    w = van.make["openings"]["windshield"]
    top = Cuts.windshield_top(van)

    shapes =
      case Detail.level() do
        :near ->
          for s <- [1, -1] do
            Hull.shell(h, w["base"], top, :glass_dark,
              side: s,
              thickness: 0.008,
              offset: -0.004,
              step: 0.05,
              clip: fn d -> Cuts.windshield(van, d) || [{:z_min, 9.0}] end
            )
          end

        level ->
          Hull.skin(h, w["base"], top, :glass_dark,
            offset: %{mid: 0.01, far: 0.025}[level],
            sides: 16,
            step: 0.05,
            clip: fn d ->
              inset = Hull.half_width(h, d) - w["inset"]
              [{:z_min, Hull.z_high(h, d) - 0.04}, {:x_max, inset}, {:x_min, -inset}]
            end
          )
      end

    window("windshield", Kit.part(@station, "windshield", :glass, List.flatten([shapes]), [Kit.origin()]), [])
  end

  @doc """
  The window of the body at a side (1 the right, -1 the left), the window
  `right` or `left` of the order: `{name, window}`, or nil.
  """
  def side(van, s) do
    case Cuts.side_windows(van, s) do
      [] ->
        nil

      [{d0, d1, c}] ->
        planes = &Cuts.side_window(van, &1, d0, d1, c)

        shapes =
          case Detail.level() do
            :near ->
              Hull.shell(van.h, d0, d1, :glass_dark,
                side: s,
                thickness: 0.008,
                offset: -0.004,
                step: 0.05,
                clip: fn d -> planes.(d) || [{:z_min, 9.0}] end
              )

            level ->
              region(van, d0, d1, planes, s, level)
          end

        name = if s == 1, do: "window_right", else: "window_left"
        sources = van.make["windows"]["sources"]

        {name,
         window(
           name,
           Kit.part(@station, name, :glass, List.flatten([shapes]), [Kit.origin()], sources: sources),
           sources
         )}
    end
  end

  # The glass of a window on the closed body (the mid and far levels): a
  # skin over the region of the window at a side.
  defp region(van, d0, d1, planes, s, level) do
    [
      Hull.skin(van.h, d0, d1, :glass_dark,
        offset: 0.006,
        sides: 8,
        step: %{mid: 0.1, far: 0.3}[level],
        clip: fn d -> Kit.mirror(planes.(d) || [{:z_min, 9.0}], s) end
      )
    ]
  end

  # The glass of a rear door at a side.
  defp rear_glass(van, r0, d1, s, offset, step) do
    Hull.shell(van.h, r0, d1, :glass_dark,
      side: s,
      thickness: 0.008,
      offset: offset,
      step: step,
      clip: &Cuts.rear_window(van, &1)
    )
  end

  # A window: its glass at the root, of the kind `:window`.
  defp window(name, glass, sources), do: Assembly.new(name, glass, root: "glass", kind: :window, sources: sources)

  # A door: its panel at the root, of the kind `:door` (the openings
  # factory makes it, `World.Places.family_of/1`).
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
