defmodule Event.TestProcessor do
  use Event.Processor

  def start_link(source) do
    Event.Processor.start_link(__MODULE__, :ok, subscribe_to: [source])
  end

  def handle_events(events, _from, state) do
    events = events
    |> Enum.map(fn event -> 
      {event, :processed}
    end)
    {:noreply, events, state}
  end
end