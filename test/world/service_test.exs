defmodule World.ServiceTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias World.Service

  defp call(method, path, body \\ nil) do
    conn(method, path, body) |> Service.call(Service.init([]))
  end

  defp json(conn), do: JSON.decode!(conn.resp_body)

  @strut ~s({"blueprint": "strut", "options": {"length": 0.3}})

  test "GET /blueprints" do
    conn = call(:get, "/blueprints")
    assert conn.status == 200
    assert "house" in Enum.map(json(conn), & &1["name"])
  end

  test "POST /check" do
    conn = call(:post, "/check", @strut)
    assert conn.status == 200
    assert %{"hash" => _, "order" => %{"options" => %{"kind" => "slotted", "length" => 0.3}}} = json(conn)

    conn = call(:post, "/check", ~s({"blueprint": "strut"}))
    assert conn.status == 422
    assert [%{"path" => "options.length"}] = json(conn)["errors"]

    assert call(:post, "/check", "nope").status == 400
    assert call(:post, "/check", String.duplicate(" ", 1_100_000)).status == 413
  end

  test "POST /build: each file, and the errors" do
    glb = call(:post, "/build?level=far", @strut)
    assert glb.status == 200
    assert <<"glTF", _::binary>> = glb.resp_body
    assert Plug.Conn.get_resp_header(glb, "content-type") == ["model/gltf-binary"]

    receipt = call(:post, "/build?level=far&file=receipt", @strut)
    assert json(receipt)["level"] == "far"
    assert json(call(:post, "/build?level=far&file=parts", @strut))["parts"] != []

    log = call(:post, "/build?level=far&file=log", @strut)
    assert Plug.Conn.get_resp_header(log, "content-type") == ["application/json"]
    assert {:ok, _} = World.Log.from_json(log.resp_body)

    replay = call(:post, "/build?level=far&file=replay", @strut)
    assert Plug.Conn.get_resp_header(replay, "content-type") == ["model/gltf-binary"]
    assert <<"glTF", _::binary>> = replay.resp_body

    assert [%{"path" => "file", "message" => "must be one of: glb, log, replay, parts, receipt"}] =
             json(call(:post, "/build?file=zip", @strut))["errors"]

    assert [%{"path" => "level"}] = json(call(:post, "/build?level=huge", @strut))["errors"]
  end

  test "an order of Phượt (a traveler) gives its files and its log, and the times agree" do
    order = ~s({"blueprint": "traveler", "options": {"vehicle": "motorbike"}})
    assert <<"glTF", _::binary>> = call(:post, "/build?level=far", order).resp_body

    log = call(:post, "/build?level=far&file=log", order)
    assert ["build;dur=" <> ms] = Plug.Conn.get_resp_header(log, "server-timing")
    {:ok, l} = World.Log.from_json(log.resp_body)
    assert World.Log.check(l) == :ok
    events = World.Log.events(l)
    first = hd(events)
    delivered = Enum.find(events, &(&1.kind == "delivered"))

    # The run is in the time of the build in the service, and the events
    # of the order are in the time of the run.
    assert %{kind: "run_done", data: %{"ms" => run, "memory_peak" => peak, "memory_end" => memory}} = List.last(events)
    assert run <= String.to_integer(ms)
    assert delivered.wall - first.wall <= run
    assert peak >= memory and memory > 0
    assert List.last(events).data["memory"] == "total"
  end

  test "two builds at one time: the second waits for the first, and each gives its file" do
    builds =
      for length <- [0.3, 0.4],
          do:
            Task.async(fn ->
              call(:post, "/build?level=far", ~s({"blueprint": "strut", "options": {"length": #{length}}}))
            end)

    assert [%{status: 200}, %{status: 200}] = Task.await_many(builds, 60_000)
  end

  test "POST /orders keeps the full order and gives the URLs of its files, from x-world-origin" do
    conn =
      conn(:post, "/orders", @strut)
      |> Plug.Conn.put_req_header("x-world-origin", "https://world.mkfifo.com")
      |> Service.call(Service.init([]))

    assert conn.status == 200
    %{"hash" => hash, "files" => files, "replay" => replay} = json(conn)
    assert files["mid.glb"] == "https://world.mkfifo.com/o/#{hash}.mid.glb"
    assert replay == "https://world.mkfifo.com/replay.html?order=#{hash}"

    # With no x-world-origin, the URLs start with this server.
    assert json(call(:post, "/orders", @strut))["files"]["glb"] == "http://www.example.com:80/o/#{hash}.glb"

    assert call(:post, "/orders", ~s({"blueprint": "strut"})).status == 422
    assert call(:post, "/orders", "nope").status == 400
  end

  test "POST /build of a hash: 404 for an order that is not in the store, or for a wrong hash" do
    assert json(call(:post, "/build?hash=ffffffffffffffffffffffffffffffff", ""))["errors"] ==
             [%{"path" => "", "message" => "no such order: send it to POST /orders"}]

    assert call(:post, "/build?hash=../../x", "").status == 404
  end

  test "/mcp: one JSON-RPC message for each POST, 202 for a notification, 405 for the other methods" do
    ping = ~s({"jsonrpc":"2.0","id":1,"method":"ping"})
    conn = call(:post, "/mcp", ping)
    assert conn.status == 200
    assert json(conn) == %{"jsonrpc" => "2.0", "id" => 1, "result" => %{}}
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["application/json"]

    old =
      conn(:post, "/mcp", ping)
      |> Plug.Conn.put_req_header("mcp-protocol-version", "1999-01-01")
      |> Service.call(Service.init([]))

    assert old.status == 400

    notified = call(:post, "/mcp", ~s({"jsonrpc":"2.0","method":"notifications/initialized"}))
    assert {notified.status, notified.resp_body} == {202, ""}

    assert call(:post, "/mcp", String.duplicate(" ", 1_100_000)).status == 413

    for method <- [:get, :delete] do
      conn = call(method, "/mcp")
      assert conn.status == 405
      assert Plug.Conn.get_resp_header(conn, "allow") == ["POST"]
    end
  end

  test "a page that is not there" do
    assert call(:get, "/nope").status == 404
  end

  test "the application starts the server only with WORLD_SERVER" do
    assert World.Application.children(%{}) == []
    [{Bandit, opts}] = World.Application.children(%{"WORLD_SERVER" => "true", "PORT" => "4100"})
    assert opts[:plug] == Service and opts[:port] == 4100
    [{Bandit, opts}] = World.Application.children(%{"WORLD_SERVER" => "true"})
    assert opts[:port] == 4000
  end
end
