defmodule StarterPort do
  use GenServer

  # Many calls take timeouts for how long to wait for reading and writing
  # serial ports. This is the additional time added to the GenServer message passing
  # timeout so that the interprocess messaging timers don't hit before the
  # timeouts on the actual operations.
  @genserver_timeout_slack 500

  # There's a timeout when interacting with the port as well. If the port
  # doesn't respond by timeout + @port_timeout_slack, then there's something
  # wrong with it.
  @port_timeout_slack 400

  @moduledoc """
  Find and use starter_ports, serial ports, and more.
  """

  defmodule State do
    @moduledoc false

    # port: C port process
    # controlling_process: where events get sent
    # name: port name when opened
    # is_active: active or passive mode
    defstruct port: nil,
              controlling_process: nil,
              name: :closed,
              is_active: true,
              id: :name
  end

  @type starter_port_option ::
          {:active, boolean}
          | {:speed, non_neg_integer}
          | {:data_bits, 5..8}
          | {:stop_bits, 1..2}
          | {:id, :name | :pid}

  # Public API

  @doc """
  Start up a starter_port GenServer.
  """
  @spec start_link([term]) :: {:ok, pid} | {:error, term}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, [], opts)
  end

  @doc """
  Stop the starter_port GenServer.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(pid) do
    GenServer.stop(pid)
  end

  @spec open(GenServer.server(), binary, [starter_port_option]) :: :ok | {:error, term}
  def open(pid, name, opts \\ []) do
    GenServer.call(pid, {:open, name, opts})
  end

  @spec close(GenServer.server()) :: :ok | {:error, term}
  def close(pid) do
    GenServer.call(pid, :close)
  end

  @spec configure(GenServer.server(), [starter_port_option]) :: :ok | {:error, term}
  def configure(pid, opts) do
    GenServer.call(pid, {:configure, opts})
  end

  @spec configuration(GenServer.server()) :: {binary() | :closed, [starter_port_option]}
  def configuration(pid) do
    GenServer.call(pid, :configuration)
  end

  @doc """
  Send a continuous stream of zero bits for a duration in milliseconds.
  By default, the zero bits are transmitted at least 0.25 seconds.

  This is a convenience function for calling `set_break/2` to enable
  the break signal, wait, and then turn it off.
  """
  @spec send_break(GenServer.server(), integer) :: :ok | {:error, term}
  def send_break(pid, duration \\ 250) do
    :ok = set_break(pid, true)
    :timer.sleep(duration)
    set_break(pid, false)
  end

  @doc """
  Start or stop sending a break signal.
  """
  @spec set_break(GenServer.server(), boolean) :: :ok | {:error, term}
  def set_break(pid, value) when is_boolean(value) do
    GenServer.call(pid, {:set_break, value})
  end

  @doc """
  Write data to the opened starter_port. It's possible for the write to return before all
  of the data is actually transmitted. To wait for the data, call drain/1.

  This call blocks until all of the data to be written is in the operating
  system's internal buffers. If you're sending a lot of data on a slow link,
  supply a longer timeout to avoid timing out prematurely.

  Returns `:ok` on success or `{:error, reason}` if an error occurs.

  Typical error reasons:

    * `:ebadf` - the starter_port is closed
  """
  @spec write(GenServer.server(), iodata(), non_neg_integer()) :: :ok | {:error, term}
  def write(pid, data, timeout \\ 5000) do
    GenServer.call(pid, {:write, data, timeout}, genserver_timeout(timeout))
  end

  @doc """
  Read data from the starter_port. This call returns data as soon as it's available or
  after timing out.

  Returns `{:ok, binary}`, where `binary` is a binary data object that contains the
  read data, or `{:error, reason}` if an error occurs.

  Typical error reasons:

    * `:ebadf` - the starter_port is closed
    * `:einval` - the starter_port is in active mode
  """
  @spec read(GenServer.server(), non_neg_integer()) :: {:ok, binary} | {:error, term}
  def read(pid, timeout \\ 5000) do
    GenServer.call(pid, {:read, timeout}, genserver_timeout(timeout))
  end

  @doc """
  Waits until all data has been transmitted. See
  [tcdrain(3)](http://linux.die.net/man/3/tcdrain) for low level details on
  Linux or OSX. This is not implemented on Windows.
  """
  @spec drain(GenServer.server()) :: :ok | {:error, term}
  def drain(pid) do
    GenServer.call(pid, :drain)
  end

  @doc """
  Flushes the `:receive` buffer, the `:transmit` buffer, or `:both`.

  See [tcflush(3)](http://linux.die.net/man/3/tcflush) for low level details on
  Linux or OSX. This calls `PurgeComm` on Windows.
  """
  @spec flush(GenServer.server()) :: :ok | {:error, term}
  def flush(pid, direction \\ :both) do
    GenServer.call(pid, {:flush, direction})
  end

  @doc """
  Returns a map of signal names and their current state (true or false).
  Signals include:

    * `:dsr` - Data Set Ready
    * `:dtr` - Data Terminal Ready
    * `:rts` - Request To Send
    * `:st`  - Secondary Transmitted Data
    * `:sr`  - Secondary Received Data
    * `:cts` - Clear To Send
    * `:cd`  - Data Carrier Detect
    * `:rng` - Ring Indicator
  """
  @spec signals(GenServer.server()) :: map | {:error, term}
  def signals(pid) do
    GenServer.call(pid, :signals)
  end

  @doc """
  Set or clear the Data Terminal Ready signal.
  """
  @spec set_dtr(GenServer.server(), boolean) :: :ok | {:error, term}
  def set_dtr(pid, value) when is_boolean(value) do
    GenServer.call(pid, {:set_dtr, value})
  end

  @doc """
  Set or clear the Request To Send signal.
  """
  @spec set_rts(GenServer.server(), boolean) :: :ok | {:error, term}
  def set_rts(pid, value) when is_boolean(value) do
    GenServer.call(pid, {:set_rts, value})
  end

  @doc """
  Change the controlling process that
  receives events from an active starter_port.
  """
  @spec controlling_process(GenServer.server(), pid) :: :ok | {:error, term}
  def controlling_process(pid, controlling_process) when is_pid(controlling_process) do
    GenServer.call(pid, {:controlling_process, controlling_process})
  end

  # gen_server callbacks
  def init([]) do
    executable = Application.app_dir(:starter_port, ["priv", "starter_port"]) |> to_charlist()

    port =
      Port.open({:spawn_executable, executable}, [
        {:args, []},
        {:packet, 2},
        :use_stdio,
        :binary,
        :exit_status
      ])

    state = %State{port: port}
    {:ok, state}
  end

  def handle_call({:open, name, opts}, {from_pid, _}, state) do
    is_active = Keyword.get(opts, :active, true)
    id_mode = Keyword.get(opts, :id, :name)

    response = call_port(state, :open, {name, opts})

    new_state = %{
      state
      | name: name,
        controlling_process: from_pid,
        is_active: is_active,
        id: id_mode
    }

    {:reply, response, new_state}
  end

  def handle_call(:configuration, _from, state) do
    opts =
      call_port(state, :configuration, {}) ++
        [
          active: state.is_active,
          id: state.id,
          rx_framing_timeout: state.rx_framing_timeout,
          framing: state.framing
        ]

    {:reply, {state.name, opts}, state}
  end

  def handle_call(:close, _from, state) do
    # Clean up the C side
    response = call_port(state, :close, nil)

    # Clean up the Elixir side
    new_framing_state = apply(state.framing, :flush, [:both, state.framing_state])

    new_state =
      handle_framing_timer(
        %{state | name: :closed, framing_state: new_framing_state, queued_messages: []},
        :ok
      )

    {:reply, response, new_state}
  end

  def handle_call({:read, _timeout}, _from, %{queued_messages: [message | rest]} = state) do
    # Return the queued response.
    new_state = %{state | queued_messages: rest}
    {:reply, {:ok, message}, new_state}
  end

  def handle_call({:read, timeout}, from, state) do
    call_time = System.monotonic_time(:millisecond)
    # Poll the serial port
    case call_port(state, :read, timeout, port_timeout(timeout)) do
      {:ok, <<>>} ->
        # Timeout
        {:reply, {:ok, <<>>}, state}

      {:ok, buffer} ->
        # More data
        {rc, messages, new_framing_state} =
          apply(state.framing, :remove_framing, [buffer, state.framing_state])

        new_state = handle_framing_timer(%{state | framing_state: new_framing_state}, rc)

        if messages == [] do
          # If nothing, poll some more with reduced timeout
          elapsed = System.monotonic_time(:millisecond) - call_time
          retry_timeout = max(timeout - elapsed, 0)
          handle_call({:read, retry_timeout}, from, new_state)
        else
          # Return the first message
          [first_message | rest] = messages
          new_state = %{new_state | queued_messages: rest}
          {:reply, {:ok, first_message}, new_state}
        end

      response ->
        # Error
        {:reply, response, state}
    end
  end

  def handle_call({:write, data, timeout}, _from, state) do
    bin_data = IO.iodata_to_binary(data)

    {:ok, framed_data, new_framing_state} =
      apply(state.framing, :add_framing, [bin_data, state.framing_state])

    response = call_port(state, :write, {framed_data, timeout}, port_timeout(timeout))
    new_state = %{state | framing_state: new_framing_state}
    {:reply, response, new_state}
  end

  def handle_call({:configure, opts}, _from, state) do
    new_framing = Keyword.get(opts, :framing, nil)
    new_rx_framing_timeout = Keyword.get(opts, :rx_framing_timeout, state.rx_framing_timeout)
    is_active = Keyword.get(opts, :active, state.is_active)
    id_mode = Keyword.get(opts, :id, state.id)

    state =
      change_framing(
        %{state | rx_framing_timeout: new_rx_framing_timeout, is_active: is_active, id: id_mode},
        new_framing
      )

    response = call_port(state, :configure, opts)
    {:reply, response, state}
  end

  def handle_call(:drain, _from, state) do
    response = call_port(state, :drain, nil)
    {:reply, response, state}
  end

  def handle_call({:flush, direction}, _from, state) do
    fstate = apply(state.framing, :flush, [direction, state.framing_state])
    new_state = %{state | framing_state: fstate}
    response = call_port(new_state, :flush, direction)
    {:reply, response, new_state}
  end

  def handle_call(:signals, _from, state) do
    response = call_port(state, :signals, nil)
    {:reply, response, state}
  end

  def handle_call({:set_dtr, value}, _from, state) do
    response = call_port(state, :set_dtr, value)
    {:reply, response, state}
  end

  def handle_call({:set_rts, value}, _from, state) do
    response = call_port(state, :set_rts, value)
    {:reply, response, state}
  end

  def handle_call({:set_break, value}, _from, state) do
    response = call_port(state, :set_break, value)
    {:reply, response, state}
  end

  def handle_call({:controlling_process, pid}, _from, state) do
    new_state = %{state | controlling_process: pid}
    {:reply, :ok, new_state}
  end

  def handle_info({_, {:data, <<?n, message::binary>>}}, state) do
    msg = :erlang.binary_to_term(message)
    handle_port(msg, state)
  end

  def handle_info(:rx_framing_timed_out, state) do
    {:ok, messages, new_framing_state} =
      apply(state.framing, :frame_timeout, [state.framing_state])

    new_state =
      notify_timedout_messages(
        %{state | rx_framing_tref: nil, framing_state: new_framing_state},
        messages
      )

    {:noreply, new_state}
  end

  defp notify_timedout_messages(%{is_active: true, controlling_process: dest} = state, messages)
       when dest != nil do
    Enum.each(messages, &report_message(state, &1))
    state
  end

  defp notify_timedout_messages(%{is_active: false} = state, messages) do
    # IO.puts("Queuing... #{inspect(messages)}")
    new_queued_messages = state.queued_messages ++ messages
    %{state | queued_messages: new_queued_messages}
  end

  defp notify_timedout_messages(state, _messages), do: state

  defp change_framing(state, nil), do: state

  defp change_framing(state, framing_mod) when is_atom(framing_mod) do
    change_framing(state, {framing_mod, []})
  end

  defp change_framing(state, {framing_mod, framing_args}) do
    {:ok, framing_state} = apply(framing_mod, :init, [framing_args])
    %{state | framing: framing_mod, framing_state: framing_state}
  end

  defp call_port(state, command, arguments, timeout \\ 4000) do
    msg = {command, arguments}
    send(state.port, {self(), {:command, :erlang.term_to_binary(msg)}})
    # Block until the response comes back since the C side
    # doesn't want to handle any queuing of requests. REVISIT
    receive do
      {_, {:data, <<?r, response::binary>>}} ->
        :erlang.binary_to_term(response)
    after
      timeout ->
        # Not sure how this can be recovered
        exit(:port_timed_out)
    end
  end

  defp handle_port({:notif, data}, state) when is_binary(data) do
    # IO.puts "Received data on port #{state.name}"
    {rc, messages, new_framing_state} =
      apply(state.framing, :remove_framing, [data, state.framing_state])

    new_state = handle_framing_timer(%{state | framing_state: new_framing_state}, rc)

    if state.controlling_process do
      Enum.each(messages, &report_message(new_state, &1))
    end

    {:noreply, new_state}
  end

  defp handle_port({:notif, data}, state) do
    # Report an error from the port
    if state.controlling_process do
      report_message(state, data)
    end

    {:noreply, state}
  end

  defp report_message(state, message) do
    event = {:starter_port, message_id(state.id, state.name), message}
    send(state.controlling_process, event)
  end

  defp message_id(:pid, _name), do: self()
  defp message_id(:name, name), do: name

  defp genserver_timeout(timeout) when timeout >= 0 do
    timeout + @genserver_timeout_slack
  end

  defp port_timeout(timeout) when timeout >= 0 do
    timeout + @port_timeout_slack
  end

  # Stop the framing timer if active and a frame completed
  defp handle_framing_timer(%{rx_framing_tref: tref} = state, :ok) when tref != nil do
    _ = :timer.cancel(tref)
    %{state | rx_framing_tref: tref}
  end

  # Start the framing timer if ended on an incomplete frame
  defp handle_framing_timer(%{rx_framing_timeout: timeout} = state, :in_frame) when timeout > 0 do
    _ = if state.rx_framing_tref, do: :timer.cancel(state.rx_framing_tref)
    {:ok, tref} = :timer.send_after(timeout, :rx_framing_timed_out)
    %{state | rx_framing_tref: tref}
  end

  # Don't do anything with the framing timer for all other reasons
  defp handle_framing_timer(state, _rc), do: state
end
