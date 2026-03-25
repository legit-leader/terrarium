# Terrarium

[![Hex.pm](https://img.shields.io/hexpm/v/terrarium.svg)](https://hex.pm/packages/terrarium)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/terrarium)
[![CI](https://github.com/pepicrft/terrarium/actions/workflows/terrarium.yml/badge.svg)](https://github.com/pepicrft/terrarium/actions/workflows/terrarium.yml)

An Elixir abstraction for provisioning and interacting with sandbox environments.

## Motivation

The AI agent ecosystem is producing many sandbox environment providers — Daytona, E2B, Modal, Fly Sprites, Namespace, and more. Each has its own API, SDK, and conventions. Terrarium provides a common Elixir interface so your code doesn't couple to any single provider.

## Features

- **Provider behaviour** — a single contract for creating, destroying, and querying sandbox environments
- **Process execution** — run commands in sandboxes with structured results
- **File operations** — read, write, and list files within sandboxes
- **Provider-agnostic** — swap providers without changing application code

## Installation

Add `terrarium` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:terrarium, "~> 0.1.0"}
  ]
end
```

## Quick Start

### 1. Add a provider package

```elixir
def deps do
  [
    {:terrarium, "~> 0.1.0"},
    {:terrarium_daytona, "~> 0.1.0"}
  ]
end
```

### 2. Create and use a sandbox

```elixir
# Create a sandbox
{:ok, sandbox} = Terrarium.create(Terrarium.Daytona,
  image: "debian:12",
  resources: %{cpu: 2, memory: 4}
)

# Execute commands
{:ok, result} = Terrarium.exec(sandbox, "echo hello")
IO.puts(result.stdout)

# File operations
:ok = Terrarium.write_file(sandbox, "/app/hello.txt", "Hello from Terrarium!")
{:ok, content} = Terrarium.read_file(sandbox, "/app/hello.txt")

# Clean up
:ok = Terrarium.destroy(sandbox)
```

## Implementing a Provider

Providers implement the `Terrarium.Provider` behaviour:

```elixir
defmodule MyProvider do
  use Terrarium.Provider

  @impl true
  def create(opts) do
    # Provision a sandbox via your provider's API
    {:ok, %Terrarium.Sandbox{id: id, provider: __MODULE__, state: %{...}}}
  end

  @impl true
  def destroy(sandbox) do
    # Tear down the sandbox
    :ok
  end

  @impl true
  def status(sandbox) do
    :running
  end

  @impl true
  def exec(sandbox, command, opts) do
    # Execute the command
    {:ok, %Terrarium.Process.Result{exit_code: 0, stdout: output}}
  end

  # File operations are optional — defaults return {:error, :not_supported}
  @impl true
  def read_file(sandbox, path) do
    {:ok, content}
  end

  @impl true
  def write_file(sandbox, path, content) do
    :ok
  end
end
```

## Available Providers

| Provider | Package | Status |
|---|---|---|
| [Daytona](https://daytona.io) | `terrarium_daytona` | Planned |
| [E2B](https://e2b.dev) | `terrarium_e2b` | Planned |
| [Modal](https://modal.com) | `terrarium_modal` | Planned |
| [Fly Sprites](https://sprites.dev) | `terrarium_sprites` | Planned |
| [Namespace](https://namespace.so) | `terrarium_namespace` | Planned |

## License

This project is licensed under the [MIT License](LICENSE).
