defmodule PlausibleWeb.Api.SystemController do
  use Plausible
  use PlausibleWeb, :controller
  require Logger

  def info(conn, _params) do
    build =
      :plausible
      |> Application.get_env(:runtime_metadata)
      |> Keyword.take([:version, :commit, :created, :tags])
      |> Map.new()

    geo_database = Plausible.Geo.database_type() || "(not configured)"

    json(conn, %{
      geo_database: geo_database,
      build: build
    })
  end

  def liveness(conn, _params) do
    json(conn, %{ok: true})
  end

  def api_docs(conn, _params) do
    json(conn, %{
      endpoints: [
        %{
          method: "GET",
          path: "/health",
          purpose: "Returns HTTP 200 when the app is ready for Hugging Face Space transition from starting to running."
        },
        %{
          method: "GET",
          path: "/api-docs",
          purpose: "Exposes documentation of all available API endpoints."
        },
        %{
          method: "POST",
          path: "/api/event",
          purpose: "Send analytical events directly via the API."
        },
        %{
          method: "GET",
          path: "/api/v1/stats/realtime/visitors",
          purpose: "Get current number of active visitors on a site."
        },
        %{
          method: "GET",
          path: "/api/v1/stats/aggregate",
          purpose: "Retrieve aggregate metrics over a given period."
        },
        %{
          method: "GET",
          path: "/api/v1/stats/breakdown",
          purpose: "Break down stats by metrics like browser, country, etc."
        },
        %{
          method: "GET",
          path: "/api/v1/stats/timeseries",
          purpose: "Get metrics over time at regular intervals."
        }
      ]
    })
  end

  @task_timeout 15_000
  @critical_caches [
    Plausible.Site.Cache,
    Plausible.Shield.IPRuleCache,
    on_ee do
      Plausible.Site.TrackerScriptIdCache
    else
      Plausible.Site.TrackerScriptCache
    end
  ]

  def readiness(conn, _params) do
    postgres_health_task =
      Task.async(fn ->
        Ecto.Adapters.SQL.query(Plausible.Repo, "SELECT 1", [])
      end)

    clickhouse_health_task =
      Task.async(fn ->
        Ecto.Adapters.SQL.query(Plausible.ClickhouseRepo, "SELECT 1", [])
      end)

    postgres_health =
      case Task.await(postgres_health_task, @task_timeout) do
        {:ok, _} ->
          "ok"

        e ->
          Logger.error("Postgres health check failure: #{inspect(e)}")
          "error"
      end

    clickhouse_health =
      case Task.await(clickhouse_health_task, @task_timeout) do
        {:ok, _} ->
          "ok"

        e ->
          Logger.error("Clickhouse health check failure: #{inspect(e)}")
          "error"
      end

    cache_health =
      if postgres_health == "ok" and Enum.all?(@critical_caches, & &1.ready?()) do
        "ok"
      end

    sessions_health =
      if Plausible.Session.Transfer.attempted?() do
        "ok"
      else
        "waiting"
      end

    status =
      case {postgres_health, clickhouse_health, cache_health, sessions_health} do
        {"ok", "ok", "ok", "ok"} -> 200
        _ -> 500
      end

    put_status(conn, status)
    |> json(%{
      postgres: postgres_health,
      clickhouse: clickhouse_health,
      sites_cache: cache_health,
      sessions: sessions_health
    })
  end
end
