# Event

Provides modules that can be used to simplify event production and consumption. All
modules are compatible with GenStage and are typically designed to simplify use of GenStage.

## Usage

### Event Producer

Variant of the GenStage `:producer` stage type. Provides options for automatic buffering of events, restricting the maximum number of events
allowed in the queue and a simplified interface compared to GenStage.

#### Example

```elixir

defmodule MyProducer do
  use Event.Producer, name: __MODULE__, max_items: 1_000

  @doc """
  Synchronously notify consumers that an event has occurred. Will only
  return once the event has been consumed or the timeout is reached
  """
  def sync_notify(event) do
    Event.Producer.sync_notify(__MODULE__, event)
  end

  @doc """
  Asynchronously notify consumers that an event has occurred
  """
  def async_notify(event) do
    Event.Producer.async_notify(__MODULE__, event)
  end
end
```

#### Available Options

* `max_events` - The maximum number of events that the producer will buffer. Any events sent to the producer after this limit has been reached will be discarded. If synchronously sent, the producer will reply with `{:error, :queue_full}`
* `dispatcher` - Specifies the GenStage dispatcher type for the producer, defaults to `GenStage.BroadcastDispatcher`

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `event` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:event, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/event](https://hexdocs.pm/event).

