defmodule GitGud.SmartHTTPBackend do
  @moduledoc """
  `Plug` providing support for Git server commands over HTTP.

  This plug handles following Git commands:

  * `git-receive-pack` - corresponding server-side command to `git push`.
  * `git-upload-pack` - corresponding server-side command to `git fetch`.

  A registered `GitGud.User` can authenticate over HTTP via *Basic Authentication*.
  This is only, required for commands requiring specific permissions (such as pushing commits and cloning private repos).

  See `GitGud.Authorization` for more details.
  """

  use Plug.Router

  import Base, only: [decode64: 1]
  import String, only: [split: 3]

  alias GitRekt.GitAgent
  alias GitRekt.WireProtocol

  alias GitGud.Auth
  alias GitGud.User
  alias GitGud.RepoQuery
  alias GitGud.RepoStorage

  alias GitGud.Authorization

  plug :basic_authentication
  plug :match
  plug :dispatch

  get "/info/refs" do
    if repo = RepoQuery.user_repo(conn.params["user_login"], conn.params["repo_name"]),
      do: git_info_refs(conn, repo, conn.params["service"]) || require_authentication(conn),
    else: send_resp(conn, :not_found, "Not found")
  end

  get "/HEAD" do
    if repo = RepoQuery.user_repo(conn.params["user_login"], conn.params["repo_name"]),
      do: git_head_ref(conn, repo) || require_authentication(conn),
    else: send_resp(conn, :not_found, "Not found")
  end

  post "/git-receive-pack" do
    if repo = RepoQuery.user_repo(conn.params["user_login"], conn.params["repo_name"]),
      do: git_pack(conn, repo, "git-receive-pack") || require_authentication(conn),
    else: send_resp(conn, :not_found, "Not found")
  end

  post "/git-upload-pack" do
    if repo = RepoQuery.user_repo(conn.params["user_login"], conn.params["repo_name"]),
      do: git_pack(conn, repo, "git-upload-pack") || require_authentication(conn),
    else: send_resp(conn, :not_found, "Not found")
  end

  match _ do
    send_resp(conn, :not_found, "Not Found")
  end

  #
  # Helpers
  #

  defp authorized?(conn, repo, "git-upload-pack"),  do: authorized?(conn, repo, :read)
  defp authorized?(conn, repo, "git-receive-pack"), do: authorized?(conn, repo, :write)
  defp authorized?(conn, repo, action), do: Authorization.authorized?(conn.assigns[:current_user], repo, action)

  defp basic_authentication(conn, _opts) do
    with ["Basic " <> auth] <- get_req_header(conn, "authorization"),
         {:ok, credentials} <- decode64(auth),
         [login, passwd] <- split(credentials, ":", parts: 2),
         %User{} = user <- Auth.check_credentials(login, passwd) do
      assign(conn, :current_user, user)
    else
      _ -> conn
    end
  end

  defp require_authentication(conn) do
    conn
    |> put_resp_header("www-authenticate", "Basic realm=\"GitGud\"")
    |> send_resp(:unauthorized, "Unauthorized")
    |> halt()
  end

  defp deflated?(conn), do: "gzip" in get_req_header(conn, "content-encoding")

  defp inflate_body(conn, body) do
    if deflated?(conn),
      do: :zlib.gunzip(body),
    else: body
  end

  defp read_body_full(conn, buffer \\ "") do
    case read_body(conn) do
      {:ok, body, conn} ->
        {:ok, inflate_body(conn, buffer <> body), conn}
      {:more, part, conn} ->
        read_body_full(conn, buffer <> part)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp git_info_refs(conn, repo, service) do
    if authorized?(conn, repo, service) do
      case GitAgent.attach(repo) do
        {:ok, repo} ->
          refs = WireProtocol.reference_discovery(repo, service)
          info = WireProtocol.encode(["# service=#{service}", :flush] ++ refs)
          conn
          |> put_resp_content_type("application/x-#{service}-advertisement")
          |> send_resp(:ok, info)
        {:error, _reason} ->
          conn
          |> send_resp(:not_found, "Not found")
          |> halt()
      end
    end
  end

  defp git_head_ref(conn, repo) do
    if authorized?(conn, repo, :read) do
      with {:ok, repo} <- GitAgent.attach(repo),
           {:ok, head} <- GitAgent.head(repo) do
        send_resp(conn, :ok, "ref: #{head.prefix <> head.name}")
      else
        {:error, reason} ->
          conn
          |> send_resp(:internal_server_error, reason)
          |> halt()
      end
    end
  end

  defp git_pack(conn, repo, service) do
    if authorized?(conn, repo, service) do
      with {:ok, body, conn} <- read_body_full(conn),
           {:ok, repo} <- GitAgent.attach(repo) do
        conn
        |> put_resp_content_type("application/x-#{service}-result")
        |> send_resp(:ok, git_exec(service, repo, body))
      else
        {:error, reason} ->
          conn
          |> send_resp(:internal_server_error, reason)
          |> halt()
      end
    end
  end

  defp git_exec(exec, repo, data) do
    repo.__agent__
    |> WireProtocol.new(exec, callback: {RepoStorage, :push, [repo]})
    |> WireProtocol.run(data, skip: 1)
    |> elem(1)
  end
end
