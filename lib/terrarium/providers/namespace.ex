defmodule Terrarium.Providers.Namespace do
  @moduledoc """
  A provider backed by Namespace Cloud Compute.

  The provider uses Namespace's JSON/Connect endpoints to create and destroy
  compute instances, then exposes the instance through SSH using the credentials
  returned by `GetSSHConfig`.

  ## Configuration

      config :terrarium,
        providers: [
          namespace: {Terrarium.Providers.Namespace,
            token: System.fetch_env!("NAMESPACE_TOKEN"),
            ssh_public_key: System.fetch_env!("NAMESPACE_SSH_PUBLIC_KEY"),
            ssh_private_key_path: "~/.ssh/id_ed25519"
          }
        ]

  ## Options

  - `:token` — Namespace tenant bearer token
  - `:cluster_id` — Namespace cluster id (default: `"default"`)
  - `:shape` — compute shape map (default: Linux arm64, 2 vCPU, 8 GiB RAM)
  - `:deadline_minutes` — lifetime from creation time (default: `20`)
  - `:ssh_public_key` — public key authorized on the instance
  - `:ssh_private_key` — PEM/private key string used by `ssh_opts/1`
  - `:ssh_private_key_path` — private key path used by `ssh_opts/1`; the containing directory is passed to Erlang SSH
  - `:ssh_user_dir` — SSH user directory used by `ssh_opts/1`
  - `:compute_url` — base ComputeService URL
  - `:request_timeout` — HTTP timeout in milliseconds (default: `30_000`)
  - `:create_timeout` — polling timeout in milliseconds (default: `120_000`)
  - `:poll_interval` — polling interval in milliseconds (default: `1_000`)
  """

  use Terrarium.Provider

  @default_compute_url "https://eu.compute.namespaceapis.com/namespace.cloud.compute.v1beta.ComputeService"
  @default_cluster_id "default"
  @default_request_timeout 30_000
  @default_create_timeout 120_000
  @default_poll_interval 1_000

  @impl true
  def create(opts) do
    with {:ok, token} <- fetch_required(opts, :token),
         {:ok, ssh_public_key} <- fetch_required(opts, :ssh_public_key),
         {:ok, response} <- create_instance(opts, token, ssh_public_key),
         {:ok, instance_id} <- fetch_instance_id(response),
         state = build_state(opts, token, instance_id),
         :ok <- wait_until_running(state) do
      {:ok,
       %Terrarium.Sandbox{
         id: instance_id,
         provider: __MODULE__,
         name: Keyword.get(opts, :name),
         state: state
       }}
    end
  end

  @impl true
  def destroy(%Terrarium.Sandbox{state: state}) do
    case compute_request(state, "DestroyInstance", %{"instance_id" => state["instance_id"]}) do
      :ok -> :ok
      {:ok, _body} -> :ok
      {:error, "Not found"} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def status(%Terrarium.Sandbox{state: state}) do
    case describe_instance(state) do
      {:ok, %{"metadata" => %{"status" => status}}} -> normalize_status(status)
      {:error, "Not found"} -> :destroyed
      {:error, _reason} -> :error
    end
  end

  @impl true
  def reconnect(%Terrarium.Sandbox{} = sandbox) do
    case status(sandbox) do
      :running -> {:ok, sandbox}
      :creating -> {:ok, sandbox}
      :destroyed -> {:error, :not_found}
      status -> {:error, {:not_running, status}}
    end
  end

  @impl true
  def ssh_opts(%Terrarium.Sandbox{state: state}) do
    with {:ok, %{"endpoint" => endpoint, "username" => username}} <- ssh_config(state),
         {:ok, host, port} <- parse_endpoint(endpoint) do
      {:ok,
       [
         host: host,
         port: port,
         user: username,
         auth: ssh_auth(state)
       ]}
    end
  end

  @impl true
  def exec(sandbox, command, opts \\ []) do
    with {:ok, ssh_opts} <- ssh_opts(sandbox),
         {:ok, ssh_sandbox} <- Terrarium.Providers.SSH.create(Keyword.put(ssh_opts, :cwd, Keyword.get(opts, :cwd, "/"))) do
      try do
        Terrarium.Providers.SSH.exec(ssh_sandbox, command, opts)
      after
        Terrarium.Providers.SSH.destroy(ssh_sandbox)
      end
    end
  end

  @impl true
  def read_file(sandbox, path), do: with_ssh(sandbox, &Terrarium.Providers.SSH.read_file(&1, path))

  @impl true
  def write_file(sandbox, path, content), do: with_ssh(sandbox, &Terrarium.Providers.SSH.write_file(&1, path, content))

  @impl true
  def transfer(sandbox, local_path, remote_path, opts) do
    with_ssh(sandbox, &Terrarium.Providers.SSH.transfer(&1, local_path, remote_path, opts))
  end

  @impl true
  def ls(sandbox, path), do: with_ssh(sandbox, &Terrarium.Providers.SSH.ls(&1, path))

  defp create_instance(opts, token, ssh_public_key) do
    state = build_request_state(opts, token)

    body =
      %{
        "cluster_id" => state["cluster_id"],
        "shape" => shape(opts),
        "deadline" => deadline(opts),
        "experimental" => %{
          "authorized_ssh_keys" => [ssh_public_key]
        }
      }
      |> maybe_put("name", Keyword.get(opts, :name))
      |> maybe_put("image", Keyword.get(opts, :image))
      |> maybe_put("env", Keyword.get(opts, :env))

    compute_request(state, "CreateInstance", body)
  end

  defp wait_until_running(state) do
    deadline = System.monotonic_time(:millisecond) + state["create_timeout"]
    poll_until_running(state, deadline)
  end

  defp poll_until_running(state, deadline) do
    case describe_instance(state) do
      {:ok, %{"metadata" => %{"status" => "RUNNING"}}} ->
        :ok

      {:ok, %{"metadata" => %{"status" => status}}} when status in ["FAILED", "ERROR"] ->
        {:error, {:instance_failed, status}}

      {:ok, _body} ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :instance_timeout}
        else
          Process.sleep(state["poll_interval"])
          poll_until_running(state, deadline)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp describe_instance(state) do
    compute_request(state, "DescribeInstance", %{
      "instance_id" => state["instance_id"],
      "cluster_id" => state["cluster_id"]
    })
  end

  defp ssh_config(state) do
    compute_request(state, "GetSSHConfig", %{"instance_id" => state["instance_id"]})
  end

  defp compute_request(state, method, body) do
    request(
      state["compute_url"] <> "/" <> method,
      state["token"],
      body,
      state["request_timeout"]
    )
  end

  defp request(url, token, body, timeout) do
    Req.post(
      url: url,
      headers: [
        {"authorization", "Bearer #{token}"},
        {"accept", "application/json"}
      ],
      json: body,
      receive_timeout: timeout,
      retry: false
    )
    |> handle_response()
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) when status in [200, 201] do
    case body do
      %{} = decoded when map_size(decoded) == 0 -> :ok
      decoded -> {:ok, decoded}
    end
  end

  defp handle_response({:ok, %Req.Response{status: 204}}), do: :ok

  defp handle_response({:ok, %Req.Response{status: 401}}),
    do: {:error, "Unauthorized: Invalid or expired namespace token"}

  defp handle_response({:ok, %Req.Response{status: 403}}), do: {:error, "Forbidden: Insufficient permissions"}
  defp handle_response({:ok, %Req.Response{status: 404}}), do: {:error, "Not found"}

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, "Unexpected status code: #{status}. Body: #{inspect(body)}"}
  end

  defp handle_response({:error, reason}), do: {:error, {:request_failed, reason}}

  defp build_state(opts, token, instance_id) do
    opts
    |> build_request_state(token)
    |> Map.merge(%{
      "instance_id" => instance_id,
      "ssh_private_key" => Keyword.get(opts, :ssh_private_key),
      "ssh_private_key_path" => Keyword.get(opts, :ssh_private_key_path),
      "ssh_user_dir" => Keyword.get(opts, :ssh_user_dir)
    })
  end

  defp build_request_state(opts, token) do
    %{
      "token" => token,
      "compute_url" => Keyword.get(opts, :compute_url, @default_compute_url),
      "cluster_id" => Keyword.get(opts, :cluster_id, @default_cluster_id),
      "request_timeout" => Keyword.get(opts, :request_timeout, @default_request_timeout),
      "create_timeout" => Keyword.get(opts, :create_timeout, @default_create_timeout),
      "poll_interval" => Keyword.get(opts, :poll_interval, @default_poll_interval)
    }
  end

  defp shape(opts) do
    Keyword.get(opts, :shape, %{
      "os" => "linux",
      "memory_megabytes" => 8_192,
      "virtual_cpu" => 2,
      "machine_arch" => "arm64"
    })
  end

  defp deadline(opts) do
    opts
    |> Keyword.get(:deadline_minutes, 20)
    |> then(&DateTime.add(DateTime.utc_now(), &1, :minute))
    |> DateTime.to_iso8601()
  end

  defp fetch_required(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when value not in [nil, ""] -> {:ok, value}
      _ -> {:error, {:missing_required_option, key}}
    end
  end

  defp fetch_instance_id(%{"metadata" => %{"instanceId" => instance_id}}), do: {:ok, instance_id}
  defp fetch_instance_id(%{"metadata" => %{"instance_id" => instance_id}}), do: {:ok, instance_id}
  defp fetch_instance_id(response), do: {:error, {:missing_instance_id, response}}

  defp normalize_status("RUNNING"), do: :running
  defp normalize_status("CREATING"), do: :creating
  defp normalize_status("PENDING"), do: :creating
  defp normalize_status("STOPPED"), do: :stopped
  defp normalize_status("DESTROYED"), do: :destroyed
  defp normalize_status(_status), do: :error

  defp ssh_auth(%{"ssh_user_dir" => dir}) when dir not in [nil, ""], do: {:user_dir, dir}

  defp ssh_auth(%{"ssh_private_key_path" => path}) when path not in [nil, ""],
    do: {:user_dir, path |> Path.expand() |> Path.dirname()}

  defp ssh_auth(%{"ssh_private_key" => key}) when key not in [nil, ""], do: {:key, key}
  defp ssh_auth(_state), do: nil

  defp parse_endpoint(endpoint) do
    endpoint =
      if String.contains?(endpoint, "://") do
        endpoint
      else
        "ssh://" <> endpoint
      end

    case URI.parse(endpoint) do
      %URI{host: host, port: port} when is_binary(host) and port != nil -> {:ok, host, port}
      %URI{host: host} when is_binary(host) -> {:ok, host, 22}
      _ -> {:error, {:invalid_ssh_endpoint, endpoint}}
    end
  end

  defp with_ssh(sandbox, fun) do
    with {:ok, ssh_opts} <- ssh_opts(sandbox),
         {:ok, ssh_sandbox} <- Terrarium.Providers.SSH.create(ssh_opts) do
      try do
        fun.(ssh_sandbox)
      after
        Terrarium.Providers.SSH.destroy(ssh_sandbox)
      end
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
