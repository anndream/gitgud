defmodule GitGud.Commit do
  @moduledoc """
  Git commit schema and helper functions.
  """
  use Ecto.Schema

  alias GitRekt.Git

  alias GitGud.Repo
  alias GitGud.GPGKey

  @primary_key false
  schema "commits" do
    belongs_to :repo, Repo, primary_key: true
    field :oid, :binary, primary_key: true
    field :parents, {:array, :binary}
    field :message, :string
    field :author_name, :string
    field :author_email, :string
    field :committer_name, :string
    field :committer_email, :string
    field :gpg_key_id, :binary
    field :committed_at, :naive_datetime
  end

  @type t :: %__MODULE__{
    repo_id: pos_integer,
    repo: Repo.t,
    oid: Git.oid,
    parents: [Git.oid],
    message: binary,
    author_name: binary,
    author_email: binary,
    committer_name: binary,
    committer_email: binary,
    gpg_key_id: binary,
    committed_at: NaiveDateTime.t
  }

  @doc """
  Decodes the given *RAW* commit `data`.
  """
  @spec decode!(binary) :: map
  def decode!(data) do
    commit = extract_commit_props(data)
    author = extract_commit_author(commit)
    committer = extract_commit_committer(commit)
    %{
      parents: extract_commit_parents(commit),
      message: strip_utf8(commit["message"]),
      author_name: strip_utf8(author["name"]),
      author_email: strip_utf8(author["email"]),
      committer_name: strip_utf8(committer["name"]),
      committer_email: strip_utf8(committer["email"]),
      gpg_key_id: extract_commit_gpg_key_id(commit),
      committed_at: author["time"],
    }
  end

  #
  # Helpers
  #

  defp extract_commit_props(data) do
    [header, message] = String.split(data, "\n\n", parts: 2)
    header
    |> String.split("\n", trim: true)
    |> Enum.chunk_by(&String.starts_with?(&1, " "))
    |> Enum.chunk_every(2)
    |> Enum.flat_map(fn
      [one] -> one
      [one, two] ->
        two = Enum.join(Enum.map(two, &String.trim_leading/1), "\n")
        List.update_at(one, -1, &Enum.join([&1, two], "\n"))
    end)
    |> Enum.map(fn line ->
      [key, val] = String.split(line, " ", parts: 2)
      {key, String.trim_trailing(val)}
    end)
    |> List.insert_at(0, {"message", message})
    |> Enum.reduce(%{}, fn {key, val}, acc -> Map.update(acc, key, val, &(List.wrap(val) ++ [&1])) end)
  end

  defp extract_commit_parents(commit) do
    Enum.map(List.wrap(commit["parent"] || []), &Git.oid_parse/1)
  end

  defp extract_commit_author(commit) do
    ~r/^(?<name>.+) <(?<email>.+)> (?<time>[0-9]+) (?<time_offset>[-\+][0-9]{4})$/
    |> Regex.named_captures(commit["author"])
    |> Map.update!("time", &DateTime.to_naive(DateTime.from_unix!(String.to_integer(&1))))
  end

  defp extract_commit_committer(commit) do
    ~r/^(?<name>.+) <(?<email>.+)> (?<time>[0-9]+) (?<time_offset>[-\+][0-9]{4})$/
    |> Regex.named_captures(commit["committer"])
    |> Map.update!("time", &DateTime.to_naive(DateTime.from_unix!(String.to_integer(&1))))
  end

  defp extract_commit_gpg_key_id(commit) do
    if gpg_signature = commit["gpgsig"] do
      gpg_signature
      |> GPGKey.decode!()
      |> GPGKey.parse!()
      |> get_in([:sig, :sub_pack, :issuer])
    end
  end

  defp strip_utf8(str) do
    strip_utf8_helper(str, [])
  end

  defp strip_utf8_helper(<<x :: utf8>> <> rest, acc), do: strip_utf8_helper(rest, [x|acc])
  defp strip_utf8_helper(<<_x>> <> rest, acc), do: strip_utf8_helper(rest, acc)
  defp strip_utf8_helper("", acc) do
    acc
    |> Enum.reverse()
    |> List.to_string()
  end
end
