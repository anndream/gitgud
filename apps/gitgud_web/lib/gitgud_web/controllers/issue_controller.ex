defmodule GitGud.Web.IssueController do
  @moduledoc """
  Module responsible for CRUD actions on `GitGud.Issue`.
  """

  use GitGud.Web, :controller

  alias GitGud.User
  alias GitGud.RepoQuery
  alias GitGud.Issue
  alias GitGud.IssueQuery
  alias GitGud.Comment

  plug :ensure_authenticated when action in [:new, :create]
  plug :put_layout, :repo

  action_fallback GitGud.Web.FallbackController

  @spec index(Plug.Conn.t, map) :: Plug.Conn.t
  def index(conn, %{"user_login" => user_login, "repo_name" => repo_name} = _params) do
    if repo = RepoQuery.user_repo(user_login, repo_name, preload: [issues: :author], viewer: current_user(conn)) do
      render(conn, "index.html", repo: repo)
    end || {:error, :not_found}
  end

  @spec show(Plug.Conn.t, map) :: Plug.Conn.t
  def show(conn, %{"user_login" => user_login, "repo_name" => repo_name, "number" => issue_number} = _params) do
    if repo = RepoQuery.user_repo(user_login, repo_name, viewer: current_user(conn)) do
      if issue = IssueQuery.repo_issue(repo, String.to_integer(issue_number), viewer: current_user(conn)) do
        render(conn, "show.html", repo: repo, issue: issue)
      end
    end || {:error, :not_found}
  end

  @doc """
  Renders a repository creation form.
  """
  @spec new(Plug.Conn.t, map) :: Plug.Conn.t
  def new(conn, %{"user_login" => user_login, "repo_name" => repo_name} = _params) do
    user = current_user(conn)
    if repo = RepoQuery.user_repo(user_login, repo_name, viewer: current_user(conn)) do
      if User.verified?(user),
       do: render(conn, "new.html", repo: repo, changeset: Issue.changeset(%Issue{comments: [%Comment{}]})),
     else: {:error, :unauthorized}
    end || {:error, :not_found}
  end

  @doc """
  Creates a new repository.
  """
  @spec create(Plug.Conn.t, map) :: Plug.Conn.t
  def create(conn, %{"user_login" => user_login, "repo_name" => repo_name, "issue" => issue_params} = _params) do
    user = current_user(conn)
    if repo = RepoQuery.user_repo(user_login, repo_name, viewer: current_user(conn)) do
      if User.verified?(user) do
        case Issue.create(Map.merge(issue_params, %{"repo_id" => repo.id, "author_id" => user.id})) do
          {:ok, issue} ->
            conn
            |> put_flash(:info, "Issue ##{issue.number} created.")
            |> redirect(to: Routes.issue_path(conn, :show, user_login, repo_name, issue.number))
          {:error, changeset} ->
            conn
            |> put_flash(:error, "Something went wrong! Please check error(s) below.")
            |> put_status(:bad_request)
            |> render("new.html", repo: repo, changeset: %{changeset|action: :insert})
        end
      end || {:error, :unauthorized}
    end || {:error, :not_found}
  end
end
