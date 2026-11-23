defmodule TymeslotWeb.RdVisitInternal do
  @moduledoc """
  The internal listener for on-site appointments (Revision Dynamics,
  `rd-visit-service.patch`): `Tymeslot.RdVisit` for the website's server.

  A port of its own (`RD_VISIT_PORT`, default 4101) beside the public
  endpoint, never published on the host and never behind the reverse proxy:
  only containers on the internal Docker network reach it. Every request
  needs `Authorization: Bearer <RD_VISIT_SECRET>`; without a secret of at
  least 32 characters the listener does not start.

      GET  /visit/health   {"status": "ok"}
      POST /visit/busy     {"from": "2026-11-23", "to": "2026-11-30"}
                           -> {"events": [{"start", "end", "location"}]}
      POST /visit/book     see `Tymeslot.RdVisit.book/1`
                           -> 201 {"booked": true} | 409 {"error": "taken"}

  Bodies are JSON of at most 16 KB. Nothing a request carries is logged.
  """

  use Plug.Router

  alias Plug.Crypto
  alias Tymeslot.Infrastructure.Logging.LogFormat
  alias Tymeslot.RdVisit

  require Logger

  plug :authenticate
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason, length: 16_384
  plug :match
  plug :dispatch

  @doc "The listener as a child of the application, when a secret is set."
  @spec children() :: [Supervisor.child_spec()]
  def children do
    if RdVisit.secret() do
      port = String.to_integer(System.get_env("RD_VISIT_PORT") || "4101")

      [
        Supervisor.child_spec(
          {Bandit,
           plug: __MODULE__, scheme: :http, ip: bind_ip(), port: port, startup_log: false},
          id: :rd_visit_internal
        )
      ]
    else
      []
    end
  end

  defp bind_ip do
    case :inet.parse_address(String.to_charlist(System.get_env("RD_VISIT_BIND") || "0.0.0.0")) do
      {:ok, ip} -> ip
      _invalid -> {0, 0, 0, 0}
    end
  end

  get "/visit/health" do
    reply(conn, 200, %{status: "ok"})
  end

  post "/visit/busy" do
    with %{"from" => from, "to" => to} <- conn.body_params,
         {:ok, from} <- Date.from_iso8601(to_string(from)),
         {:ok, to} <- Date.from_iso8601(to_string(to)) do
      case RdVisit.busy(from, to) do
        {:ok, events} ->
          reply(conn, 200, %{
            events:
              Enum.map(events, fn event ->
                %{
                  start: DateTime.to_iso8601(event.start),
                  end: DateTime.to_iso8601(event.end),
                  location: event.location
                }
              end)
          })

        {:error, :invalid} ->
          reply(conn, 422, %{error: "invalid"})

        {:error, _reason} ->
          reply(conn, 503, %{error: "calendar"})
      end
    else
      _invalid -> reply(conn, 422, %{error: "invalid"})
    end
  end

  post "/visit/book" do
    case RdVisit.book(conn.body_params) do
      {:ok, _meeting} ->
        reply(conn, 201, %{booked: true})

      {:error, :taken} ->
        reply(conn, 409, %{error: "taken"})

      {:error, :invalid} ->
        reply(conn, 422, %{error: "invalid"})

      {:error, reason} ->
        Logger.warning("rd_visit: booking failed", reason: LogFormat.reason(reason))
        reply(conn, 503, %{error: "unavailable"})
    end
  end

  match _ do
    reply(conn, 404, %{error: "path"})
  end

  defp authenticate(conn, _opts) do
    expected = RdVisit.secret()

    given =
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token] -> token
        _missing -> ""
      end

    if is_binary(expected) and byte_size(given) == byte_size(expected) and
         Crypto.secure_compare(given, expected) do
      conn
    else
      conn |> reply(401, %{error: "auth"}) |> halt()
    end
  end

  defp reply(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, Jason.encode!(body))
  end
end
