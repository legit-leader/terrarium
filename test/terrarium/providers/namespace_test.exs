defmodule Terrarium.Providers.NamespaceTest do
  use ExUnit.Case, async: true

  alias Terrarium.Providers.Namespace

  describe "create/1" do
    test "creates an instance and waits until it is running" do
      {:ok, server} =
        start_server([
          {"/namespace.cloud.compute.v1beta.ComputeService/CreateInstance", 200,
           %{"metadata" => %{"instanceId" => "inst-123"}}},
          {"/namespace.cloud.compute.v1beta.ComputeService/DescribeInstance", 200,
           %{"metadata" => %{"status" => "RUNNING"}}}
        ])

      assert {:ok, sandbox} =
               Namespace.create(
                 token: "tenant-token",
                 ssh_public_key: "ssh-ed25519 test",
                 ssh_private_key_path: "~/.ssh/id_ed25519",
                 compute_url: server.url <> "/namespace.cloud.compute.v1beta.ComputeService",
                 poll_interval: 0
               )

      assert sandbox.id == "inst-123"
      assert sandbox.provider == Namespace
      assert sandbox.state["token"] == "tenant-token"
      assert sandbox.state["instance_id"] == "inst-123"
      assert sandbox.state["ssh_private_key_path"] == "~/.ssh/id_ed25519"

      assert [create_request, describe_request] = requests(server)
      assert create_request.authorization == "Bearer tenant-token"
      assert create_request.body["cluster_id"] == "default"

      assert create_request.body["shape"] == %{
               "machine_arch" => "arm64",
               "memory_megabytes" => 8_192,
               "os" => "linux",
               "virtual_cpu" => 2
             }

      assert create_request.body["experimental"]["authorized_ssh_keys"] == ["ssh-ed25519 test"]
      assert describe_request.body == %{"cluster_id" => "default", "instance_id" => "inst-123"}
    end

    test "requires a token" do
      assert {:error, {:missing_required_option, :token}} = Namespace.create(ssh_public_key: "ssh-ed25519 test")
    end

    test "requires an ssh public key" do
      assert {:error, {:missing_required_option, :ssh_public_key}} = Namespace.create(token: "tenant-token")
    end
  end

  describe "destroy/1" do
    test "destroys the instance" do
      {:ok, server} =
        start_server([
          {"/namespace.cloud.compute.v1beta.ComputeService/DestroyInstance", 200, %{}}
        ])

      sandbox = sandbox(server)

      assert :ok = Namespace.destroy(sandbox)
      assert [%{body: %{"instance_id" => "inst-123"}}] = requests(server)
    end

    test "treats missing instances as destroyed" do
      {:ok, server} =
        start_server([
          {"/namespace.cloud.compute.v1beta.ComputeService/DestroyInstance", 404, %{}}
        ])

      assert :ok = Namespace.destroy(sandbox(server))
    end
  end

  describe "status/1" do
    test "maps namespace status values" do
      {:ok, server} =
        start_server([
          {"/namespace.cloud.compute.v1beta.ComputeService/DescribeInstance", 200,
           %{"metadata" => %{"status" => "RUNNING"}}}
        ])

      assert :running = Namespace.status(sandbox(server))
    end

    test "returns destroyed for 404" do
      {:ok, server} =
        start_server([
          {"/namespace.cloud.compute.v1beta.ComputeService/DescribeInstance", 404, %{}}
        ])

      assert :destroyed = Namespace.status(sandbox(server))
    end
  end

  describe "ssh_opts/1" do
    test "fetches ssh configuration and returns provider ssh opts" do
      {:ok, server} =
        start_server([
          {"/namespace.cloud.compute.v1beta.ComputeService/GetSSHConfig", 200,
           %{"endpoint" => "runner.namespace.test:2222", "username" => "admin"}}
        ])

      assert {:ok, opts} = Namespace.ssh_opts(sandbox(server))
      assert opts[:host] == "runner.namespace.test"
      assert opts[:port] == 2222
      assert opts[:user] == "admin"
      assert opts[:auth] == {:key_path, "~/.ssh/id_ed25519"}
    end
  end

  defp sandbox(server) do
    %Terrarium.Sandbox{
      id: "inst-123",
      provider: Namespace,
      state: %{
        "token" => "tenant-token",
        "compute_url" => server.url <> "/namespace.cloud.compute.v1beta.ComputeService",
        "cluster_id" => "default",
        "request_timeout" => 1_000,
        "create_timeout" => 1_000,
        "poll_interval" => 0,
        "instance_id" => "inst-123",
        "ssh_private_key_path" => "~/.ssh/id_ed25519"
      }
    }
  end

  defp requests(%{agent: agent}) do
    Agent.get(agent, &Enum.reverse(&1.requests))
  end

  defp start_server(responses) do
    test_pid = self()
    {:ok, agent} = Agent.start(fn -> %{responses: responses, requests: []} end)
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(listen_socket)

    pid =
      spawn(fn ->
        accept_loop(listen_socket, agent, test_pid)
      end)

    on_exit(fn ->
      :gen_tcp.close(listen_socket)
      Process.exit(pid, :normal)

      if Process.alive?(agent) do
        Agent.stop(agent)
      end
    end)

    {:ok, %{url: "http://127.0.0.1:#{port}", agent: agent}}
  end

  defp accept_loop(listen_socket, agent, test_pid) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        handle_connection(socket, agent)
        accept_loop(listen_socket, agent, test_pid)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        send(test_pid, {:server_error, reason})
    end
  end

  defp handle_connection(socket, agent) do
    {:ok, raw_request} = read_request(socket, "")
    {path, headers, body} = parse_request(raw_request)
    authorization = Map.get(headers, "authorization")
    decoded_body = if body == "", do: %{}, else: JSON.decode!(body)

    {status, response_body} =
      Agent.get_and_update(agent, fn %{responses: [{expected_path, status, response_body} | rest]} = state ->
        assert path == expected_path

        {{status, response_body},
         %{
           state
           | responses: rest,
             requests: [%{path: path, authorization: authorization, body: decoded_body} | state.requests]
         }}
      end)

    write_response(socket, status, response_body)
    :gen_tcp.close(socket)
  end

  defp read_request(socket, acc) do
    case :gen_tcp.recv(socket, 0, 1_000) do
      {:ok, chunk} ->
        next = acc <> chunk

        if request_complete?(next) do
          {:ok, next}
        else
          read_request(socket, next)
        end

      error ->
        error
    end
  end

  defp request_complete?(raw_request) do
    case String.split(raw_request, "\r\n\r\n", parts: 2) do
      [headers, body] ->
        content_length =
          headers
          |> String.split("\r\n")
          |> Enum.find_value(0, fn header ->
            case String.split(header, ":", parts: 2) do
              [name, value] ->
                if String.downcase(name) == "content-length" do
                  String.trim(value) |> String.to_integer()
                end

              _ ->
                nil
            end
          end)

        byte_size(body) >= content_length

      _ ->
        false
    end
  end

  defp parse_request(raw_request) do
    [head, body] = String.split(raw_request, "\r\n\r\n", parts: 2)
    [request_line | header_lines] = String.split(head, "\r\n")
    [_method, path, _version] = String.split(request_line, " ", parts: 3)

    headers =
      Map.new(header_lines, fn line ->
        [name, value] = String.split(line, ":", parts: 2)
        {String.downcase(name), String.trim(value)}
      end)

    {path, headers, body}
  end

  defp write_response(socket, status, body) do
    encoded_body = JSON.encode!(body)

    response = [
      "HTTP/1.1 #{status} OK\r\n",
      "content-type: application/json\r\n",
      "content-length: #{byte_size(encoded_body)}\r\n",
      "connection: close\r\n",
      "\r\n",
      encoded_body
    ]

    :ok = :gen_tcp.send(socket, response)
  end
end
