defmodule Terrarium.RuntimeTestProvider do
  @moduledoc false

  use Terrarium.Provider

  @impl true
  def create(opts) do
    {:ok,
     %Terrarium.Sandbox{
       id: "runtime-test-#{System.unique_integer([:positive])}",
       provider: __MODULE__,
       state: %{
         "exec_responses" => Keyword.get(opts, :exec_responses, %{}),
         "written_files" => [],
         "exec_log" => []
       }
     }}
  end

  @impl true
  def destroy(_sandbox), do: :ok

  @impl true
  def status(_sandbox), do: :running

  @impl true
  def reconnect(sandbox), do: {:ok, sandbox}

  @impl true
  def exec(sandbox, command, _opts \\ []) do
    responses = sandbox.state["exec_responses"]

    result =
      Enum.find_value(responses, fn {pattern, response} ->
        if String.contains?(command, to_string(pattern)), do: response
      end)

    result || {:ok, %Terrarium.Process.Result{exit_code: 0, stdout: "", stderr: ""}}
  end

  @impl true
  def write_file(_sandbox, _path, _content), do: :ok

  @impl true
  def ssh_opts(_sandbox), do: {:ok, [host: "test.example.com", port: 22, user: "root", auth: nil]}
end
