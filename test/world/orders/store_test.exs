defmodule World.Orders.StoreTest do
  # Not async: the tests change the program of the store in the
  # environment of the application.
  use ExUnit.Case, async: false
  import Plug.Test

  alias World.Orders.Store

  @hash "00000000000000000000000000000abc"

  setup do
    on_exit(fn -> Application.delete_env(:world, Store) end)
  end

  defp with_store(opts), do: Application.put_env(:world, Store, opts)

  test "an order goes into the folder of the store, and comes back", %{} do
    dir = Path.join(System.tmp_dir!(), "world-store-#{System.unique_integer([:positive])}")
    with_store(dir: dir)
    assert Store.get(@hash) == :none
    assert Store.put(@hash, ~s({"blueprint":"strut"})) == :ok
    assert File.read!(Path.join(dir, Store.key(@hash))) == ~s({"blueprint":"strut"})
    assert Store.get(@hash) == {:ok, ~s({"blueprint":"strut"})}
    File.rm_rf!(dir)
  end

  test "a store that is not there, that fails or that does not answer gives :error", %{} do
    with_store(program: "/no/such/program")
    assert Store.put(@hash, "{}") == :error
    assert Store.get(@hash) == :error

    with_store(program: "/bin/false")
    assert Store.put(@hash, "{}") == :error
    assert Store.get(@hash) == :error

    # A wrong key: the program refuses it with the exit status 1.
    with_store([])
    assert Store.get("../x") == :error
  end

  @tag :tmp_dir
  test "a store that does not answer in its time gives :error", %{tmp_dir: tmp} do
    slow = Path.join(tmp, "slow.sh")
    File.write!(slow, "#!/bin/sh\nsleep 5\n")
    File.chmod!(slow, 0o755)
    with_store(program: slow, timeout: 100)
    assert Store.get(@hash) == :error
  end

  test "a store that fails: POST /orders, the build of a hash and place_order tell it" do
    with_store(program: "/bin/false")
    service = fn method, path, body -> conn(method, path, body) |> World.Service.call(World.Service.init([])) end

    placed = service.(:post, "/orders", ~s({"blueprint": "strut", "options": {"length": 0.3}}))
    assert placed.status == 503
    assert JSON.decode!(placed.resp_body)["errors"] == [%{"path" => "", "message" => "the store of the orders failed"}]

    assert service.(:post, "/build?hash=#{@hash}", "").status == 503

    call =
      ~s({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"place_order","arguments":{"order":{"blueprint":"strut","options":{"length":0.3}}}}})

    {200, %{"result" => result}} = World.MCP.answer(call, nil, "https://world.mkfifo.com")
    assert result["isError"] == true
    assert [%{"message" => "the store of the orders failed; try again later"}] = result["structuredContent"]["errors"]
  end
end
