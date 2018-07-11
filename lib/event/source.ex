defmodule Event.Source do
  @moduledoc """
  Queues events for dissemination to subscribed processors and sinks. Buffers demand
  for events so that when the queue is refilled, connected processors and sinks receive
  them. Exposes various options for limiting buffering, as well as GenStage control options.
  """
  use GenStage
  defstruct module:     nil,
            state:      nil,
            opts:       nil,
            demand:     0,
            queue:      :queue.new()

  defmacro __using__(opts \\ []) do
    quote do
      import Event.Source
      @behaviour Event.Source

      def start_link,
        do: Event.Source.start_link(__MODULE__, [], unquote(opts))

      @doc """
      Default initializer function
      """
      def init(args),
        do: {:ok, args}

      @doc """
      Handle a synchronous call
      """
      def handle_call(_call, _from, state),
        do: {:reply, :ok, [], state}

      @doc """
      Handle an asynchronous cast
      """
      def handle_cast(_cast, state),
        do: {:noreply, [], state}

      @doc """
      Default handler for incoming messages.
      """
      def handle_info(_info, state), 
        do: {:noreply, [], state}

      @doc """
      Handle a code change
      """
      def code_change(_old_version, state, _extra), 
        do: {:ok, state}
      

      def terminate(_reason, _state),
        do: :ok

      defoverridable [init: 1, handle_call: 3, handle_cast: 2, handle_info: 2, code_change: 3, terminate: 2]
    end
  end

  @doc """
  Start an EventSource process.
  """
  def start_link(module, args, opts) do
    sopts = opts
    |> Keyword.take([:max_events, :dispatcher])
    |> Keyword.merge([module: module, args: args])
    |> Keyword.put_new(:dispatcher, GenStage.BroadcastDispatcher)

    GenStage.start_link(__MODULE__, sopts, Keyword.drop(opts, [:max_events, :module, :args, :dispatcher]))
  end

  @doc """
  Synchronously notify the source that an event has occurred. This call will block until
  the event has been consumed, or until the timeout is reached
  """
  def sync_notify(source, event, timeout \\ 5_000) do
    GenStage.call(source, {:es_notify, event}, timeout)
  end

  @doc """
  Asynchronously notify the source that an event has occurred. Returns immediately.
  """
  def async_notify(source, event) do
    GenStage.cast(source, {:es_notify, event})
  end

  @doc """
  Get the event queue for the given source
  """
  def queue(source, timeout \\ 5_000) do
    GenStage.call(source, :es_queue, timeout)
  end

  @doc """
  Send a message to the event source and await a response.
  """
  def call(source, call, timeout \\ 5_000) do
    GenStage.call(source, call, timeout)
  end

  @doc """
  Send an asynchronous message to the event source
  """
  def cast(source, cast) do
    GenStage.cast(source, cast)
  end

  @doc """
  Initialize event source state
  """
  def init(opts) do
    stage_opts = opts
    |> Keyword.take([:demand, :buffer_size, :buffer_keep, :dispatcher])

    with true <- function_exported?(opts[:module], :init, 1) do
      case Kernel.apply(opts[:module], :init, [opts[:args]]) do
        {:ok, state} ->
          {:producer, %Event.Source{module: opts[:module], state: state, opts: opts}, stage_opts}
        {:ok, state, init_opts} ->
          opts = Keyword.merge(opts, init_opts)
          {:producer, %Event.Source{module: opts[:module], state: state, opts: opts}, stage_opts}
        other ->
          other
      end
    else
      {:stop, reason} ->
        {:stop, reason}
      false ->
        {:producer, %Event.Source{module: opts[:module], state: :ok, opts: opts}, stage_opts}
    end
  end

  @doc """
  Handle a subscription
  """
  def handle_subscribe(subscriber, opts, from, %{module: module, state: mstate} = state) do
    with  true <- function_exported?(module, :handle_subscribe, 4) ,
          {_, new_state}  <- Kernel.apply(module, :handle_subscribe, [subscriber, opts, from, mstate]) do
      {:automatic, %{state | state: new_state}}
    else
      _ ->
        {:automatic, state}
    end
  end

  @doc """
  Handle a synchronous event notification
  """
  def handle_call({:es_notify, event}, from, state) do
    maybe_dispatch({:sync, from, [event]}, state)
  end
  def handle_call(:es_queue, _from, %{queue: queue} = state) do
    {:reply, {:ok, queue}, [], state}
  end
  def handle_call(call, from, %{module: module, state: mstate} = state) do
    with true <- function_exported?(module, :handle_call, 3) do
      case Kernel.apply(module, :handle_call, [call, from, mstate]) do
        {:reply, reply, new_state} ->
          {:reply, reply, [], %{state | state: new_state}}
        {:reply, reply, events, new_state} ->
          maybe_dispatch({:sync, from, reply, events}, %{state | state: new_state})
        {:reply, reply, events, new_state, _} ->
          maybe_dispatch({:sync, from, reply, events}, %{state | state: new_state})
        {:noreply, new_state} ->
          {:noreply, [], %{state | state: new_state}}
        {:noreply, events, new_state} ->
          maybe_dispatch({:async, events}, %{state | state: new_state})  
        {:noreply, events, new_state, _} ->
          maybe_dispatch({:async, events}, %{state | state: new_state})
        stop ->
          stop
      end
    else
      false ->
        {:reply, :ok, [], state}
    end
  end

  @doc """
  Handle an asynchronous event notification
  """
  def handle_cast({:es_notify, event}, state) do
    maybe_dispatch({:async, [event]}, state)
  end
  def handle_cast(call, %{module: module, state: mstate} = state) do
    with true <- function_exported?(module, :handle_cast, 2) do
      case Kernel.apply(module, :handle_cast, [call, mstate]) do
        {:noreply, new_state} ->
          {:noreply, [], %{state | state: new_state}}
        {:noreply, events, new_state} ->
          maybe_dispatch({:async, events}, %{state | state: new_state})
        {:noreply, events, new_state, _} ->
          maybe_dispatch({:async, events}, %{state | state: new_state})
        stop ->
          stop
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
        {:noreply, events, new_state} ->
          maybe_dispatch({:async, events}, %{state | state: new_state})
        {:noreply, events, new_state, _} ->
          maybe_dispatch({:async, events}, %{state | state: new_state})
        stop ->
          stop
      end
    else
      false ->
        {:noreply, [], state}
    end
  end

  @doc """
  Handle demand for new events
  """
  def handle_demand(new_demand, %{demand: old_demand} = state) do
    dispatch_events(%{state | demand: new_demand + old_demand}, [])
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

  @doc """
  Conditionally enqueue and dispatch the given event based on options such as
  the max allowed number of queued items
  """
  def maybe_dispatch({:sync, from, reply, events}, state) do
    GenServer.reply(from, reply)

    events
    |> Enum.reduce(state, &__MODULE__.maybe_enqueue/2)
    |> dispatch_events([])
  end
  def maybe_dispatch({:sync, from, events}, state) do
    maybe_dispatch({:sync, from, :ok, events}, state)
  end
  def maybe_dispatch({:async, events}, state) do
    events
    |> Enum.reduce(state, &__MODULE__.maybe_enqueue/2)
    |> dispatch_events([])
  end

  @doc """
  Enqueue the given event if the event queue's length is less than the configured maximum
  """
  def maybe_enqueue(event, %{queue: queue} = state) do
    case {state.opts[:max_events], :queue.len(queue)} do
      {max, max} ->
        state
      {_, _} ->
        %{state | queue: :queue.in(event, queue)}
    end
  end

  @doc """
  Dispatch as many events as possible until demand reaches zero or 
  we run out of buffered events
  """
  def dispatch_events(%{demand: 0} = state, events) do
    {:noreply, Enum.reverse(events), state}
  end
  def dispatch_events(%{queue: queue, demand: demand} = state, events) do
    case :queue.out(queue) do
      {{:value, event}, queue} ->
        dispatch_events(%{state | queue: queue, demand: demand - 1}, [event | events])
      {:empty, queue} ->
        {:noreply, Enum.reverse(events), %{state | queue: queue}}
    end
  end

  #
  # Behaviour Definition
  #
  @typedoc "Option values used by the `init*` specific to `:producer` type"
  @type producer_only_option :: {:demand, :forward | :accumulate}

  @typedoc "Option values used by the `init*` common to `:producer` and `:producer_consumer` types"
  @type producer_and_producer_consumer_option :: {:buffer_size, non_neg_integer | :infinity} |
                           {:buffer_keep, :first | :last} |
                           {:dispatcher, module | {module, GenStage.Dispatcher.options}}
  
  @typedoc "Option values used by the `init*` functions when stage type is `:producer`"
  @type producer_option :: producer_only_option | producer_and_producer_consumer_option

  @callback init(args :: term) ::
    {:ok, state} |
    {:ok, state, [producer_option]} |
    :ignore |
    {:stop, reason :: any} when state: any

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
    code_change: 3,
    handle_call: 3,
    handle_cast: 2,
    handle_info: 2,
    terminate: 2
  ]
end