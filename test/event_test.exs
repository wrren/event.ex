defmodule EventTest do
  use ExUnit.Case
  
  test "event pipeline connects correctly and processes events" do
    {:ok, source}     = Event.TestSource.start_link
    {:ok, processor}  = Event.TestProcessor.start_link(source)
    {:ok, sink}       = Event.TestSink.start_link(processor)

    Event.TestSource.event(source)
    Event.TestSource.event(source)
    Event.TestSource.event(source)

    # Sleep so that all processes have a chance to receive events
    Process.sleep(500)

    assert Event.TestSink.events(sink) == [
      {:test_event, :processed},
      {:test_event, :processed},
      {:test_event, :processed}
    ]
  end
end
