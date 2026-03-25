defmodule TerrariumTest do
  use ExUnit.Case, async: true

  alias Terrarium.Sandbox

  describe "create/2" do
    test "delegates to the provider's create callback" do
      assert {:ok, %Sandbox{id: "test-123", provider: Terrarium.TestProvider}} =
               Terrarium.create(Terrarium.TestProvider)
    end
  end

  describe "destroy/1" do
    test "delegates to the provider's destroy callback" do
      sandbox = %Sandbox{id: "test-123", provider: Terrarium.TestProvider}
      assert :ok = Terrarium.destroy(sandbox)
    end
  end

  describe "status/1" do
    test "delegates to the provider's status callback" do
      sandbox = %Sandbox{id: "test-123", provider: Terrarium.TestProvider}
      assert :running = Terrarium.status(sandbox)
    end
  end

  describe "exec/3" do
    test "delegates to the provider's exec callback" do
      sandbox = %Sandbox{id: "test-123", provider: Terrarium.TestProvider}
      assert {:ok, %Terrarium.Process.Result{exit_code: 0, stdout: "hello\n"}} = Terrarium.exec(sandbox, "echo hello")
    end
  end

  describe "read_file/2" do
    test "delegates to the provider's read_file callback" do
      sandbox = %Sandbox{id: "test-123", provider: Terrarium.TestProvider}
      assert {:ok, "file content"} = Terrarium.read_file(sandbox, "/app/file.txt")
    end
  end

  describe "write_file/3" do
    test "delegates to the provider's write_file callback" do
      sandbox = %Sandbox{id: "test-123", provider: Terrarium.TestProvider}
      assert :ok = Terrarium.write_file(sandbox, "/app/file.txt", "content")
    end
  end

  describe "ls/2" do
    test "delegates to the provider's ls callback" do
      sandbox = %Sandbox{id: "test-123", provider: Terrarium.TestProvider}
      assert {:ok, ["file1.txt", "file2.txt"]} = Terrarium.ls(sandbox, "/app")
    end
  end
end
