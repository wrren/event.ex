defmodule Event.SourceTest do
  use ExUnit.Case, async: true
  alias Event.Source

  test "source defaults to broadcast dispatcher" do
    {:producer, _state, opts} = Source.init([module: __MODULE__])
    assert opts[:dispatcher] ==  GenStage.BroadcastDispatcher
  end
end