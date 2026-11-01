defmodule World.MCPTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias World.MCP

  @origin "https://world.mkfifo.com"
  @strut %{"blueprint" => "strut", "options" => %{"length" => 0.3}}

  defp rpc(method, params \\ nil, version \\ nil) do
    message = %{"jsonrpc" => "2.0", "id" => 7, "method" => method}
    message = if params, do: Map.put(message, "params", params), else: message
    MCP.answer(JSON.encode!(message), version, @origin)
  end

  defp tool(name, args) do
    {200, %{"id" => 7, "result" => result}} = rpc("tools/call", %{"name" => name, "arguments" => args})
    result
  end

  test "initialize gives the version of the client when the server knows it, else the newest" do
    {200, %{"jsonrpc" => "2.0", "id" => 7, "result" => r}} = rpc("initialize", %{"protocolVersion" => "2025-06-18"})
    assert r["protocolVersion"] == "2025-06-18"
    assert r["capabilities"] == %{"tools" => %{"listChanged" => false}}
    assert r["serverInfo"]["name"] == "world"
    assert r["serverInfo"]["version"] == to_string(Application.spec(:world, :vsn))
    assert r["instructions"] =~ "place_order"

    {200, %{"result" => newer}} = rpc("initialize", %{"protocolVersion" => "2099-01-01"})
    assert newer["protocolVersion"] == hd(MCP.versions())
    {200, %{"result" => none}} = rpc("initialize")
    assert none["protocolVersion"] == hd(MCP.versions())
  end

  test "ping, and the list of the tools" do
    assert {200, %{"result" => %{}}} = rpc("ping")
    {200, %{"result" => %{"tools" => tools}}} = rpc("tools/list", %{})
    assert Enum.map(tools, & &1["name"]) == ~w(list_blueprints get_blueprint check_order place_order)
    for t <- tools, do: assert(t["inputSchema"]["type"] == "object" and is_binary(t["description"]))
    assert tools == MCP.tools()
  end

  test "list_blueprints gives the name and the description of each blueprint" do
    r = tool("list_blueprints", %{})
    names = Enum.map(r["structuredContent"]["blueprints"], & &1["name"])
    assert "van" in names and "person" in names
    assert JSON.decode!(hd(r["content"])["text"]) == r["structuredContent"]
    refute Map.has_key?(r, "isError")
  end

  test "get_blueprint gives the options of one blueprint, or the names of the blueprints" do
    van = tool("get_blueprint", %{"name" => "van"})["structuredContent"]
    assert "windows" in Enum.map(van["options"], & &1["name"])

    wrong = tool("get_blueprint", %{"name" => "ball"})
    assert wrong["isError"] == true
    assert [%{"message" => "no blueprint ball; the blueprints are " <> _}] = wrong["structuredContent"]["errors"]

    # Arguments that are not an object are no arguments.
    assert tool("get_blueprint", [1])["isError"] == true
  end

  test "check_order gives the full order, or the errors with their paths" do
    r = tool("check_order", %{"order" => @strut})["structuredContent"]
    assert r["order"]["options"]["kind"] == "slotted"
    assert r["hash"] =~ ~r/^[0-9a-f]{32}$/

    wrong = tool("check_order", %{"order" => %{"blueprint" => "strut"}})
    assert wrong["isError"] == true
    assert [%{"path" => "options.length"}] = wrong["structuredContent"]["errors"]
  end

  test "place_order keeps the order and gives the URLs of its files; the build of its hash reads it" do
    r = tool("place_order", %{"order" => @strut})["structuredContent"]
    hash = r["hash"]
    assert r["files"]["glb"] == "#{@origin}/o/#{hash}.glb"
    assert r["files"]["far.glb"] == "#{@origin}/o/#{hash}.far.glb"
    assert r["files"]["log.json"] == "#{@origin}/o/#{hash}.log.json"
    assert r["replay"] == "#{@origin}/replay.html?order=#{hash}"
    assert World.Orders.Store.get(hash) == {:ok, World.Orders.encode(r["order"])}

    glb = conn(:post, "/build?level=far&hash=#{hash}", "") |> World.Service.call(World.Service.init([]))
    assert <<"glTF", _::binary>> = glb.resp_body

    assert tool("place_order", %{"order" => %{"blueprint" => "ball"}})["isError"] == true
  end

  test "an order that is not a JSON object is a tool error" do
    for args <- [%{}, %{"order" => nil}, %{"order" => "strut"}, %{"order" => [1]}] do
      r = tool("place_order", args)
      assert r["isError"] == true
      assert hd(r["content"])["text"] =~ "must be a JSON object"
    end
  end

  test "the errors of the protocol" do
    assert {200, %{"id" => 7, "error" => %{"code" => -32601, "message" => "no method resources/list"}}} =
             rpc("resources/list")

    {200, %{"error" => e}} = rpc("tools/call", %{"name" => "build_house"})
    assert e["code"] == -32602
    assert e["message"] =~ "the tools are list_blueprints, get_blueprint, check_order, place_order"
    assert {200, %{"error" => %{"code" => -32602}}} = rpc("tools/call", "x")

    assert {400, %{"error" => %{"code" => -32700}}} = MCP.answer("nope", nil, @origin)

    for body <- [~s([{"jsonrpc":"2.0","id":1,"method":"ping"}]), ~s({"id":1,"method":"ping"}), "null"],
        do: assert({400, %{"error" => %{"code" => -32600}}} = MCP.answer(body, nil, @origin))

    {400, %{"error" => %{"message" => message}}} = rpc("ping", nil, "1999-01-01")
    assert message =~ "1999-01-01 is not known"
    assert {200, _} = rpc("ping", nil, "2025-06-18")
  end

  test "a notification or a response of the client gets 202 with no body" do
    assert MCP.answer(~s({"jsonrpc":"2.0","method":"notifications/initialized"}), nil, @origin) == {202, nil}
    assert MCP.answer(~s({"jsonrpc":"2.0","id":3,"result":{}}), nil, @origin) == {202, nil}
  end
end
