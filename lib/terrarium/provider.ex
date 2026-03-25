defmodule Terrarium.Provider do
  @moduledoc """
  Behaviour for sandbox providers.

  A provider is responsible for the full lifecycle of a sandbox: creating it,
  destroying it, querying its status, and interacting with it (executing commands,
  reading/writing files).

  Providers implement this behaviour to integrate with specific sandbox platforms
  like Daytona, E2B, Modal, Fly Sprites, Namespace, and others.

  ## Implementing a provider

      defmodule MyApp.Sandbox.Daytona do
        @behaviour Terrarium.Provider

        @impl true
        def create(opts) do
          # Call Daytona API to create a sandbox
          {:ok, %Terrarium.Sandbox{id: sandbox_id, provider: __MODULE__, state: %{...}}}
        end

        @impl true
        def destroy(sandbox) do
          # Call Daytona API to destroy the sandbox
          :ok
        end

        # ... implement remaining callbacks
      end

  ## Optional callbacks

  Providers that don't support file operations can skip `read_file/2`, `write_file/3`,
  and `ls/2` — they will return `{:error, :not_supported}` by default.
  """

  alias Terrarium.Sandbox

  @type status :: :creating | :running | :stopped | :destroyed | :error

  @doc """
  Creates a new sandbox.

  Options are provider-specific. Common options include:

  - `:image` — the base image or template
  - `:resources` — map with `:cpu`, `:memory`, `:disk` keys
  - `:env` — environment variables
  - `:timeout` — creation timeout in milliseconds
  """
  @callback create(opts :: keyword()) :: {:ok, Sandbox.t()} | {:error, term()}

  @doc """
  Destroys a sandbox and releases all associated resources.
  """
  @callback destroy(sandbox :: Sandbox.t()) :: :ok | {:error, term()}

  @doc """
  Returns the current status of a sandbox.
  """
  @callback status(sandbox :: Sandbox.t()) :: status()

  @doc """
  Executes a command in the sandbox.

  ## Options

  - `:cwd` — working directory for the command
  - `:env` — environment variables as a map
  - `:timeout` — timeout in milliseconds
  """
  @callback exec(sandbox :: Sandbox.t(), command :: String.t(), opts :: keyword()) ::
              {:ok, Terrarium.Process.Result.t()} | {:error, term()}

  @doc """
  Reads a file from the sandbox filesystem.
  """
  @callback read_file(sandbox :: Sandbox.t(), path :: String.t()) :: {:ok, binary()} | {:error, term()}

  @doc """
  Writes content to a file in the sandbox filesystem.
  Creates parent directories as needed.
  """
  @callback write_file(sandbox :: Sandbox.t(), path :: String.t(), content :: binary()) :: :ok | {:error, term()}

  @doc """
  Lists the contents of a directory in the sandbox.
  """
  @callback ls(sandbox :: Sandbox.t(), path :: String.t()) :: {:ok, [String.t()]} | {:error, term()}

  @optional_callbacks [read_file: 2, write_file: 3, ls: 2]

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Terrarium.Provider

      @impl true
      def read_file(_sandbox, _path), do: {:error, :not_supported}

      @impl true
      def write_file(_sandbox, _path, _content), do: {:error, :not_supported}

      @impl true
      def ls(_sandbox, _path), do: {:error, :not_supported}

      defoverridable read_file: 2, write_file: 3, ls: 2
    end
  end
end
