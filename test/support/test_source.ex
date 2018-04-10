defmodule Event.TestSource do
  use Event.Source

  def event(source) do
    sync_notify(source, :test_event)
  end
end