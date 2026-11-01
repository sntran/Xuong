defmodule World.Vehicles.Van.Closures do
  @moduledoc """
  The second station of the line of a van (`World.Vehicles.Van`): the
  closures on their hinges and rails. The hood turns up at the front.
  The doors come from the openings factory (`World.Openings.Van`):
  each front door turns out on hinges at its front edge, with its window
  and its mirror; the sliding door at the right side slides back; the
  two rear doors turn out on hinges at their outer edges.
  """
  alias World.Assembly
  alias World.Vehicles.Hull
  alias World.Openings, as: Factory
  alias World.Vehicles.Van.Kit
  @station "closures"

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

  # --- The doors -------------------------------------------------------------------------

  # The doors come from the openings factory (`World.Openings.Van`):
  # each front door turns out on hinges at its front edge, the sliding
  # door slides back on its rail, the rear doors turn out on hinges at
  # their outer edges.
  defp front_doors(asm, van) do
    Enum.reduce([{"front_door_right", 1}, {"front_door_left", -1}], asm, fn {name, s}, asm ->
      Assembly.add(asm, name, Factory.Van.front(van, s),
        at: Factory.Van.front_hinge(van, s),
        port: "hinge",
        kind: :hinge,
        role: :door,
        limits: [0, 70]
      )
    end)
  end

  defp sliding_door(asm, van) do
    Assembly.add(asm, "sliding_door", Factory.Van.sliding(van),
      at: Factory.Van.slide(van),
      port: "slide",
      kind: :slide,
      role: :door,
      limits: [0, 1.25]
    )
  end

  defp rear_doors(asm, van) do
    Enum.reduce([{"rear_door_right", 1}, {"rear_door_left", -1}], asm, fn {name, s}, asm ->
      Assembly.add(asm, name, Factory.Van.rear(van, s),
        at: Factory.Van.rear_hinge(van, s),
        port: "hinge",
        kind: :hinge,
        role: :door,
        limits: [0, 180]
      )
    end)
  end
end
