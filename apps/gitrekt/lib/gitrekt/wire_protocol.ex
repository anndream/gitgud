defmodule GitRekt.WireProtocol do
  @moduledoc """
  Conveniences for Git transport protocol and server side commands.
  """

  alias GitRekt.Git
  alias GitRekt.GitAgent
  alias GitRekt.Packfile

  @upload_caps ~w(thin-pack multi_ack multi_ack_detailed)
  @receive_caps ~w(report-status delete-refs)

  @doc """
  Callback used to transist a service to the next step.
  """
  @callback next(struct, [term]) :: {struct, [term]}

  @doc """
  Callback used to transist a service to the next step without performing any action.
  """
  @callback skip(struct) :: struct

  @doc """
  Returns an *PKT-LINE* encoded representation of the given `lines`.
  """
  @spec encode(Enumerable.t) :: iolist
  def encode(lines) do
    Enum.map(lines, &pkt_line/1)
  end

  @doc """
  Returns a stream of decoded *PKT-LINE*s for the given `pkt`.
  """
  @spec decode(binary) :: Stream.t
  def decode(pkt) do
    Stream.map(pkt_stream(pkt), &pkt_decode/1)
  end

  @doc """
  Returns a new service object for the given `repo` and `executable`.
  """
  @spec new(Git.repo, binary, keyword) :: struct
  def new(repo, executable, init_values \\ []) do
    struct(exec_impl(executable), Keyword.put(init_values, :repo, repo))
  end

  @doc """
  Runs the given `service` to the next step.
  """
  @spec next(struct, binary | :discovery) :: {struct, iolist}
  def next(service, data \\ :discovery)
  def next(service, :discovery) do
    {service, lines} = exec_next(service, [])
    {service, encode(lines)}
  end

  def next(service, data) do
    if service.state == :buffer do
      {service, lines} = exec_next(service, data)
      {service, encode(lines)}
    else
      {service, lines} = exec_next(service, Enum.to_list(decode(data)))
      {service, encode(lines)}
    end
  end

  @doc """
  Runs all the steps of the given `service` at once.
  """
  @spec run(struct, binary | :discovery, keyword) :: {struct, iolist}
  def run(service, data \\ :discovery, opts \\ [])
  def run(service, :discovery, opts), do: exec_run(service, [], opts)
  def run(service, data, opts), do: exec_run(service, Enum.to_list(decode(data)), opts)

  @doc """
  Sets the given `service` to the next logical step without performing any action.
  """
  @spec skip(struct) :: struct
  def skip(service), do: apply(service.__struct__, :skip, [service])

  @doc """
  Returns `true` if `service` is done; elsewhise returns `false`.
  """
  @spec done?(struct) :: boolean
  def done?(service), do: service.state == :done

  @doc """
  Returns a stream describing each ref and it current value.
  """
  @spec reference_discovery(GitAgent.agent, binary) :: iolist
  def reference_discovery(agent, service) do
    [reference_head(agent), reference_branches(agent), reference_tags(agent)]
    |> List.flatten()
    |> Enum.map(&format_ref_line/1)
    |> List.update_at(0, &(&1 <> "\0" <> server_capabilities(service)))
    |> Enum.concat([:flush])
  end

  @doc """
  Returns the given `data` formatted as *PKT-LINE*
  """
  @spec pkt_line(binary|:flush) :: binary
  def pkt_line(data \\ :flush)
  def pkt_line(:flush), do: "0000"
  def pkt_line({:ack, oid}), do: pkt_line("ACK #{Git.oid_fmt(oid)}")
  def pkt_line({:ack, oid, status}), do: pkt_line("ACK #{Git.oid_fmt(oid)} #{status}")
  def pkt_line(:nak), do: pkt_line("NAK")
  def pkt_line(<<"PACK", _rest::binary>> = pack), do: pack
  def pkt_line(data) when is_binary(data) do
    data
    |> byte_size()
    |> Kernel.+(5)
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(4, "0")
    |> Kernel.<>(data)
    |> Kernel.<>("\n")
  end

  #
  # Helpers
  #

  defp exec_run(service, lines, opts) do
    {service, _skip} =
      if skip = Keyword.get(opts, :skip),
        do: exec_skip(service, skip),
      else: service
    {service, lines} = exec_all(service, lines)
    {service, encode(lines)}
  end

  defp exec_next(service, lines, acc \\ []) do
    old_service = service
    event_time = System.monotonic_time(1_000_000)
    result =
      case apply(service.__struct__, :next, [service, lines]) do
        {service, [], out} ->
          if old_service.state not in [:buffer] do
            latency = System.monotonic_time(1_000_000) - event_time
            :telemetry.execute([:gitrekt, :wire_protocol, service_command(old_service)], %{latency: latency}, %{service: old_service})
          end
          {service, acc ++ out}
        {service, lines, out} ->
          exec_next(service, lines, acc ++ out)
      end
    result
  end

  defp exec_all(service, lines, acc \\ []) do
    done? = done?(service)
    {service, out} = exec_next(service, lines)
    if done?, do: {service, acc ++ out}, else: exec_all(service, [], acc ++ out)
  end

  defp exec_skip(service, count) when count > 0 do
    Enum.reduce(1..count, {service, []}, fn _i, {service, states} ->
      {skip(service), [service.state|states]}
    end)
  end

  defp exec_impl("git-upload-pack"),  do: GitRekt.WireProtocol.UploadPack
  defp exec_impl("git-receive-pack"), do: GitRekt.WireProtocol.ReceivePack

  defp service_command(%{__struct__: GitRekt.WireProtocol.UploadPack}), do: :upload_pack
  defp service_command(%{__struct__: GitRekt.WireProtocol.ReceivePack}), do: :receive_pack

  defp server_capabilities("git-upload-pack"), do: Enum.join(@upload_caps, " ")
  defp server_capabilities("git-receive-pack"), do: Enum.join(@receive_caps, " ")

  defp format_ref_line(ref), do: "#{Git.oid_fmt(ref.oid)} #{ref.prefix <> ref.name}"

  defp reference_head(agent) do
    case GitAgent.head(agent) do
      {:ok, head} -> %{head|prefix: "", name: "HEAD"}
      {:error, _reason} -> []
    end
  end

  defp reference_branches(agent) do
    case GitAgent.branches(agent) do
      {:ok, stream} -> Enum.to_list(stream)
      {:error, _reason} -> []
    end
  end

  defp reference_tags(agent) do
    case GitAgent.tags(agent) do
      {:ok, stream} -> Enum.to_list(stream)
      {:error, _reason} -> []
    end
  end

  defp pkt_stream(data) do
    Stream.resource(fn -> data end, &pkt_next/1, fn _ -> :ok end)
  end

  defp pkt_next(""), do: {:halt, nil}
  defp pkt_next("0000" <> rest), do: {[:flush], rest}
  defp pkt_next("PACK" <> rest), do: Packfile.parse(rest)
  defp pkt_next(<<hex::bytes-size(4), payload::binary>>) do
    {payload_size, ""} = Integer.parse(hex, 16)
    data_size = payload_size - 4
    data_size_skip_lf = data_size - 1
    case payload do
      <<data::bytes-size(data_size_skip_lf), "\n", rest::binary>> ->
        {[data], rest}
      <<data::bytes-size(data_size), rest::binary>> ->
        {[data], rest}
      <<data::bytes-size(data_size)>> ->
        {[data], ""}
    end
  end

  defp pkt_decode("done"), do: :done
  defp pkt_decode("want " <> hash), do: {:want, hash}
  defp pkt_decode("have " <> hash), do: {:have, hash}
  defp pkt_decode("shallow " <> hash), do: {:shallow, hash}
  defp pkt_decode(pkt_line), do: pkt_line
end
