defmodule Hooks.TestServer do
  use GenServer

  @name __MODULE__

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: @name)
  end

  def hook1(data), do: GenServer.call(@name, {:hook1, data})
  def stop, do: GenServer.cast(@name, :stop)
  def status, do: GenServer.call(@name, :status)

  def init(args) do
    Hooks.register(:hook1, &hook1/1)
    {:ok, args}
  end

  def handle_call({:hook1, data}, _, state), do: {:reply, [state | data], state}
  def handle_call(:status, _, state), do: {:reply, state, state}

  def handle_cast(:stop, state), do: {:stop, :normal, state}
end
