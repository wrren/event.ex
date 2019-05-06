defmodule Event.Adapter do
  @moduledoc """
  Acts as an event sink, sending all incoming events as messages to the provided
  process. Useful when you have a process that should receive events but cannot act
  as an event sink or GenStage.

  The adapter process will monitor the receiver process and exit when it does.
  """
  use Event.Sink

  @doc """
  Start an Event Adapter that will receive events from the given source(s) GenStage and
  send them as messages to the receiver pid provided
  """
  def start_link(sources, receiver) when is_list(sources),
    do: Event.Sink.start_link(__MODULE__, receiver, [subscribe_to: sources])
  def start_link(source, receiver),
    do: Event.Sink.start_link(__MODULE__, receiver, [subscribe_to: [source]])


  def init(receiver) do
    Process.monitor(receiver)
    {:ok, receiver}
  end

  def handle_events(events, _from, receiver) do
    events
    |> Enum.each(&(send(receiver, &1)))
    {:noreply, receiver}
  end

  def handle_info({:DOWN, _ref, :process, receiver, _}, receiver) do
    {:stop, :normal, receiver}
  end
end
