defmodule Terrarium.ConfigTest do
  use ExUnit.Case, async: false

  alias Terrarium.Sandbox

  # These tests modify Application config and must run sequentially.

  setup do
    on_exit(fn ->
      Application.delete_env(:terrarium, :default)
      Application.delete_env(:terrarium, :providers)
    end)
  end

  describe "named providers from config" do
    test "resolves a named provider" do
      Application.put_env(:terrarium, :providers, test: Terrarium.TestProvider)

      assert {:ok, %Sandbox{provider: Terrarium.TestProvider}} = Terrarium.create(:test)
    end

    test "resolves a named provider with {module, opts} tuple" do
      Application.put_env(:terrarium, :providers, test: {Terrarium.TestProvider, some: "config"})

      assert {:ok, %Sandbox{provider: Terrarium.TestProvider}} = Terrarium.create(:test)
    end
  end

  describe "default provider from config" do
    test "uses the configured default provider" do
      Application.put_env(:terrarium, :default, :test)
      Application.put_env(:terrarium, :providers, test: Terrarium.TestProvider)

      assert {:ok, %Sandbox{provider: Terrarium.TestProvider}} = Terrarium.create()
    end

    test "merges config opts with call-site opts" do
      Application.put_env(:terrarium, :default, :test)
      Application.put_env(:terrarium, :providers, test: {Terrarium.TestProvider, from_config: true})

      assert {:ok, %Sandbox{provider: Terrarium.TestProvider}} =
               Terrarium.create(from_call: true)
    end
  end
end
