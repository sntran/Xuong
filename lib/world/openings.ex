defmodule World.Openings do
  @moduledoc """
  The openings factory (`docs/world.md`, "The factories"): it makes the
  doors and the windows of all kinds, each an assembly of the kind
  `:door` or `:window` (`World.Places.family_of/1`). So the factory of a
  house or of a vehicle orders its doors and its windows here, and the
  truck of the openings factory brings them.

  - The prehung door of a building: a frame of jambs, the slab on its
    hinges, and a knob (`prehung/4`).
  - The window of a building: a frame of vinyl, and a casement sash or a
    fixed pane (`window/5`).
  - The doors and the windows of a van, to the numbers of the order of
    the van (`World.Openings.Van`).
  """
  alias World.{Assembly, Kit, Part, Shape, Vec}
  alias World.Materials.Construction
  import Kit, only: [inch: 1, same: 4]

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  @doc """
  A prehung door of `w` by `h` (the slab) for a wall of `depth`: a frame
  of jambs, the slab on three hinges, and a knob. Its origin is at the
  bottom left of the rough opening, on the outside face of the wall; it
  opens to the inside (+y).
  """
  def prehung(name, w, h, depth) do
    j = inch(0.75)
    {ro_w, ro_h} = {w + 2 * j + 0.012, h + j + 0.012}
    x0 = j + 0.006
    slab_t = inch(1.75)
    y_in = depth - 0.01

    frame =
      [
        Shape.box({0.006, 0.0, 0.0}, {x0, depth, h + 0.003}, :white),
        Shape.box({x0 + w, 0.0, 0.0}, {x0 + w + j, depth, h + 0.003}, :white),
        Shape.box({0.006, 0.0, h + 0.003}, {x0 + w + j, depth, h + 0.003 + j}, :white),
        # The stops: strips on the jambs and the head, on the outside of the slab.
        Shape.box({x0, y_in - slab_t - 0.013, 0.0}, {x0 + 0.012, y_in - slab_t - 0.003, h}, :white),
        Shape.box({x0 + w - 0.012, y_in - slab_t - 0.013, 0.0}, {x0 + w, y_in - slab_t - 0.003, h}, :white),
        Shape.box({x0, y_in - slab_t - 0.013, h - 0.012}, {x0 + w, y_in - slab_t - 0.003, h}, :white)
      ]

    hinge_at = {x0, y_in, 0.0}

    slab =
      Part.new(
        "door_slab_#{round(w / 0.0254)}x#{round(h / 0.0254)}",
        :door,
        [
          Shape.box({x0 + 0.003, y_in - slab_t, 0.005}, {x0 + w - 0.003, y_in, h - 0.015}, :wood),
          Shape.box({x0 + 0.08, y_in - slab_t - 0.004, h * 0.55}, {x0 + w - 0.08, y_in - slab_t, h - 0.1}, :wood),
          Shape.box({x0 + 0.08, y_in - slab_t - 0.004, 0.1}, {x0 + w - 0.08, y_in - slab_t, h * 0.5}, :wood)
        ],
        [same("hinge", hinge_at, {0, 0, 1}, {0, 1, 0})],
        sources: ["A door slab of #{round(w / 0.0254)} by #{round(h / 0.0254)} in, 1 3/4 in thick."]
      )

    knob_at = {x0 + w - 0.065, y_in, 0.914}
    knob = %{Kit.knob("knob_#{name}", knob_at, {0, 1, 0}, {0, 0, 1}, 0.028, 0.06) | name: "door_knob"}

    hinges =
      for {z, k} <- Enum.with_index([0.18, h / 2, h - 0.27], 1),
          do:
            {"hinge_#{name}_#{k}", Construction.hinge(),
             [at: Part.port("hinge_#{name}_#{k}", Vec.add(hinge_at, {0.0, 0.0, z}), {0, 0, 1}, {0, 1, 0}), port: "pin"]}

    Assembly.new(
      name,
      Part.new("door_frame_#{round(w / 0.0254)}x#{round(h / 0.0254)}", :frame, frame, [@o],
        params: %{"rough_opening" => [ro_w, ro_h]}
      ),
      root: "frame",
      kind: :door,
      sources: [
        "A prehung door: a slab of #{round(w / 0.0254)} by #{round(h / 0.0254)} in, jambs of 3/4 in, three hinges of 3 1/2 in."
      ]
    )
    |> Assembly.add("slab_" <> name, slab,
      at: Kit.same("hinge", hinge_at, {0, 0, 1}, {0, 1, 0}),
      port: "hinge",
      kind: :hinge,
      role: :door,
      limits: [0, 100]
    )
    |> Assembly.add_all(hinges)
    |> Assembly.add("knob_#{name}", knob,
      to: "slab_" <> name,
      at: Kit.same("knob_#{name}", knob_at, {0, 1, 0}, {0, 0, 1}),
      port: "knob_#{name}",
      kind: :hinge,
      role: :knob,
      limits: [0, 60]
    )
  end

  @doc "The rough opening of a prehung door: `{width, height}`."
  def prehung_opening(w, h), do: {w + 2 * inch(0.75) + 0.012, h + inch(0.75) + 0.012}

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

  @doc "A prehung door of 36 by 80 in, for a wall of 2x4 with its sheathing (4 1/2 in)."
  def prehung_sample, do: prehung("door_prehung_36x80", inch(36), inch(80), inch(4.5))

  @doc "A casement window of 36 by 48 in (the rough opening), for a wall of 2x4."
  def window_sample, do: window("window_casement_36x48", inch(36), inch(48), inch(4.5))
end
