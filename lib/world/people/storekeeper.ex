defmodule World.People.Storekeeper do
  @moduledoc """
  A storekeeper (`World.People.Person`, job `:storekeeper`) as a process:
  the stock of one warehouse (`World.Stock`). The storekeeper takes the
  parts from a supplier into the store, picks them out of the store to
  the dock of the warehouse, and puts the files of a finished model into
  the store. Each act is an event of the log.
  """
  use GenServer

  alias World.Log.Server
  alias World.Stock

  @doc """
  Start a storekeeper. The options: `name` (the person), `place` (the
  warehouse), `stock` (`World.Stock`), `log` (a `World.Log.Server`).
  """
  def start_link(opts), do: GenServer.start_link(__MODULE__, Map.new(opts))

  @doc "Check the stock for the needs of an order (`%{item => count}`): the count to get of each item."
  def check(sk, order, needs), do: GenServer.call(sk, {:check, order, needs})

  @doc "Take `n` items of `bytes` each from a supplier into the store: `:ok`, or `{:error, :full}`."
  def supply(sk, order, supplier, item, n, bytes), do: GenServer.call(sk, {:supply, order, supplier, item, n, bytes})

  @doc "Pick `n` items out of the store, to the dock of the warehouse: `:ok`, or `{:error, :missing}`."
  def pick(sk, order, item, n), do: GenServer.call(sk, {:pick, order, item, n})

  @doc "Put the files of a model into the store: `:ok`, or `{:error, :full}`."
  def store_model(sk, order, name, bytes), do: GenServer.call(sk, {:model, order, name, bytes})

  @doc "The stock now."
  def stock(sk), do: GenServer.call(sk, :stock)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:check, order, needs}, _from, s) do
    missing = Map.new(needs, fn {item, n} -> {item, max(n - Stock.count(s.stock, item), 0)} end)
    record(s, "stock_checked", order, %{"missing" => missing})
    {:reply, missing, s}
  end

  def handle_call({:supply, order, supplier, item, n, bytes}, _from, s) do
    case Stock.put(s.stock, item, n, bytes) do
      {:ok, stock} ->
        s = %{s | stock: stock}
        record(s, "stored", order, %{"item" => item, "count" => n, "from" => supplier})
        {:reply, :ok, s}

      {:error, reason} ->
        record(s, "refused", order, %{"item" => item, "count" => n, "reason" => Atom.to_string(reason)})
        {:reply, {:error, reason}, s}
    end
  end

  def handle_call({:pick, order, item, n}, _from, s) do
    case Stock.take(s.stock, item, n) do
      {:ok, stock} ->
        s = %{s | stock: stock}
        record(s, "picked", order, %{"item" => item, "count" => n})
        {:reply, :ok, s}

      error ->
        {:reply, error, s}
    end
  end

  def handle_call({:model, order, name, bytes}, _from, s) do
    case Stock.put(s.stock, name, 1, bytes) do
      {:ok, stock} ->
        s = %{s | stock: stock}
        record(s, "stored", order, %{"model" => name, "bytes" => bytes})
        {:reply, :ok, s}

      {:error, reason} ->
        record(s, "refused", order, %{"model" => name, "bytes" => bytes, "reason" => Atom.to_string(reason)})
        {:reply, {:error, reason}, s}
    end
  end

  def handle_call(:stock, _from, s), do: {:reply, s.stock, s}

  # Each event of a storekeeper tells how full the store is after it: the
  # racks of the warehouse show it.
  defp record(s, kind, order, data),
    do:
      Server.record(s.log, kind,
        order: order,
        place: s.place,
        who: s.name,
        data: Map.merge(data, %{"used" => Stock.used(s.stock), "limit" => s.stock.limit})
      )
end
