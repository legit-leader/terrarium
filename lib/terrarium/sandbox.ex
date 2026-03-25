defmodule Terrarium.Sandbox do
  @moduledoc """
  Represents a running sandbox environment.

  A sandbox is the core data structure in Terrarium. It carries the provider module
  that created it along with provider-specific state needed to interact with the
  sandbox (IDs, connection info, credentials, etc.).

  You should not construct this struct directly — it is returned by `Terrarium.create/2`.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          provider: module(),
          state: map()
        }

  @enforce_keys [:id, :provider]
  defstruct [:id, :provider, state: %{}]
end
