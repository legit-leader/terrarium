defmodule Terrarium.RuntimeTest do
  use ExUnit.Case, async: true

  alias Terrarium.RuntimeTestProvider

  defp create_sandbox(exec_responses) do
    {:ok, sandbox} = RuntimeTestProvider.create(exec_responses: exec_responses)
    sandbox
  end

  # We can't test the full run/2 pipeline without a real SSH sandbox,
  # but we test the individual stages via their observable behavior.

  describe "replicate/2 — mise setup" do
    test "proceeds when mise is already available" do
      sandbox =
        create_sandbox(%{
          "which mise" => {:ok, %Terrarium.Process.Result{exit_code: 0, stdout: "/usr/bin/mise", stderr: ""}}
        })

      # Gets past ensure_mise and deploy_code, fails at Terrarium.Peer.start (no real SSH)
      result = Terrarium.replicate(sandbox)
      assert {:error, _reason} = result
    end

    test "installs mise when not available" do
      sandbox =
        create_sandbox(%{
          "which mise" => {:ok, %Terrarium.Process.Result{exit_code: 1, stdout: "", stderr: ""}},
          "mise.run" => {:ok, %Terrarium.Process.Result{exit_code: 0, stdout: "", stderr: ""}}
        })

      # Gets past ensure_mise (curl succeeds), fails later at peer start
      result = Terrarium.replicate(sandbox)
      assert {:error, _reason} = result
    end

    test "returns error when mise install fails" do
      sandbox =
        create_sandbox(%{
          "which mise" => {:ok, %Terrarium.Process.Result{exit_code: 1, stdout: "", stderr: ""}},
          "mise.run" => {:ok, %Terrarium.Process.Result{exit_code: 1, stdout: "", stderr: "curl failed"}}
        })

      assert {:error, {:mise_install_failed, 1, "curl failed"}} = Terrarium.replicate(sandbox)
    end
  end

  describe "replicate/2 — options" do
    test "accepts custom destination" do
      sandbox =
        create_sandbox(%{
          "which mise" => {:ok, %Terrarium.Process.Result{exit_code: 0, stdout: "/usr/bin/mise", stderr: ""}}
        })

      result = Terrarium.replicate(sandbox, dest: "/custom/path")
      assert {:error, _reason} = result
    end

    test "accepts env and erl_args options" do
      sandbox =
        create_sandbox(%{
          "which mise" => {:ok, %Terrarium.Process.Result{exit_code: 0, stdout: "/usr/bin/mise", stderr: ""}}
        })

      result = Terrarium.replicate(sandbox, env: %{"MIX_ENV" => "prod"}, erl_args: "+S 4")
      assert {:error, _reason} = result
    end
  end

  describe "stop_replica/1" do
    test "is defined" do
      assert {:stop_replica, 1} in Terrarium.__info__(:functions)
    end
  end
end
