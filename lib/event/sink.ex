defmodule Event.Sink do
  @moduledoc """
  Final stage in an Event processing chain. Receives events from an
  Event.Source or Event.Processor and performs any final processing
  on them.
  """

  use GenStage
  defstruct module:     nil,
            state:      nil,
            opts:       nil

  defmacro __using__(opts \\ []) do
    quote do
      @behaviour Event.Sink

      @doc """
      Start an Event Sink
      """
      def start_link do
        Event.Sink.start_link(__MODULE__, [], unquote(opts))
      end

      @doc """
      Start an Event Sink
      """
      def start_link(module, args, opts) do
        Event.Sink.start_link(__MODULE__, args, opts)
      end

      @doc """
      Default initializer function
      """
      def init(args) do
        {:ok, args}
      end

      @doc """
      Handle incoming events from an upstream producer
      """
      def handle_events(events, _from, state) do
        {:noreply, events, state}
      end

      @doc """
      Handle a synchronous call
      """
      def handle_call(_call, _from, state) do
        {:reply, :ok, [], state}
      end

      @doc """
      Handle an asynchronous cast
      """
      def handle_cast(_cast, state) do
        {:noreply, [], state}
      end

      @doc """
      Default handler for incoming messages.
      """
      def handle_info(_info, state) do
        {:noreply, [], state}
      end

      @doc """
      Handle a code change
      """
      def code_change(_old_version, state, _extra), 
        do: {:ok, state}
      

      def terminate(_reason, _state),
        do: :ok

      defoverridable [
        init: 1, 
        handle_call: 3, 
        handle_cast: 2, 
        handle_info: 2, 
        handle_events: 3, 
        code_change: 3, 
        terminate: 2
      ]
    end
  end

  @doc """
  Start an EventSink process.
  """
  def start_link(module, args, opts) do
    GenStage.start_link(
      __MODULE__, 
      Keyword.merge(opts, [module: module, args: args]),
      Keyword.drop(opts, [:module, :args])
    )
  end

  @doc """
  Send a message to the event processor and await a response.
  """
  def call(processor, call, timeout \\ 5_000) do
    GenStage.call(processor, call, timeout)
  end

  @doc """
  Send an asynchronous message to the event processor
  """
  def cast(processor, cast) do
    GenStage.cast(processor, cast)
  end

  @doc """
  Initialize event processor state
  """
  def init(opts) do
    stage_opts = opts
    |> Keyword.take([:subscribe_to])

    with  true <- function_exported?(opts[:module], :init, 1) do
      case Kernel.apply(opts[:module], :init, [opts[:args]]) do
        {:ok, state} ->
          {:consumer, %Event.Source{module: opts[:module], state: state, opts: opts}, stage_opts}
        {:ok, state, init_opts} ->
          opts = Keyword.merge(opts, init_opts)
          {:consumer, %Event.Source{module: opts[:module], state: state, opts: opts}, stage_opts}
        other ->
          other
      end
    else
      {:stop, reason} ->
        {:stop, reason}
      false ->
        {:consumer, %Event.Source{module: opts[:module], state: :ok, opts: opts}, stage_opts}
    end
  end

  @doc """
  Handle a subscription
  """
  def handle_subscribe(subscriber, opts, from, %{module: module, state: mstate} = state) do
    with  true <- function_exported?(module, :handle_subscribe, 4),
          {_, new_state} <- Kernel.apply(module, :handle_subscribe, [subscriber, opts, from, mstate]) do
      {:automatic, %{state | state: new_state}}
    else
      _ ->
        {:automatic, state}
    end
  end

  @doc """
  Handle incoming events
  """
  def handle_events(events, from, %{module: module, state: mstate} = state) do
    with true <- function_exported?(module, :handle_events, 3) do
      case Kernel.apply(module, :handle_events, [events, from, mstate]) do
        {:noreply, new_state} ->
          {:noreply, [], %{state | state: new_state}}
        {:noreply, new_state, :hibernat} ->
          {:noreply, [], %{state | state: new_state}, :hibernate}
        {:stop, reason, new_state} ->
          {:stop, reason, %{state | state: new_state}}
      end
    else
      false ->
        {:reply, :ok, [], state}
    end
  end

  @doc """
  Handle a synchronous event notification
  """
  def handle_call(call, from, %{module: module, state: mstate} = state) do
    with true <- function_exported?(module, :handle_call, 3) do
      case Kernel.apply(module, :handle_call, [call, from, mstate]) do
        {:reply, reply, new_state} ->
          {:reply, reply, [], %{state | state: new_state}}
        other ->
          other
      end
    else
      false ->
        {:reply, :ok, [], state}
    end
  end

  @doc """
  Handle an asynchronous event notification
  """
  def handle_cast(call, %{module: module, state: mstate} = state) do
    with true <- function_exported?(module, :handle_cast, 2) do
      case Kernel.apply(module, :handle_cast, [call, mstate]) do
        {:noreply, new_state} ->
          {:noreply, [], %{state | state: new_state}}
        other ->
          other
      end
    else
      false ->
        {:noreply, [], state}
    end
  end

  @doc """
  Handle an incoming message
  """
  def handle_info(info, %{module: module, state: mstate} = state) do
    with true <- function_exported?(module, :handle_info, 2) do
      case Kernel.apply(module, :handle_info, [info, mstate]) do
        {:noreply, new_state} ->
          {:noreply, [], %{state | state: new_state}}
        other ->
          other
      end
    else
      false ->
        {:noreply, [], state}
    end
  end

  @doc """
  Handle a code change
  """
  def code_change(old_version, %{module: module, state: mstate} = state, extra) do
    with true <- function_exported?(module, :code_change, 3) do
      case Kernel.apply(module, :code_change, [old_version, mstate, extra]) do
        {:ok, new_state} ->
          {:ok, %{state | state: new_state}}
        {:error, reason} ->
          {:error, reason}
      end
    else
      false ->
        {:ok, state}
    end
  end

  @doc """
  Handle process termination
  """
  def terminate(reason, %{module: module, state: mstate}) do
    with true <- function_exported?(module, :terminate, 2) do
      Kernel.apply(module, :terminate, [reason, mstate])
    else
      false ->
        :ok
    end
  end

  #
  # Behaviour Callbacks
  #
  @opaque subscription_tag :: reference

  @type from :: {pid, subscription_tag}

  @callback handle_events(events :: [event], from, state :: term) ::
    {:noreply, new_state} |
    {:noreply, new_state, :hibernate} |
    {:stop, reason, new_state} when new_state: term, reason: term, event: term

  @callback handle_call(request :: term, from :: GenServer.from, state :: term) ::
    {:reply, reply, new_state} |
    {:reply, reply, [event], new_state} |
    {:reply, reply, [event], new_state, :hibernate} |
    {:noreply, new_state} |
    {:noreply, [event], new_state} |
    {:noreply, [event], new_state, :hibernate} |
    {:stop, reason, reply, new_state} |
    {:stop, reason, new_state} when reply: term, new_state: term, reason: term, event: term

  @callback handle_cast(request :: term, state :: term) ::
    {:noreply, new_state} |
    {:noreply, [event], new_state} |
    {:noreply, [event], new_state, :hibernate} |
    {:stop, reason :: term, new_state} when new_state: term, event: term

  @callback handle_info(message :: term, state :: term) ::
    {:noreply, new_state} |
    {:noreply, [event], new_state} |
    {:noreply, [event], new_state, :hibernate} |
    {:stop, reason :: term, new_state} when new_state: term, event: term

  @callback terminate(reason, state :: term) ::
    term when reason: :normal | :shutdown | {:shutdown, term} | term

  @callback code_change(old_vsn, state :: term, extra :: term) ::
    {:ok, new_state :: term} |
    {:error, reason :: term} when old_vsn: term | {:down, term}
  
  @optional_callbacks [
    handle_events: 3,
    code_change: 3,
    handle_call: 3,
    handle_cast: 2,
    handle_info: 2,
    terminate: 2
  ]
end