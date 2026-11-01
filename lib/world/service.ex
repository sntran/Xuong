defmodule World.Service do
  @moduledoc """
  The HTTP service of the factory in the VM (`docs/factory.md`). The
  Worker (`worker.js`) gives it the orders that are not in its cache, and
  keeps the files in R2.

  - `GET /blueprints`: each blueprint with its options, as JSON.
  - `POST /check`: an order in the body. 200 with `{"hash", "order"}` (the
    full order), or 422 with `{"errors"}`.
  - `POST /orders`: an order in the body. The full order goes into the
    store of the orders (`World.Orders.place/2`): 200 with `{"hash",
    "order", "files", "replay"}`, 422 with `{"errors"}`, or 503 when the
    store failed.
  - `POST /build?level=near&file=glb`: an order in the body, or
    `&hash=HASH` with no body for an order of `POST /orders` (404 when
    the store has no order of the hash). 200 with the file
    (`World.Orders.files/0`: `glb`, `log`, `replay`, `parts` or
    `receipt`), or 422 with `{"errors"}`. The header `server-timing`
    has the time of the build in the VM (`build;dur=MS`), with no wait
    for the build before it.
  - `POST /mcp`: the MCP server (`World.MCP`). The other methods give
    405.

  A body that is not JSON gives 400. A body of more than 1 MB gives 413.
  The header `x-world-origin` (from the Worker) is the start of the URLs
  of an order: `https://world.mkfifo.com`.
  """
  use Plug.Router

  alias World.{MCP, Orders}
  alias World.Orders.{Blueprint, Blueprints, Store}

  plug(:match)
  plug(:dispatch)

  @types %{
    "glb" => "model/gltf-binary",
    "replay" => "model/gltf-binary",
    "log" => "application/json",
    "parts" => "application/json",
    "receipt" => "application/json"
  }

  get "/blueprints" do
    json(conn, 200, Enum.map(Blueprints.all(), &Blueprint.describe/1))
  end

  post "/check" do
    with_order(conn, fn order ->
      case Orders.check(order) do
        {:ok, full} -> json(conn, 200, %{"hash" => Orders.hash(full), "order" => full})
        {:error, errors} -> json(conn, 422, %{"errors" => errors})
      end
    end)
  end

  post "/orders" do
    with_order(conn, fn order ->
      case Orders.place(order, origin(conn)) do
        {:ok, placed} ->
          json(conn, 200, placed)

        {:error, :store} ->
          json(conn, 503, %{"errors" => [%{"path" => "", "message" => "the store of the orders failed"}]})

        {:error, errors} ->
          json(conn, 422, %{"errors" => errors})
      end
    end)
  end

  post "/mcp" do
    case read_body(conn, length: 1_000_000) do
      {:ok, body, conn} ->
        version = conn |> get_req_header("mcp-protocol-version") |> List.first()

        case MCP.answer(body, version, origin(conn)) do
          {202, nil} -> send_resp(conn, 202, "")
          {status, message} -> json(conn, status, message)
        end

      {:more, _, conn} ->
        json(conn, 413, %{
          "jsonrpc" => "2.0",
          "id" => nil,
          "error" => %{"code" => -32600, "message" => "the body is more than 1 MB"}
        })
    end
  end

  match "/mcp" do
    conn
    |> put_resp_header("allow", "POST")
    |> json(405, %{
      "jsonrpc" => "2.0",
      "id" => nil,
      "error" => %{"code" => -32000, "message" => "use POST: this server sends no event stream"}
    })
  end

  post "/build" do
    conn = fetch_query_params(conn)
    file = Map.get(conn.query_params, "file", "glb")
    level = Map.get(conn.query_params, "level", "near")

    with_order(conn, fn order ->
      case one_at_a_time(fn -> :timer.tc(Orders, :build, [order, level, file], :millisecond) end) do
        {ms, {:ok, out}} ->
          conn
          |> put_resp_header("server-timing", "build;dur=#{ms}")
          |> put_resp_content_type(Map.fetch!(@types, file), nil)
          |> send_resp(200, out)

        {_, {:error, errors}} ->
          json(conn, 422, %{"errors" => errors})
      end
    end)
  end

  match _ do
    json(conn, 404, %{"errors" => [%{"path" => "", "message" => "no such page"}]})
  end

  # One build at a time in the VM: the edge has 128 MB, and two builds of
  # a near level at one time need more. A second build waits for the lock
  # (`:global.trans/4` tries again until it has it).
  defp one_at_a_time(fun), do: :global.trans({__MODULE__, self()}, fun, [node()], :infinity)

  # The start of the URLs of an order: from the Worker, else this server.
  defp origin(conn) do
    case get_req_header(conn, "x-world-origin") do
      [origin | _] -> origin
      [] -> "#{conn.scheme}://#{conn.host}:#{conn.port}"
    end
  end

  # The order of a request: the full order of `hash=HASH` from the store,
  # else the JSON of the body.
  defp with_order(%{query_params: %{"hash" => hash}} = conn, fun) do
    with true <- hash =~ ~r/^[0-9a-f]{32}$/,
         {:ok, json} <- Store.get(hash) do
      fun.(JSON.decode!(json))
    else
      :error -> json(conn, 503, %{"errors" => [%{"path" => "", "message" => "the store of the orders failed"}]})
      _ -> json(conn, 404, %{"errors" => [%{"path" => "", "message" => "no such order: send it to POST /orders"}]})
    end
  end

  defp with_order(conn, fun) do
    case read_body(conn, length: 1_000_000) do
      {:ok, body, conn} ->
        case JSON.decode(body) do
          {:ok, order} -> fun.(order)
          {:error, _} -> json(conn, 400, %{"errors" => [%{"path" => "", "message" => "the body is not JSON"}]})
        end

      {:more, _, conn} ->
        json(conn, 413, %{"errors" => [%{"path" => "", "message" => "the body is more than 1 MB"}]})
    end
  end

  defp json(conn, status, body) do
    conn |> put_resp_content_type("application/json", nil) |> send_resp(status, Orders.encode(body))
  end
end
