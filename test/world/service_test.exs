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
