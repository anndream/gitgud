defmodule GitRekt.Git do
  @moduledoc ~S"""
  Erlang NIF that exposes a subset of *libgit2*'s library functions.

  Most functions available in this module are implemented in C for performance reasons.
  These functions are compiled into a dynamic loadable, shared library. They are called like any other Elixir functions.

  > As a NIF library is dynamically linked into the emulator process, this is the fastest way of calling C-code from Erlang (alongside port drivers). Calling NIFs requires no context switches. But it is also the least safe, because a crash in a NIF brings the emulator down too.
  >
  > [Erlang documentation - NIFs](http://erlang.org/doc/tutorial/nif.html)

  ## Example

  Let's start with a basic code example showing the last commit author and message:

  ```elixir
  alias GitRekt.Git

  # load repository
  {:ok, repo} = Git.repository_open("/tmp/my-repo")

  # fetch commit pointed by master
  {:ok, :commit, _oid, commit} = Git.reference_peel(repo, "refs/heads/master")

  # fetch commit author & message
  {:ok, name, email, time, _offset} = Git.commit_author(commit)
  {:ok, message} = Git.commit_message(commit)

  IO.puts "Last commit by #{name} <#{email}>:"
  IO.puts message
  ```

  First we open our repository using `repository_open/1`, passing the path of the Git repository.  We can fetch
  a branch by passing the exact reference path to `reference_peel/2`. In our example, this allows us to access
  the commit `master` is pointing to.

  This is one of many ways to fetch a given commit, `reference_lookup/2` and `reference_glob/2` offer similar
  functionalities. There are other related functions such as `revparse_single/2` and `revparse_ext/2` which
  provide support for parsing [revspecs](https://git-scm.com/book/en/v2/Git-Tools-Revision-Selection).

  ## Thread safety

  Accessing a `t:repo/0` or any NIF allocated pointer (`t:blob/0`, `t:commit/0`, `t:config/0`, etc.) from multiple
  processes simultaneously is not safe. These pointers should never be shared across processes.

  In order to access a repository in a concurrent manner, each process has to initialize it's own repository
  pointer using `repository_open/1`. Alternatively, the `GitRekt.GitAgent` module provides a similar API but
  can use a dedicated process, so that its access can be serialized.
  """

  @type repo          :: reference

  @type oid           :: binary
  @type signature     :: {binary, binary, non_neg_integer, non_neg_integer}

  @type odb           :: reference
  @type odb_type      :: atom

  @type ref_iter      :: reference
  @type ref_type      :: :oid | :symbolic

  @type config        :: reference
  @type blob          :: reference
  @type commit        :: reference
  @type tag           :: reference

  @type obj           :: blob | commit | tree | tag
  @type obj_type      :: :blob | :commit | :tree | :tag

  @type reflog_entry  :: {
    binary,
    binary,
    non_neg_integer,
    non_neg_integer,
    oid,
    oid,
    binary
  }

  @type tree          :: reference
  @type tree_entry    :: {integer, :blob | :tree, oid, binary}

  @type diff          :: reference
  @type diff_format   :: :patch | :patch_header | :raw | :name_only | :name_status
  @type diff_delta    :: {diff_file, diff_file, non_neg_integer, non_neg_integer}
  @type diff_file     :: {oid, binary, integer, non_neg_integer}
  @type diff_hunk     :: {binary, integer, integer, integer, integer}
  @type diff_line     :: {char, integer, integer, integer, integer, binary}

  @type index         :: reference
  @type index_entry   :: {
    integer,
    integer,
    non_neg_integer,
    non_neg_integer,
    non_neg_integer,
    non_neg_integer,
    non_neg_integer,
    integer,
    binary,
    non_neg_integer,
    non_neg_integer,
    binary
  }

  @type revwalk       :: reference
  @type revwalk_sort  :: :topsort | :timesort | :reversesort

  @type pack          :: reference

  @on_load :load_nif

  @nif_path Path.join(:code.priv_dir(:gitrekt), "geef_nif")
  @nif_path_lib @nif_path <> ".so"

  @doc false
  def load_nif do
    case :erlang.load_nif(@nif_path, 0) do
      :ok -> :ok
      {:error, {:load_failed, error}} -> raise RuntimeError, message: error
    end
  end

  @doc """
  Returns a repository handle for the `path`.
  """
  @spec repository_load(Path.t) :: {:ok, repo} | {:error, term}
  def repository_load(path) when is_binary(path), do: repository_open(path)

  @doc """
  Returns a repository handle for a custom backend.
  """
  @spec repository_load({atom, [term]}) :: {:ok, repo} | {:error, term}
  def repository_load({backend, args} = _backend_spec) do
    apply(__MODULE__, String.to_atom("repository_open_#{backend}"), args)
  end

  @doc """
  Returns a repository handle for the `path`.
  """
  @spec repository_open(Path.t) :: {:ok, repo} | {:error, term}
  def repository_open(_path) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc false
  def repository_open_postgres(_repo_id, _db_url) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns `true` if `repo` is bare; elsewhise returns `false`.
  """
  @spec repository_bare?(repo) :: boolean
  def repository_bare?(_repo) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns `true` if `repo` is empty; elsewhise returns `false`.
  """
  @spec repository_empty?(repo) :: boolean
  def repository_empty?(_repo) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the absolute path for the given `repo`.
  """
  @spec repository_get_path(repo) :: Path.t
  def repository_get_path(_repo) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the normalized path to the working directory for the given `repo`.
  """
  @spec repository_get_workdir(repo) :: Path.t
  def repository_get_workdir(_repo) do
      raise Code.LoadError, file: @nif_path_lib
    end

  @doc """
  Returns the ODB for the given `repository`.
  """
  @spec repository_get_odb(repo) :: {:ok, odb} | {:error, term}
  def repository_get_odb(_repo) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the config for the given `repo`.
  """
  @spec repository_get_config(repo) :: {:ok, config} | {:error, term}
  def repository_get_config(_repo) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Initializes a new repository at the given `path`.
  """
  @spec repository_init(Path.t, boolean) :: {:ok, repo} | {:error, term}
  def repository_init(_path, _bare \\ false) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Looks for a repository and returns its path.
  """
  @spec repository_discover(Path.t) :: {:ok, Path.t} | {:error, term}
  def repository_discover(_path) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns all references for the given `repo`.
  """
  @spec reference_list(repo) :: {:ok, [binary]} | {:error, term}
  def reference_list(_repo) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Recursively peels the given reference `name` until an object of type `type` is found.
  """
  @spec reference_peel(repo, binary, obj_type | :undefined) :: {:ok, obj_type, oid, obj} | {:error, term}
  def reference_peel(_repo, _name, _type \\ :undefined) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Creates a new reference name which points to an object or to an other reference.
  """
  @spec reference_create(repo, binary, ref_type, binary | oid, boolean) :: :ok | {:error, term}
  def reference_create(_repo, _name, _type, _target, _force \\ false) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Deletes an existing reference.
  """
  @spec reference_delete(repo, binary) :: :ok | {:error, term}
  def reference_delete(_repo, _name) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Looks for a reference by `name` and returns its id.
  """
  @spec reference_to_id(repo, binary) :: {:ok, oid} | {:error, term}
  def reference_to_id(_repo, _name) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Similar to `reference_list/1` but allows glob patterns.
  """
  @spec reference_glob(repo, binary) :: {:ok, [binary]} | {:error, term}
  def reference_glob(_repo, _glob) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Looks for a reference by `name`.
  """
  @spec reference_lookup(repo, binary) :: {:ok, binary, ref_type, binary} | {:error, term}
  def reference_lookup(_repo, _name) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns an iterator for the references that match the specific `glob` pattern.
  """
  @spec reference_iterator(repo, binary | :undefined) :: {:ok, ref_iter} | {:error, term}
  def reference_iterator(_repo, _glob \\ :undefined) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the next reference.
  """
  @spec reference_next(ref_iter) :: {:ok, binary, binary, ref_type, binary} | {:error, term}
  def reference_next(_iter) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns a stream for the references that match the specific `glob` pattern.
  """
  @spec reference_stream(repo, binary | :undefined) :: {:ok, Stream.t} | {:error, term}
  def reference_stream(repo, glob \\ :undefined) do
    case reference_iterator(repo, glob) do
      {:ok, iter} -> {:ok, Stream.resource(fn -> iter end, &reference_stream_next/1, fn _iter -> :ok end)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Resolves a symbolic reference to a direct reference.
  """
  @spec reference_resolve(repo, binary) :: {:ok, binary, binary, oid} | {:error, term}
  def reference_resolve(_repo, _name) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Looks for a reference by DWIMing its `short_name`.
  """
  @spec reference_dwim(repo, binary) :: {:ok, binary, ref_type, binary} | {:error, term}
  def reference_dwim(_repo, _short_name) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns `true` if a reflog exists for the given reference `name`.
  """
  @spec reference_log?(repo, binary) :: {:ok, boolean} | {:error, term}
  def reference_log?(_repo, _name) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Reads the number of entry for the given reflog `name`.
  """
  @spec reflog_count(repo, binary) :: {:ok, pos_integer} | {:error, term}
  def reflog_count(_repo, _name) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Reads the reflog for the given reference `name`.
  """
  @spec reflog_read(repo, binary) :: {:ok, [reflog_entry]} | {:error, term}
  def reflog_read(_repo, _name) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Deletes the reflog for the given reference `name`.
  """
  @spec reflog_delete(repo, binary) :: :ok | {:error, term}
  def reflog_delete(_repo, _name) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the OID of an object `type` and raw `data`.

  The resulting SHA-1 OID will be the identifier for the data buffer as if the data buffer it were to written to the ODB.
  """
  @spec odb_object_hash(obj_type, binary) :: {:ok, oid} | {:error, term}
  def odb_object_hash(_type, _data) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns `true` if the given `oid` exists in `odb`; elsewhise returns `false`.
  """
  @spec odb_object_exists?(odb, oid) :: boolean
  def odb_object_exists?(_odb, _oid) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Return the uncompressed, raw data of an ODB object.
  """
  @spec odb_read(odb, oid) :: {:ok, obj_type, binary}
  def odb_read(_odb, _oid) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Writes the given `data` into the `odb`.
  """
  @spec odb_write(odb, binary, odb_type) :: {:ok, oid} | {:error, term}
  def odb_write(_odb, _data, _type) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the SHA `hash` for the given `oid`.
  """
  @spec oid_fmt(oid) :: binary
  def oid_fmt(_oid) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the abbreviated SHA `hash` for the given `oid`.
  """
  @spec oid_fmt_short(oid) :: binary
  def oid_fmt_short(oid), do: String.slice(oid_fmt(oid), 0..7)

  @doc """
  Returns the OID for the given SHA `hash`.
  """
  @spec oid_parse(binary) :: oid
  def oid_parse(_hash) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the repository that owns the given `obj`.
  """
  @spec object_repository(obj) :: {:ok, repo} | {:error, term}
  def object_repository(_obj) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Looks for an object with the given `oid`.
  """
  @spec object_lookup(repo, oid) :: {:ok, obj_type, obj} | {:error, term}
  def object_lookup(_repo, _oid) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the OID for the given `obj`.
  """
  @spec object_id(obj) :: {:ok, oid} | {:error, term}
  def object_id(_obj) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Inflates the given `data` with *zlib*.
  """
  @spec object_zlib_inflate(binary) :: {:ok, iodata, non_neg_integer} | {:error, term}
  def object_zlib_inflate(_data) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns parent commits of the given `commit`.
  """
  @spec commit_parents(commit) :: {:ok, [{oid, commit}]} | {:error, term}
  def commit_parents(commit) do
    case commit_parent_count(commit) do
      {:ok, count} ->
        {:ok, Stream.resource(fn -> {commit, 0, count} end, &commit_parent_stream_next/1, fn _iter -> :ok end)}
    end
  end

  @doc """
  Looks for a parent commit of the given `commit` by its `index`.
  """
  @spec commit_parent(commit, non_neg_integer) :: {:ok, oid, commit} | {:error, term}
  def commit_parent(_commit, _index) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the number of parents for the given `commit`.
  """
  @spec commit_parent_count(commit) :: oid
  def commit_parent_count(_commit) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the tree id for the given `commit`.
  """
  @spec commit_tree_id(commit) :: oid
  def commit_tree_id(_commit) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the tree for the given `commit`.
  """
  @spec commit_tree(commit) :: {:ok, oid, tree} | {:error, term}
  def commit_tree(_commit) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Creates a new commit with the given params.
  """
  @spec commit_create(repo, binary | :undefined, signature, signature, binary | :undefined, binary, oid, [binary]) :: {:ok, oid} | {:error, term}
  def commit_create(_repo, _ref, _author, _commiter, _encoding, _message, _tree, _parents) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the message for the given `commit`.
  """
  @spec commit_message(commit) :: {:ok, binary} | {:error, term}
  def commit_message(_commit) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the author of the given `commit`.
  """
  @spec commit_author(commit) :: {:ok, binary, binary, non_neg_integer, non_neg_integer} | {:error, term}
  def commit_author(_commit) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the committer of the given `commit`.
  """
  @spec commit_committer(commit) :: {:ok, binary, binary, non_neg_integer, non_neg_integer} | {:error, term}
  def commit_committer(_commit) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the time of the given `commit`.
  """
  @spec commit_time(commit) :: {:ok, non_neg_integer, non_neg_integer} | {:error, term}
  def commit_time(_commit) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the full raw header of the given `commit`.
  """
  @spec commit_raw_header(commit) :: {:ok, binary} | {:error, term}
  def commit_raw_header(_commit) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns an arbitrary header `field` of the given `commit`.
  """
  @spec commit_header(commit, binary) :: {:ok, binary} | {:error, term}
  def commit_header(_commit, _field) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Retrieves a tree entry owned by the given `tree`, given its id.
  """
  @spec tree_byid(tree, oid) :: {:ok, integer, atom, binary, binary} | {:error, term}
  def tree_byid(_tree, _oid) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Retrieves a tree entry contained in the given `tree` or in any of its subtrees, given its relative path.
  """
  @spec tree_bypath(tree, Path.t) :: {:ok, integer, atom, binary, binary} | {:error, term}
  def tree_bypath(_tree, _path) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the number of entries listed in the given `tree`.
  """
  @spec tree_count(tree) :: {:ok, non_neg_integer} | {:error, term}
  def tree_count(_tree) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Looks for a tree entry by its position in the given `tree`.
  """
  @spec tree_nth(tree, non_neg_integer) :: {:ok, integer, atom, binary, binary} | {:error, term}
  def tree_nth(_tree, _nth) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns all entries in the given `tree`.
  """
  @spec tree_entries(tree) :: {:ok, Stream.t} | {:error, term}
  def tree_entries(tree) do
    {:ok, Stream.resource(fn -> {tree, 0} end, &tree_stream_next/1, fn _iter -> :ok end)}
  end

  @doc """
  Returns the size in bytes of the given `blob`.
  """
  @spec blob_size(blob) :: {:ok, integer} | {:error, term}
  def blob_size(_blob) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the raw content of the given `blob`.
  """
  @spec blob_content(blob) :: {:ok, binary} | {:error, term}
  def blob_content(_blob) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns all tags for the given `repo`.
  """
  @spec tag_list(repo) :: {:ok, [binary]} | {:error, term}
  def tag_list(_repo) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Recursively peels the given `tag` until a non tag object is found.
  """
  @spec tag_peel(tag) :: {:ok, obj_type, oid, obj} | {:error, term}
  def tag_peel(_tag) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the name of the given `tag`.
  """
  @spec tag_name(tag) :: {:ok, binary} | {:error, term}
  def tag_name(_tag) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the message of the given `tag`.
  """
  @spec tag_message(tag) :: {:ok, binary} | {:error, term}
  def tag_message(_tag) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the author of the given `tag`.
  """
  @spec tag_author(tag) :: {:ok, binary, binary, non_neg_integer, non_neg_integer} | {:error, term}
  def tag_author(_tag) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the *libgit2* library version.
  """
  @spec library_version() :: {integer, integer, integer}
  def library_version() do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Creates a new revision walk object for the given `repo`.
  """
  @spec revwalk_new(repo) :: {:ok, reference} | {:error, term}
  def revwalk_new(_repo) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Adds a new root for the traversal.
  """
  @spec revwalk_push(revwalk, oid, boolean) :: :ok | {:error, term}
  def revwalk_push(_walk, _oid, _hide \\ false) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the next commit from the given revision `walk`.
  """
  @spec revwalk_next(revwalk) :: {:ok, oid} | {:error, term}
  def revwalk_next(_walk) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Changes the sorting mode when iterating through the repository's contents.
  """
  @spec revwalk_sorting(revwalk, [revwalk_sort]) :: :ok | {:error, term}
  def revwalk_sorting(_walk, _sort_mode) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Simplifies the history by first-parent.
  """
  @spec revwalk_simplify_first_parent(revwalk) :: :ok | {:error, term}
  def revwalk_simplify_first_parent(_walk) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Resets the revision `walk` for reuse.
  """
  @spec revwalk_reset(revwalk) :: revwalk
  def revwalk_reset(_walk) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns a stream for the given revision `walk`.
  """
  @spec revwalk_stream(revwalk) :: {:ok, Stream.t} | {:error, term}
  def revwalk_stream(walk) do
    {:ok, Stream.resource(fn -> walk end, &revwalk_stream_next/1, fn _walk -> :ok end)}
  end

  @doc """
  Returns the repository on which the given `walker` is operating.
  """
  @spec revwalk_repository(revwalk) :: {:ok, repo} | {:error, term}
  def revwalk_repository(_walk) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns `true` if `tree` matches the given `pathspec`; otherwise returns `false`.
  """
  @spec pathspec_match_tree(tree, [binary]) :: {:ok, boolean} | {:error, term}
  def pathspec_match_tree(_tree, _pathspec) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns a *PACK* file for the given `walk`.
  """
  @spec revwalk_repository(revwalk) :: {:ok, binary} | {:error, term}
  def revwalk_pack(_walk) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns a diff with the difference between two tree objects.
  """
  @spec diff_tree(repo, tree, tree) :: {:ok, diff} | {:error, term}
  def diff_tree(_repo, _old_tree, _new_tree, _opts \\ []) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns stats for the given `diff`.
  """
  @spec diff_stats(diff) :: {:ok, non_neg_integer, non_neg_integer, non_neg_integer} | {:error, term}
  def diff_stats(_diff) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the number of deltas in the given `diff`.
  """
  @spec diff_delta_count(diff) :: {:ok, non_neg_integer} | {:error, term}
  def diff_delta_count(_diff) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns a list of deltas for the given `diff`.
  """
  @spec diff_deltas(diff) :: {:ok, [{diff_delta, [{diff_hunk, [diff_line]}]}]} | {:error, term}
  def diff_deltas(_diff) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns a binary represention of the given `diff`.
  """
  @spec diff_format(diff, diff_format) :: {:ok, binary} | {:error, term}
  def diff_format(_diff, _format \\ :patch) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Creates an new in-memory index object.
  """
  @spec index_new() :: {:ok, index} | {:error, term}
  def index_new do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Writes the given `index` from memory back to disk using an atomic file lock.
  """
  @spec index_write(index) :: :ok | {:error, term}
  def index_write(_index) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Writes the given `index` as a tree.
  """
  @spec index_write_tree(index) :: {:ok, oid} | {:error, term}
  def index_write_tree(_index) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Writes the given `index` as a tree.
  """
  @spec index_write_tree(index, repo) :: {:ok, oid} | {:error, term}
  def index_write_tree(_index, _repo) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Reads the given `tree` into the given `index` file with stats.
  """
  @spec index_read_tree(index, tree) :: :ok | {:error, term}
  def index_read_tree(_index, _tree) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the number of entries in the given `index`.
  """
  @spec index_count(index) :: non_neg_integer()
  def index_count(_index) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Looks for an entry by its position in the given `index`.
  """
  @spec index_nth(index, non_neg_integer) ::
  {:ok, integer,
        integer,
        non_neg_integer,
        non_neg_integer,
        non_neg_integer,
        non_neg_integer,
        non_neg_integer,
        integer,
        binary,
        non_neg_integer,
        non_neg_integer,
        binary} |
  {:error, term}

  def index_nth(_index, _nth) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Retrieves an entry contained in the `index` given its relative path.
  """
  @spec index_bypath(index, Path.t, non_neg_integer) ::
  {:ok, integer,
        integer,
        non_neg_integer,
        non_neg_integer,
        non_neg_integer,
        non_neg_integer,
        non_neg_integer,
        integer,
        binary,
        non_neg_integer,
        non_neg_integer,
        binary} |
  {:error, term}
  def index_bypath(_index, _path, _stage) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Adds or updates the given `entry`.
  """
  @spec index_add(index, index_entry) :: :ok | {:error, term}
  def index_add(_index, _entry) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Clears the contents (all the entries) of the given `index`.
  """
  @spec index_clear(index) :: :ok | {:error, term}
  def index_clear(_index) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the default signature for the given `repo`.
  """
  @spec signature_default(repo) :: {:ok, binary, binary, non_neg_integer, non_neg_integer} | {:error, term}
  def signature_default(_repo) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Creates a new signature with the given `name` and `email`.
  """
  @spec signature_new(binary, binary) :: {:ok, binary, binary}
  def signature_new(_name, _email) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Creates a new signature with the given `name`, `email` and `time`.
  """
  @spec signature_new(binary, binary, non_neg_integer) :: {:ok, binary, binary, non_neg_integer, non_neg_integer} | {:error, term}
  def signature_new(_name, _email, _time) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Finds a single object, as specified by the given `revision`.
  """
  @spec revparse_single(repo, binary) :: {:ok, obj, obj_type, oid} | {:error, term}
  def revparse_single(_repo, _revision) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Finds a single object and intermediate reference, as specified by the given `revision`.
  """
  @spec revparse_ext(repo, binary) :: {:ok, obj, obj_type, oid, binary | nil} | {:error, term}
  def revparse_ext(_repo, _revision) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Sets the `config` entry with the given `name` to `val`.
  """
  @spec config_set_bool(config, binary, boolean) :: :ok | {:error, term}
  def config_set_bool(_config, _name, _val) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the value of the `config` entry with the given `name`.
  """
  @spec config_get_bool(config, binary) :: {:ok, boolean} | {:error, term}
  def config_get_bool(_config, _name) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Sets the `config` entry with the given `name` to `val`.
  """
  @spec config_set_string(config, binary, binary) :: :ok | {:error, term}
  def config_set_string(_config, _name, _val) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns the value of the `config` entry with the given `name`.
  """
  @spec config_get_string(config, binary) :: {:ok, binary} | {:error, term}
  def config_get_string(_config, _name) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns a config handle for the given `path`.
  """
  @spec config_open(binary) :: {:ok, config} | {:error, term}
  def config_open(_path) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Creates a new *PACK* object for the given `repo`.
  """
  @spec pack_new(repo) :: {:ok, pack} | {:error, term}
  def pack_new(_repo) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Inserts `commit` as well as the completed referenced tree.
  """
  @spec pack_insert_commit(pack, oid) :: :ok | {:error, term}
  def pack_insert_commit(_pack, _oid) do
    raise Code.LoadError, file: @nif_path_lib
  end


  @doc """
  Inserts objects as given by the `walk`.
  """
  @spec pack_insert_walk(pack, revwalk) :: :ok | {:error, term}
  def pack_insert_walk(_pack, _walk) do
    raise Code.LoadError, file: @nif_path_lib
  end

  @doc """
  Returns a *PACK* file for the given `pack`.
  """
  @spec pack_data(pack) :: {:ok, binary} | {:error, term}
  def pack_data(_pack) do
    raise Code.LoadError, file: @nif_path_lib
  end

  #
  # Helpers
  #

  defp reference_stream_next(iter) do
    case reference_next(iter) do
      {:ok, name, type, shortname, target} ->
        {[{name, type, shortname, target}], iter}
      {:error, :iterover} ->
        {:halt, iter}
    end
  end

  defp revwalk_stream_next(walk) do
    case revwalk_next(walk) do
      {:ok, oid} ->
        {[oid], walk}
      {:error, :iterover} ->
        {:halt, walk}
    end
  end

  defp commit_parent_stream_next({_commit, max, max} = iter), do: {:halt, iter}
  defp commit_parent_stream_next({commit, i, max}) do
    case commit_parent(commit, i) do
      {:ok, oid, parent} -> {[{oid, parent}], {commit, i+1, max}}
    end
  end

  defp tree_stream_next(iter) do
    {tree, i} = iter
    case tree_nth(tree, i) do
      {:ok, mode, type, oid, path} ->
        {[{mode, type, oid, path}], {tree, i+1}}
      {:error, :enomem} ->
        {:halt, iter}
    end
  end
end
