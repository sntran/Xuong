defmodule World.Orders.Store do
  @moduledoc """
  The store of the full orders (`orders/HASH.json`), so that
  `/o/HASH.glb` can build the files of an order later: a port program
  with the code of `order_store.js`.

  - At the edge, the program is the binding `ORDER_STORE` of the object
    of the VM (`/env/ORDER_STORE`, BEAM.com "Ports to bindings"), with
    the R2 bucket `ORDERS`. `wrangler.jsonc` gives its path in
    `WORLD_ORDER_STORE`.
  - On this computer and in the tests, the program is
    `scripts/order-store.mjs`, with a folder in place of the bucket
    (`WORLD_ORDER_DIR`, `tmp/orders` by default).

  The keys `program`, `dir` and `timeout` of the application environment
  of `:world` for this module come before these defaults.
  """

  @script Path.expand("../../../scripts/order-store.mjs", __DIR__)

  @doc "The key of the full order of a hash."
  def key(hash), do: "orders/#{hash}.json"

  @doc "Puts the full order (its JSON) of a hash in the store."
  @spec put(String.t(), binary()) :: :ok | :error
  def put(hash, json) when byte_size(json) > 0 do
    case run(["put", key(hash), "#{byte_size(json)}"], json) do
      {:ok, "ok\n"} -> :ok
      _ -> :error
    end
  end

  @doc """
  The full order (its JSON) of a hash: `:none` when the store has no
  order of the hash, `:error` when the store failed.
  """
  @spec get(String.t()) :: {:ok, binary()} | :none | :error
  def get(hash) do
    case run(["get", key(hash)], "") do
      {:ok, ""} -> :none
      other -> other
    end
  end

  defp run(args, input) do
    with {:ok, port} <- open(args) do
      # A monitor in place of the link, so that this process (a request)
      # does not end with the port. A message, not Port.command/2: a
      # program that ended takes no input, and its exit status tells it.
      Process.unlink(port)
      ref = Port.monitor(port)
      if input != "", do: send(port, {self(), {:command, input}})
      result = collect(port, ref, [], nil)
      Port.demonitor(ref, [:flush])
      result
    end
  end

  defp open(args) do
    env = [{~c"WORLD_ORDER_DIR", ~c"#{config(:dir)}"}]
    {:ok, Port.open({:spawn_executable, config(:program)}, [:binary, :exit_status, args: args, env: env])}
  rescue
    ErlangError -> :error
  end

  # The output of the program until its port ends: the exit status comes
  # before the end, and a port that ends with no exit status is an error.
  defp collect(port, ref, data, status) do
    receive do
      {^port, {:data, part}} -> collect(port, ref, [data | part], status)
      {^port, {:exit_status, code}} -> collect(port, ref, data, code)
      {:DOWN, ^ref, :port, ^port, _} -> if status == 0, do: {:ok, IO.iodata_to_binary(data)}, else: :error
    after
      config(:timeout) ->
        Port.close(port)
        :error
    end
  end

  defp config(key), do: Keyword.get(Application.get_env(:world, __MODULE__, []), key, default(key))

  defp default(:program), do: System.get_env("WORLD_ORDER_STORE", @script)
  defp default(:dir), do: System.get_env("WORLD_ORDER_DIR", "tmp/orders")
  defp default(:timeout), do: 30_000
end
