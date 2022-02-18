defmodule Hooks do
  @moduledoc """
  Documentation for `Hooks`.
  """
  use GenServer

  require Logger

  @name __MODULE__

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: @name)
  end

  @doc """
  Run a hook.

  ## Arity 2+ hooks

  Hooks with an arity more than 1 must be called with a list of the arguments.
  The first argument should be the accumulator. The remaining arguments will
  be passed to the callback and the callback should return the first argument
  (mutated optional)

  Note: function callbacks can be arity 0, 1, or 2. mfa callbacks can be
  any arity.

  ## Examples

      # arity 1 hook
      iex> Hooks.call(:a, %{})
      %{}

      # arity 2 hook
      iex> Hooks.register(:b, & [&2 | &1])
      iex> Hooks.call(:b, [[], :test])
      [:test]
  """
  def call(name, data), do: GenServer.call(@name, {:call, name, data})

  @doc """
  Run a arity/0 hook.
  """
  def call(name), do: GenServer.call(@name, {:call, name})

  def reset, do: GenServer.call(@name, :reset)

  def status, do: GenServer.call(@name, :status)

  @doc """
  Register a callback.

  Registered callbacks will be will maintain the order they are register.
  Callbacks can be either a anonymous function (arity 0, 1, and 2 only), or
  a mfa tuple. Examples include:

      {__MODULE__, :callback, 0} - def callback, do: something
      {__MODULE__, :callback, 1} - def callback(acc), do: acc
      {__MODULE__, :callback, 3} - def callback(acc, arg1, arg2), do: acc

  The arity of any given key is determined by the first registration. Any
  subsequent registration of the key will raise if the arity of given callback
  is different than the first. TODO: implement this.

  TODO: Should we implement a way register the keys and their arity? This could
  be done with a config option. Something like:

      config :hooks, keys: [key1: 0, key2: 2, key3: 1]

  If we do this, then we can validate every register against that config. This
  would give a little more consistency at the cost of more ceremony.

  ## Register a function.

  Register an arity/1 function. It will be called with given data and
  should either return the given data or return the mutated data. The data
  must be a single elixir term of any shape and is determined by the caller.

  ## Examples

      iex> callback1 = &Map.put(&1, :test, true)
      iex> callback2 = fn {a, b} -> {a + 1, Map.put(b, :test, 1)} end
      iex> Hooks.register(:a, callback1)
      iex> Hooks.register(:b, callback2)
      :ok
  """
  def register(name, callback), do: GenServer.cast(@name, {:register, name, callback})

  def register(list), do: GenServer.cast(@name, {:register, list})

  def unregister(name, callback) do
    GenServer.cast(@name, {:unregister, name, callback})
  end

  #####################
  # GenServer callbacks

  @impl true
  def init(_) do
    :ets.new(@name, [:named_table])
    register_env()

    {:ok, %{}}
  end

  @impl true
  def handle_cast({:register, name, callback}, state) do
    insert(name, callback)
    noreply(state)
  end

  def handle_cast({:register, list}, state) do
    insert(list)
    noreply(state)
  end

  def handle_cast({:unregister, name, callback}, state) do
    delete(name, callback)
    noreply(state)
  end

  @impl true
  def handle_call({:call, name, data}, _, state) do
    reply(state, do_call(name, data))
  end

  def handle_call({:call, name}, _, state) do
    reply(state, do_call(name))
  end

  def handle_call(:status, _, state) do
    reply(state, get_all())
  end

  def handle_call(:reset, _, state) do
    delete_all()
    reply(state, :ok)
  end

  ##########
  # Private

  defp do_call(name, data \\ nil) do
    name
    |> get([])
    |> Enum.reduce_while(data, fn callback, acc ->
      callback
      |> run(acc)
      |> handle_result()
    end)
  end

  defp run({m, f, 1}, data), do: apply(m, f, [data])
  defp run({m, f, 0}, _), do: apply(m, f, [])
  defp run({m, f, _}, args), do: apply(m, f, args)

  defp run(callback, _) when is_function(callback, 0), do: callback.()

  defp run(callback, data) when is_function(callback, 1), do: callback.(data)

  defp run(callback, [a, b]) when is_function(callback, 2), do: callback.(a, b)

  defp run(callback, [a, b, c]) when is_function(callback, 3), do: callback.(a, b, c)

  defp handle_result({:halt, data}), do: {:halt, data}
  defp handle_result(data), do: {:cont, data}

  defp insert(key, list) when is_list(list) do
    Enum.each(list, &insert(key, &1))
  end

  defp insert(key, value) do
    # TODO: we should validate that and subsequent registrations for a given
    # key are the same arity of the first. If different, we should probably
    # raise. This is important since the deign assumes so.
    :ets.insert(@name, {key, get(key, []) ++ [value]})
  end

  defp insert(list) do
    try do
      Enum.each(list, fn {key, value} -> insert(key, value) end)
    rescue
      e ->
        Logger.warn("error registering callbacks: #{inspect(e)}")
        :error
    end
  end

  def get(key, default \\ nil) do
    case :ets.match(@name, {key, :"$1"}) do
      [[value]] -> value
      _ -> default
    end
  end

  defp delete(key, value) do
    items = List.delete(get(key, []), value)

    if items == [] do
      :ets.match_delete(@name, {key, :_})
    else
      :ets.insert(@name, {key, items})
    end
  end

  defp delete_all do
    :ets.match_delete(@name, :_)
  end

  defp get_all do
    @name
    |> :ets.tab2list()
    |> Map.new()
  end

  defp register_env do
    :hooks
    |> Application.get_env(:register, [])
    |> insert()
  end

  defp noreply(state), do: {:noreply, state}
  defp reply(state, reply), do: {:reply, reply, state}
end
