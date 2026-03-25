defmodule Terrarium.TestProvider do
  @moduledoc false

  use Terrarium.Provider

  @impl true
  def create(_opts) do
    {:ok, %Terrarium.Sandbox{id: "test-123", provider: __MODULE__}}
  end

  @impl true
  def destroy(_sandbox), do: :ok

  @impl true
  def status(_sandbox), do: :running

  @impl true
  def exec(_sandbox, _command, _opts \\ []) do
    {:ok, %Terrarium.Process.Result{exit_code: 0, stdout: "hello\n"}}
  end

  @impl true
  def read_file(_sandbox, _path), do: {:ok, "file content"}

  @impl true
  def write_file(_sandbox, _path, _content), do: :ok

  @impl true
  def ls(_sandbox, _path), do: {:ok, ["file1.txt", "file2.txt"]}
end
