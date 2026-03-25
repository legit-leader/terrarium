defmodule Terrarium.Process do
  @moduledoc """
  Types for process execution results within sandboxes.
  """

  defmodule Result do
    @moduledoc """
    Represents the result of executing a command in a sandbox.

    ## Fields

    - `:exit_code` — the exit code of the process (0 for success)
    - `:stdout` — the standard output of the process
    - `:stderr` — the standard error output of the process
    """

    @type t :: %__MODULE__{
            exit_code: non_neg_integer(),
            stdout: String.t(),
            stderr: String.t()
          }

    @enforce_keys [:exit_code]
    defstruct [:exit_code, stdout: "", stderr: ""]
  end
end
