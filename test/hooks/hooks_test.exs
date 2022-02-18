defmodule HooksTest do
  use ExUnit.Case

  alias Hooks.TestServer

  doctest Hooks

  setup do
    Hooks.reset()
    :ok
  end

  test "register" do
    callback = &Map.put(&1, :one, true)
    assert Hooks.status() == %{}
    Hooks.register(:test, callback)
    assert Hooks.status() == %{test: [callback]}
    callback2 = &Map.put(&1, :two, true)
    Hooks.register(:test, callback2)
    assert Hooks.status() == %{test: [callback, callback2]}
  end

  test "call" do
    callback = &Map.put(&1, :one, true)
    callback2 = &Map.put(&1, :two, 2)
    Hooks.register(:test1, callback)
    Hooks.register(:test1, callback2)
    assert Hooks.status() == %{test1: [callback, callback2]}

    assert Hooks.call(:test1, %{}) == %{one: true, two: 2}
  end

  test "unregister" do
    callback = &Map.put(&1, :one, true)
    callback2 = &Map.put(&1, :two, 2)
    Hooks.register(:test2, callback)
    Hooks.register(:test2, callback2)

    Hooks.unregister(:test2, callback)
    assert Hooks.call(:test2, %{}) == %{two: 2}
    Hooks.unregister(:test2, callback2)
    assert Hooks.call(:test2, %{}) == %{}
  end

  test "call halt" do
    callback = &{:halt, Map.put(&1, :one, true)}
    callback2 = &Map.put(&1, :two, 2)
    Hooks.register(:test2, callback)
    Hooks.register(:test2, callback2)
    assert Hooks.call(:test2, %{}) == %{one: true}
  end

  test "genserver" do
    {:ok, _} = TestServer.start_link(%{a: 1})
    assert Hooks.call(:hook1, []) == [%{a: 1}]
  end

  describe "mfa" do
    test "arity 0" do
      refute Application.get_env(:hooks, :answer)
      Hooks.register(:a, {__MODULE__, :hook, 0})
      Hooks.call(:a)
      assert Application.get_env(:hooks, :answer) == 42
      Application.delete_env(:hooks, :answer)
    end

    test "arity 1" do
      Hooks.register(:a, {__MODULE__, :hook, 1})
      assert Hooks.call(:a, [0]) == [:test, 0]
    end

    test "arity 2" do
      Hooks.register(:b, {__MODULE__, :hook, 2})
      assert Hooks.call(:b, [[0], %{one: 1}]) == [1, 0]
    end
  end

  describe "fun" do
    test "arity 0" do
      refute Application.get_env(:hooks, :answer)
      Hooks.register(:b, &hook/0)
      Hooks.call(:b)
      assert Application.get_env(:hooks, :answer) == 42
      Application.delete_env(:hooks, :answer)
    end

    test "arity 2" do
      Hooks.register(:c, &hook/2)
      assert Hooks.call(:c, [[], %{one: 3}]) == [3]
    end
  end

  test "register list" do
    Hooks.register(
      a: &hook/1,
      b: {__MODULE__, :hook, 2}
    )

    assert Hooks.status() == Map.new(a: [&hook/1], b: [{__MODULE__, :hook, 2}])
  end

  test "register multiple list" do
    callback1 = & &1
    callback2 = & &1

    Hooks.register(
      a: [&hook/1, callback1, callback2],
      b: {__MODULE__, :hook, 2}
    )

    assert Hooks.status() ==
             Map.new(a: [&hook/1, callback1, callback2], b: [{__MODULE__, :hook, 2}])
  end

  ##########
  # Helpers

  def hook(), do: Application.put_env(:hooks, :answer, 42)
  def hook(data), do: [:test | data]
  def hook(data, params), do: [params[:one] | data]
end
