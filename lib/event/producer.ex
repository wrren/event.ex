defmodule Event.Producer do
  @moduledoc """
  Queues events for dissemination to subscribed consumers.
  """
  use GenStage
  defstruct module:     nil,
            state:      nil,
            opts:       nil,
            demand:     0,
            queue:      :queue.new()

  defmacro __using__(opts \\ []) do
    quote do
      import Event.Producer

      def start_link do
        Event.Producer.start_link(__MODULE__, [], unquote(opts))
      end

      @doc """
      Default initializer function
      """
      def init(args) do
        {:ok, args}
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
  Start an EventProducer process.
  """
  def start_link(module, args, opts) do
    opts = opts
    |> Keyword.take([:max_events, :dispatcher])
    |> Keyword.merge([module: module, args: args])

    GenStage.start_link(__MODULE__, opts, Keyword.drop(opts, [:max_events, :module, :args, :dispatcher]))
  end

  @doc """
  Synchronously notify the producer that an event has occurred. This call will block until
  the event has been consumed, or until the timeout is reached
  """
  def sync_notify(producer, event, timeout \\ 5_000) do
    GenStage.call(producer, {:ep_notify, event}, timeout)
  end

  @doc """
  Asynchronously notify the producer that an event has occurred. Returns immediately.
  """
  def async_notify(producer, event) do
    GenStage.cast(producer, {:ep_notify, event})
  end

  @doc """
  Send a message to the event producer and await a response.
  """
  def call(producer, call, timeout \\ 5_000) do
    GenStage.call(producer, call, timeout)
  end

  @doc """
  Send an asynchronous message to the event producer
  """
  def cast(producer, cast) do
    GenStage.cast(producer, cast)
  end

  @doc """
  Initialize event producer state
  """
  def init(opts) do
    dispatcher = opts[:dispatcher] || GenStage.BroadcastDispatcher

    with  true <- Module.defines?(opts[:module], {:init, 1}, :def),
          {:ok, state}  <- Kernel.apply(opts[:module], :init, opts[:args]) do
      {:producer, %Event.Producer{module: opts[:module], state: state, opts: opts}, dispatcher: dispatcher}
    else
      {:stop, reason} ->
        {:stop, reason}
      false ->
        {:producer, %Event.Producer{module: opts[:module], state: :ok, opts: opts}, dispatcher: dispatcher}
    end
  end

  @doc """
  Handle a subscription
  """
  def handle_subscribe(producer_or_consumer, opts, from, %{module: module, state: mstate} = state) do
    with  true <- Module.defines?(module, {:handle_subscribe, 4}, :def),
          {_, new_state}  <- Kernel.apply(module, :handle_subscribe, [producer_or_consumer, opts, from, mstate]) do
      {:automatic, %{state | state: new_state}}
    else
      _ ->
        {:automatic, state}
    end
  end

  @doc """
  Handle a synchronous event notification
  """
  def handle_call({:ep_notify, event}, from, state) do
    maybe_dispatch({:sync, from, event}, state)
  end
  def handle_call(call, from, %{module: module, state: mstate} = state) do
    with true <- Module.defines?(module, {:handle_call, 3}, :def) do
      case Kernel.apply(module, :handle_call, [call, from, mstate]) do
        {:reply, reply, events, new_state} ->
          maybe_dispatch(Enum.map(events, fn e -> {:sync, from, reply, e} end), %{state | state: new_state})
        {:reply, reply, events, new_state, _} ->
          maybe_dispatch(Enum.map(events, fn e -> {:sync, from, reply, e} end), %{state | state: new_state})
        {:noreply, events, new_state} ->
          maybe_dispatch(Enum.map(events, fn e -> {:async, e} end), %{state | state: new_state})  
        {:noreply, events, new_state, _} ->
          maybe_dispatch(Enum.map(events, fn e -> {:async, e} end), %{state | state: new_state})
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
  def handle_cast({:ep_notify, event}, state) do
    maybe_dispatch({:async, event}, state)
  end
  def handle_cast(call, %{module: module, state: mstate} = state) do
    with true <- Module.defines?(module, {:handle_cast, 2}, :def) do
      case Kernel.apply(module, :handle_cast, [call, mstate]) do
        {:noreply, events, new_state} ->
          maybe_dispatch(Enum.map(events, fn e -> {:async, e} end), %{state | state: new_state})
        {:noreply, events, new_state, _} ->
          maybe_dispatch(Enum.map(events, fn e -> {:async, e} end), %{state | state: new_state})
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
    with true <- Module.defines?(module, {:handle_info, 2}, :def) do
      case Kernel.apply(module, :handle_info, [info, mstate]) do
        {:noreply, events, new_state} ->
          maybe_dispatch(Enum.map(events, fn e -> {:async, e} end), %{state | state: new_state})
        {:noreply, events, new_state, _} ->
          maybe_dispatch(Enum.map(events, fn e -> {:async, e} end), %{state | state: new_state})
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
  Conditionally enqueue and dispatch the given event based on options such as
  the max allowed number of queued items
  """
  def maybe_dispatch([event | t], %{queue: queue} = state) do
    case {state.opts[:max_events], :queue.len(queue), event} do
      {max, max, {:sync, from, _}} ->
        GenStage.reply(from, {:error, :queue_full})
        maybe_dispatch(t, state)
      {max, max, _} ->
        maybe_dispatch(t, state)
      _ ->
        maybe_dispatch(t, %{state | queue: :queue.in(event, queue)})
    end
  end
  def maybe_dispatch([], state) do
    dispatch_events(state, [])
  end
  def maybe_dispatch(event, state) do
    maybe_dispatch([event], state)
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
      {{:value, {:sync, from, reply, event}}, queue} ->
        GenStage.reply(from, reply)
        dispatch_events(%{state | queue: queue, demand: demand - 1}, [event | events])
      {{:value, {:sync, from, event}}, queue} ->
        GenStage.reply(from, :ok)
        dispatch_events(%{state | queue: queue, demand: demand - 1}, [event | events])
      {{:value, {:async, event}}, queue} ->
        dispatch_events(%{state | queue: queue, demand: demand - 1}, [event | events])
      {:empty, queue} ->
        {:noreply, Enum.reverse(events), %{state | queue: queue}}
    end
  end
end