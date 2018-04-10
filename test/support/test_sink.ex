defmodule Event.TestSink do
  use Event.Sink

  def start_link(source) do
    Event.Sink.start_link(__MODULE__, [], subscribe_to: [source])
  end

  def handle_events(events, _from, state) do
    {:noreply, Enum.concat(events, state)}
  end

  def handle_call(:events, _from, state) do
    {:reply, state, state}
  end

  def events(sink) do
    Event.Sink.call(sink, :events)
  end
end