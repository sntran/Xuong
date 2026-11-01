defmodule World.Vehicles.Van.Closures do
  @moduledoc """
  The second station of the line of a van (`World.Vehicles.Van`): the
  closures on their hinges and rails. The hood turns up at the front;
  each front door turns out on hinges at its front edge, with its window
  and its mirror; the sliding door at the right side slides back; the
  two rear doors turn out on hinges at their outer edges.

  A door at the near level fills its opening in the body, with a gap of
  4 mm around it; at the mid level it is on the closed body; at the far
  level only the mirrors show.
  """
  alias World.{Assembly, Detail, Shape, Vec}
  alias World.Vehicles.Hull
  alias World.Vehicles.Van.{Kit, Openings, Trim}
  @station "closures"
  @gap 0.004

  # The hood: from its front edge (the top of the grille) to the black
  # strip at the base of the windshield.
  @hood {0.132, 0.634}

  @doc "The van with its hood and its doors."
  def hang(asm, van) do
    asm
    |> hood(van)
    |> front_doors(van)
    |> sliding_door(van)
    |> rear_doors(van)
  end

  # Out from the body: 0 at the near level (the door is in its opening),
  # a little at the mid level (on the closed body).
  defp out, do: if(Detail.level() == :near, do: 0.0, else: 0.004)

  # The glass of a door: a little in from the door in its opening (near),
  # or on the door (mid).
  defp glass_out, do: if(Detail.level() == :near, do: -0.004, else: 0.008)

  # The holes of a door for its windows: only at the near level; at the
  # mid level the glass is on the door.
  defp holes(windows), do: if(Detail.level() == :near, do: Enum.reject(windows, &is_nil/1), else: [])

  defp hood(asm, %{h: h}) do
    {hd0, hd1} = @hood
    hz = Hull.z_high(h, hd1)

    shell =
      Hull.skin(h, hd0, hd1, :paint,
        offset: 0.004,
        sides: 24,
        step: 0.03,
        clip: fn d -> [{:z_min, Hull.z_high(h, d) - 0.035}] end
      )

    hinge = Kit.port("hinge", {0.0, h.length - hd1, hz - 0.006}, {1, 0, 0}, {0, 0, 1})

    Assembly.add(asm, "hood", Kit.part(@station, "hood_transit", :lid, [shell], [hinge]),
      at: hinge,
      port: "hinge",
      kind: :hinge,
      role: :lid,
      limits: [0, 60]
    )
  end

  # --- The front doors --------------------------------------------------------------------

  defp front_doors(asm, van) do
    Enum.reduce([{"front_door_right", 1}, {"front_door_left", -1}], asm, fn {name, s}, asm ->
      %{h: h, l: l, f: f} = van
      {d0, d1} = Openings.front_door_span(van)
      hinge_d = d0 + 0.02
      hinge = Kit.port("hinge", {s * Hull.half_width(h, hinge_d), l - hinge_d, 1.0}, {0, 0, s}, {0, 1, 0})

      shapes =
        case Detail.level() do
          :far ->
            mirror(van, s)

          _ ->
            o = out()
            window = fn d -> Openings.door_window(van, d) end

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
            panel ++ glass ++ [band, handle | mirror(van, s)]
        end

      door =
        Kit.part(@station, "front_door_transit", :door, shapes, [hinge],
          sources: van.make["openings"]["sources"] |> Enum.take(1)
        )

      Assembly.add(asm, name, door, at: hinge, port: "hinge", kind: :hinge, role: :door, limits: [0, 70])
    end)
  end

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

  # --- The sliding door -------------------------------------------------------------------

  defp sliding_door(asm, van) do
    %{h: h, l: l} = van
    {s0, s1} = Openings.sliding_door_span(van)
    hw = Hull.half_width(h, s0 + 0.15)

    shapes =
      case Detail.level() do
        :far ->
          []

        _ ->
          o = out()
          window = Openings.slider_window(van)

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
          panel ++ glass ++ [band, handle]
      end

    # It slides back along the rail, and out from the body.
    axis = Vec.norm({0.1, -1.0, 0.0})
    at = {hw, l - (s0 + s1) / 2, 1.4}

    door =
      Kit.part(@station, "sliding_door_transit", :door, shapes, [Kit.port("slide", at, axis, {0, 0, 1})],
        sources: van.make["openings"]["sources"] |> Enum.slice(1, 1)
      )

    Assembly.add(asm, "sliding_door", door,
      at: Kit.port("slide", at, axis, {0, 0, 1}),
      port: "slide",
      kind: :slide,
      role: :door,
      limits: [0, 1.25]
    )
  end

  # --- The rear doors ---------------------------------------------------------------------

  defp rear_doors(asm, van) do
    %{h: h} = van
    {_, d1} = Hull.span(h)
    {r0, hw, _, _} = Openings.rear(van)

    Enum.reduce([{"rear_door_right", 1}, {"rear_door_left", -1}], asm, fn {name, s}, asm ->
      shapes =
        case Detail.level() do
          :far ->
            []

          _ ->
            o = out()
            window = fn d -> Openings.rear_window(van, d) end

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
              if van.windows == :cargo,
                do: [],
                else:
                  Hull.shell(h, r0, d1, :glass_dark,
                    side: s,
                    thickness: 0.008,
                    offset: glass_out(),
                    step: 0.05,
                    clip: window
                  )

            handle = if s == 1, do: [Shape.box({0.05, -0.03, 1.12}, {0.2, -0.01, 1.16}, :black)], else: []
            panel ++ glass ++ handle
        end

      hinge = Kit.port("hinge", {s * hw, 0.0, 1.5}, {0, 0, s}, {0, 1, 0})

      door =
        Kit.part(@station, "rear_door_transit", :door, shapes, [hinge],
          sources: van.make["openings"]["sources"] |> Enum.slice(2, 1)
        )

      Assembly.add(asm, name, door, at: hinge, port: "hinge", kind: :hinge, role: :door, limits: [0, 180])
    end)
  end
end
