defmodule World.Service do
  @moduledoc """
  The HTTP service of the factory in the VM (`docs/factory.md`). The
  Worker (`worker.js`) gives it the orders that are not in its cache, and
  keeps the files in R2.

  - `GET /blueprints`: each blueprint with its options, as JSON.
  - `POST /check`: an order in the body. 200 with `{"hash", "order"}` (the
    full order), or 422 with `{"errors"}`.
  - `POST /build?level=near&file=glb`: an order in the body. 200 with the
    file (`World.Orders.files/0`: `glb`, `log`, `replay`, `parts` or
    `receipt`), or 422 with `{"errors"}`. The header `server-timing`
    has the time of the build in the VM (`build;dur=MS`), with no wait
    for the build before it.

  A body that is not JSON gives 400. A body of more than 1 MB gives 413.
  """
  use Plug.Router

  alias World.Orders
  alias World.Orders.{Blueprint, Blueprints}

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
