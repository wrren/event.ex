# Event

Provides modules that can be used to simplify event production and consumption. All
modules are compatible with GenStage and are designed to simplify use of GenStage.


## Installation

Add `event` to your list of dependencies in `mix.exs`:

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



## Usage

### Event Source

Variant of the GenStage `:producer` stage type. Provides options for automatic buffering of events, restricting the maximum number of events
allowed in the queue and a simplified interface compared to GenStage.

#### Example

```elixir

defmodule MySource do
  use Event.Source, name: __MODULE__, max_items: 1_000

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

### Event Processor

Variant of the GenStage `:consumer_producer` stage type.

#### Example

```elixir

defmodule MyProcessor do
  use Event.Processor, name: __MODULE__

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

  @doc """
  Handle events from an upstream source or processor
  """
  def handle_events(events, _from, state) do
    {:noreply, Enum.map(events, fn event -> {:processed, event} end), state}
  end
end
```

### Event Processor

Variant of the GenStage `:consumer` stage type. Simplifies return signatures, removing the need to return any events, since it's
the final stage in a pipeline.

#### Example

```elixir

defmodule MySink do
  use Event.Sink, name: __MODULE__

  @doc """
  Handle events from an upstream source or processor
  """
  def handle_events(events, _from, state) do
    require Logger
    events
    |> Enum.each(fn event ->
      Logger.debug "Received Event: #{inspect event}"
    end)
    {:noreply, state}
  end
end
```

#### Available Options

* `max_events` - The maximum number of events that the source will buffer. Any events sent to the producer after this limit has been reached will be discarded. If synchronously sent, the producer will reply with `{:error, :queue_full}`
* `dispatcher` - Specifies the GenStage dispatcher type for the source, defaults to `GenStage.BroadcastDispatcher`

All other options are passed to `GenStage.start_link`, allowing you to specify GenStage behaviour if required.
