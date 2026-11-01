defmodule World.Places do
  @moduledoc """
  The places of the world (`docs/world.md`, "The places"): buildings at a
  position on the yard, in meters, in one flat frame.

  - A **warehouse** keeps stock (`World.Stock`). Its limit is the size of
    its store (`World.Store`): the memory of the VM, an R2 bucket, or the
    catalog of the release (`catalog/3`).
  - A **factory** makes one family of things: `:materials`, `:frames`,
    `:houses`, `:wheels`, `:seats`, `:openings`, `:vehicles`, `:appliances`,
    `:clothes`, `:people`.
  - A **supplier** gives a part that the world cannot make.
  - A **site** is where a delivery ends: a project of the owner.
  """
  alias World.{Stock, Store}

  @kinds [:warehouse, :factory, :supplier, :site]
  @families [:materials, :frames, :houses, :wheels, :seats, :openings, :vehicles, :appliances, :clothes, :people]

  defmodule Place do
    @moduledoc "A place: its name, its kind, its position `{x, y}` on the yard, its family (a factory) and its stock (a warehouse)."
    defstruct name: nil, kind: nil, at: {0.0, 0.0}, family: nil, stock: nil
  end

  @doc "The kinds of a place."
  def kinds, do: @kinds

  @doc "The families of things, one for each factory."
  def families, do: @families

  # The family of an assembly by its kind: the factory that makes it.
  @family_of_kind %{wheel: :wheels, seat: :seats, door: :openings, window: :openings, house: :houses}

  @doc """
  The family of an item: the factory that makes it (`:wheels` for a
  wheel, `:seats` for a seat or a bench, `:openings` for a door or a
  window, `:houses` for a house or a
  building of the world), or `nil` for an item that the factory of its
  parent makes.
  """
  def family_of(%World.Assembly{kind: kind}), do: Map.get(@family_of_kind, kind)
  def family_of(_item), do: nil

  @doc "A warehouse with the limit of its store, in bytes, and its store (the memory of the VM by default)."
  def warehouse(name, at, limit, store \\ Store.memory()),
    do: place(name, :warehouse, at, stock: Stock.new(limit, store))

  @doc """
  The catalog: a warehouse of the models of a release (the folder `dir`,
  `World.Store.release/1`). It is read only and always full.
  """
  def catalog(name, at, dir), do: place(name, :warehouse, at, stock: Stock.catalog(Store.release(dir)))

  @doc "A factory of a family of things."
  def factory(name, at, family) do
    unless family in @families, do: raise(ArgumentError, "no family of things #{inspect(family)}")
    place(name, :factory, at, family: family)
  end

  @doc "A supplier."
  def supplier(name, at), do: place(name, :supplier, at)

  @doc "The site of a customer."
  def site(name, at), do: place(name, :site, at)

  defp place(name, kind, {x, y}, fields \\ []) when is_binary(name) and is_number(x) and is_number(y),
    do: struct!(Place, [name: name, kind: kind, at: {x / 1, y / 1}] ++ fields)

  @doc "The straight distance between two places, in meters."
  def distance(%Place{at: {x0, y0}}, %Place{at: {x1, y1}}), do: :math.sqrt((x1 - x0) ** 2 + (y1 - y0) ** 2)
end
