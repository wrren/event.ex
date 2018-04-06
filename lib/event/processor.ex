defmodule Event.Processor do
  @moduledoc """
  Receives events from Event.Source or Event.Processor before passing them
  on to the next connected event handler(s)
  """
  use GenStage
  defstruct module:     nil,
            state:      nil,
            opts:       nil

  defmacro __using__(opts \\ []) do
    quote do
      import Event.Processor, only: [sync_notify: 3, async_notify: 2]
      @behaviour Event.Processor

      @doc """
      Start an Event Processor
      """
      def start_link do
        Event.Processor.start_link(__MODULE__, [], unquote(opts))
      end

      @doc """
      Start an Event Processor
      """
      def start_link(module, args, opts) do
        Event.Processor.start_link(__MODULE__, args, opts)
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

      defoverridable [init: 1, handle_call: 3, handle_cast: 2, handle_info: 2]
    end
  end

  @doc """
  Start an EventProcessor process.
  """
  def start_link(module, args, opts) do
    GenStage.start_link(
      __MODULE__, 
      Keyword.merge(opts, [module: module, args: args]), 
      Keyword.drop(opts, [:module, :args])
    )
  end

  @doc """
  Synchronously notify the processor that an event has occurred. This call will block until
  the event has been consumed, or until the timeout is reached
  """
  def sync_notify(processor, event, timeout \\ 5_000) do
    GenStage.call(processor, {:ep_notify, event}, timeout)
  end

  @doc """
  Asynchronously notify the processor that an event has occurred. Returns immediately.
  """
  def async_notify(processor, event) do
    GenStage.cast(processor, {:ep_notify, event})
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
    with true <- function_exported?(opts[:module], :init, 1)do
      case Kernel.apply(opts[:module], :init, opts[:args]) do
        {:ok, state} ->
          {:producer_consumer, %Event.Source{module: opts[:module], state: state, opts: opts}, opts}
        {:ok, state, init_opts} ->
          opts = Keyword.merge(opts, init_opts)
          {:producer_consumer, %Event.Source{module: opts[:module], state: state, opts: opts}, opts}
        other ->
          other
      end
    else
      {:stop, reason} ->
        {:stop, reason}
      false ->
        {:producer_consumer, %Event.Source{module: opts[:module], state: :ok, opts: opts}, opts}
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
      Kernel.apply(module, :handle_events, [events, from, mstate])
    else
      false ->
        {:reply, :ok, [], state}
    end
  end

  @doc """
  Handle a synchronous event notification
  """
  def handle_call({:ep_notify, event}, _from, state) do
    {:reply, :ok, [event], state}
  end
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
  def handle_cast({:ep_notify, event}, state) do
    {:noreply, [event], state}
  end
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
    {:noreply, [event], new_state} |
    {:noreply, [event], new_state, :hibernate} |
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