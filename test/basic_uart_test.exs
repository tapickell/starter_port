Code.require_file("starter_port_test.exs", __DIR__)

defmodule Basicstarter_portTest do
  use ExUnit.Case
  alias Starter.Port

  setup do
    starter_portTest.common_setup()
  end

  defp test_send_and_receive(starter_port1, starter_port2, options) do
    all_options = [{:active, false} | options]

    assert :ok = starter_port.open(starter_port1, starter_portTest.port1(), all_options)
    assert :ok = starter_port.open(starter_port2, starter_portTest.port2(), all_options)

    # starter_port1 -> starter_port2
    assert :ok = starter_port.write(starter_port1, "A")
    assert {:ok, "A"} = starter_port.read(starter_port2)

    # starter_port2 -> starter_port1
    assert :ok = starter_port.write(starter_port2, "B")
    assert {:ok, "B"} = starter_port.read(starter_port1)

    starter_port.close(starter_port1)
    starter_port.close(starter_port2)
  end

  test "serial ports exist" do
    ports = starter_port.enumerate()
    assert is_map(ports)
    assert Map.has_key?(ports, starter_portTest.port1()), "Can't find #{starter_portTest.port1()}"
    assert Map.has_key?(ports, starter_portTest.port2()), "Can't find #{starter_portTest.port2()}"
  end

  test "simple open and close", %{starter_port1: starter_port1} do
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1(), speed: 9600)
    assert :ok = starter_port.close(starter_port1)

    assert :ok = starter_port.open(starter_port1, starter_portTest.port2())
    assert :ok = starter_port.close(starter_port1)

    starter_port.close(starter_port1)
  end

  test "open same port twice", %{starter_port1: starter_port1, starter_port2: starter_port2} do
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1())
    assert {:error, _} = starter_port.open(starter_port2, starter_portTest.port1())

    starter_port.close(starter_port1)
  end

  test "write and read", %{starter_port1: starter_port1, starter_port2: starter_port2} do
    test_send_and_receive(starter_port1, starter_port2, [])
  end

  test "write iodata", %{starter_port1: starter_port1, starter_port2: starter_port2} do
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1(), active: false)
    assert :ok = starter_port.open(starter_port2, starter_portTest.port2(), active: false)

    assert :ok = starter_port.write(starter_port1, 'B')
    assert {:ok, "B"} = starter_port.read(starter_port2)

    assert :ok = starter_port.write(starter_port1, ['AB', ?C, 'D', "EFG"])

    # Wait for everything to be received in one call
    :timer.sleep(100)
    assert {:ok, "ABCDEFG"} = starter_port.read(starter_port2)

    starter_port.close(starter_port1)
    starter_port.close(starter_port2)
  end

  test "no cr and lf translations", %{starter_port1: starter_port1, starter_port2: starter_port2} do
    # It is very common for CR and NL characters to
    # be translated through ttys and serial ports, so
    # check this explicitly.
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1(), active: false)
    assert :ok = starter_port.open(starter_port2, starter_portTest.port2(), active: false)

    assert :ok = starter_port.write(starter_port1, "\n")
    assert {:ok, "\n"} = starter_port.read(starter_port2)

    assert :ok = starter_port.write(starter_port1, "\r")
    assert {:ok, "\r"} = starter_port.read(starter_port2)

    starter_port.close(starter_port1)
    starter_port.close(starter_port2)
  end

  test "all characters pass unharmed", %{
    starter_port1: starter_port1,
    starter_port2: starter_port2
  } do
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1(), active: false)
    assert :ok = starter_port.open(starter_port2, starter_portTest.port2(), active: false)

    # The default is 8-N-1, so this should all work
    for char <- 0..255 do
      assert :ok = starter_port.write(starter_port1, <<char>>)
      assert {:ok, <<^char>>} = starter_port.read(starter_port2)
    end

    starter_port.close(starter_port1)
    starter_port.close(starter_port2)
  end

  test "send and flush", %{starter_port1: starter_port1, starter_port2: starter_port2} do
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1(), active: false)
    assert :ok = starter_port.open(starter_port2, starter_portTest.port2(), active: false)

    assert :ok = starter_port.write(starter_port1, "a")
    :timer.sleep(100)

    assert :ok = starter_port.flush(starter_port2, :receive)
    assert {:ok, ""} = starter_port.read(starter_port2, 0)

    assert :ok = starter_port.write(starter_port1, "b")
    :timer.sleep(100)

    assert :ok = starter_port.flush(starter_port2, :both)
    assert {:ok, ""} = starter_port.read(starter_port2, 0)

    assert :ok = starter_port.write(starter_port1, "c")
    :timer.sleep(100)

    # unspecifed direction should be :both
    assert :ok = starter_port.flush(starter_port2)
    assert {:ok, ""} = starter_port.read(starter_port2, 0)

    starter_port.close(starter_port1)
    starter_port.close(starter_port2)
  end

  test "send more than can be done synchronously", %{
    starter_port1: starter_port1,
    starter_port2: starter_port2
  } do
    # Note: When using the tty0tty driver, both endpoints need to be
    #       opened or writes will fail with :einval. This is different
    #       than most regular starter_ports where writes to nothing just twiddle
    #       output bits.
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1())
    assert :ok = starter_port.open(starter_port2, starter_portTest.port2())

    # Try a big size to trigger a write that can't complete
    # immediately. This doesn't always work.
    lots_o_data = :binary.copy("a", 5000)

    # Allow 10 seconds for write to give it time to complete
    assert :ok = starter_port.write(starter_port1, lots_o_data, 10000)

    starter_port.close(starter_port1)
    starter_port.close(starter_port2)
  end

  test "send timeout", %{starter_port1: starter_port1} do
    # Don't run against tty0tty since it sends data almost
    # instantaneously. Also, Windows appears to have a deep
    # send buffer. Need to investigate the Windows failure more.
    if !String.starts_with?(starter_portTest.port1(), "tnt") && !:os.type() == {:windows, :nt} do
      assert :ok = starter_port.open(starter_port1, starter_portTest.port1(), speed: 1200)

      # Send more than can be sent on a 1200 baud link
      # in 10 milliseconds
      lots_o_data = :binary.copy("a", 5000)
      assert {:error, :eagain} = starter_port.write(starter_port1, lots_o_data, 10)

      starter_port.close(starter_port1)
    end
  end

  test "sends coalesce into one read", %{
    starter_port1: starter_port1,
    starter_port2: starter_port2
  } do
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1(), active: false)
    assert :ok = starter_port.open(starter_port2, starter_portTest.port2(), active: false)

    assert :ok = starter_port.write(starter_port1, "a")
    assert :ok = starter_port.write(starter_port1, "b")
    assert :ok = starter_port.write(starter_port1, "c")

    :timer.sleep(100)

    assert {:ok, "abc"} = starter_port.read(starter_port2)

    starter_port.close(starter_port1)
    starter_port.close(starter_port2)
  end

  test "error writing to a closed port", %{
    starter_port1: starter_port1,
    starter_port2: starter_port2
  } do
    assert :ok = starter_port.open(starter_port2, starter_portTest.port2(), active: false)

    # port1 not yet opened
    assert {:error, :ebadf} = starter_port.write(starter_port1, "A")

    # port1 opened
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1(), active: false)
    assert :ok = starter_port.write(starter_port1, "A")
    assert {:ok, "A"} = starter_port.read(starter_port2)

    # port1 closed
    assert :ok = starter_port.close(starter_port1)
    assert {:error, :ebadf} = starter_port.write(starter_port1, "B")

    starter_port.close(starter_port1)
    starter_port.close(starter_port2)
  end

  test "open doesn't return error AND send a message when in active mode", %{
    starter_port1: starter_port1
  } do
    :ok = starter_port.configure(starter_port1, active: true)
    {:error, _} = starter_port.open(starter_port1, "does_not_exist")
    refute_received {:starter_port, _port, _}, "No messages should be sent if open returns error"

    :ok = starter_port.configure(starter_port1, active: false)
    {:error, _} = starter_port.open(starter_port1, "does_not_exist", active: true)
    refute_received {:starter_port, _port, _}, "No messages should be sent if open returns error"
  end

  test "open doesn't send messages in passive mode for open errors", %{
    starter_port1: starter_port1
  } do
    :ok = starter_port.configure(starter_port1, active: false)
    {:error, :enoent} = starter_port.open(starter_port1, "does_not_exist")
    refute_received {:starter_port, _, _}, "No messages should be sent in passive mode"

    {:error, :enoent} = starter_port.open(starter_port1, "does_not_exist", active: false)
    refute_received {:starter_port, _, _}, "No messages should be sent in passive mode"
  end

  test "error writing to a closed port when using framing", %{
    starter_port1: starter_port1,
    starter_port2: starter_port2
  } do
    framing = {starter_port.Framing.Line, separator: "\n"}

    assert :ok =
             starter_port.open(starter_port2, starter_portTest.port2(),
               active: false,
               framing: framing
             )

    # port1 not yet opened
    assert {:error, :ebadf} = starter_port.write(starter_port1, "A")

    # port1 opened
    assert :ok =
             starter_port.open(starter_port1, starter_portTest.port1(),
               active: false,
               framing: framing
             )

    assert :ok = starter_port.write(starter_port1, "A")
    assert {:ok, "A"} = starter_port.read(starter_port2)

    # port1 closed
    assert :ok = starter_port.close(starter_port1)
    assert {:error, :ebadf} = starter_port.write(starter_port1, "B")

    starter_port.close(starter_port1)
    starter_port.close(starter_port2)
  end

  test "active mode receive", %{starter_port1: starter_port1, starter_port2: starter_port2} do
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1(), active: false)
    assert :ok = starter_port.open(starter_port2, starter_portTest.port2(), active: true)
    port2 = starter_portTest.port2()

    # First write
    assert :ok = starter_port.write(starter_port1, "a")
    assert_receive {:starter_port, ^port2, "a"}

    # Only one message should be sent
    refute_receive {:starter_port, _, _}

    # Try another write
    assert :ok = starter_port.write(starter_port1, "b")
    assert_receive {:starter_port, ^port2, "b"}

    starter_port.close(starter_port1)
    starter_port.close(starter_port2)
  end

  test "active mode receive with id: :pid", %{
    starter_port1: starter_port1,
    starter_port2: starter_port2
  } do
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1(), active: false)

    assert :ok =
             starter_port.open(starter_port2, starter_portTest.port2(), active: true, id: :pid)

    port2 = starter_portTest.port2()

    # First write
    assert :ok = starter_port.write(starter_port1, "a")
    assert_receive {:starter_port, ^starter_port2, "a"}

    # Only one message should be sent
    refute_receive {:starter_port, _, _}

    # Configure to id: :name
    starter_port.configure(starter_port2, id: :name)

    # Try another write
    assert :ok = starter_port.write(starter_port1, "b")
    assert_receive {:starter_port, ^port2, "b"}

    # Configure to id: :pid
    starter_port.configure(starter_port2, id: :pid)

    # Try another write
    assert :ok = starter_port.write(starter_port1, "c")
    assert_receive {:starter_port, ^starter_port2, "c"}

    starter_port.close(starter_port1)
    starter_port.close(starter_port2)
  end

  test "error when calling read in active mode", %{starter_port1: starter_port1} do
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1(), active: true)
    assert {:error, :einval} = starter_port.read(starter_port1)
    starter_port.close(starter_port1)
  end

  test "active mode on then off", %{starter_port1: starter_port1, starter_port2: starter_port2} do
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1(), active: false)
    assert :ok = starter_port.open(starter_port2, starter_portTest.port2(), active: false)
    port2 = starter_portTest.port2()

    assert :ok = starter_port.write(starter_port1, "a")
    assert {:ok, "a"} = starter_port.read(starter_port2, 100)

    assert :ok = starter_port.configure(starter_port2, active: true)
    assert :ok = starter_port.write(starter_port1, "b")
    assert_receive {:starter_port, ^port2, "b"}

    assert :ok = starter_port.configure(starter_port2, active: false)
    assert :ok = starter_port.write(starter_port1, "c")
    assert {:ok, "c"} = starter_port.read(starter_port2, 100)
    refute_receive {:starter_port, _, _}

    assert :ok = starter_port.configure(starter_port2, active: true)
    assert :ok = starter_port.write(starter_port1, "d")
    assert_receive {:starter_port, ^port2, "d"}

    refute_receive {:starter_port, _, _}

    starter_port.close(starter_port1)
    starter_port.close(starter_port2)
  end

  test "active mode gets event when write fails", %{starter_port1: starter_port1} do
    # This only works with tty0tty since it fails write operations if no
    # receiver.

    if String.starts_with?(starter_portTest.port1(), "tnt") do
      assert :ok = starter_port.open(starter_port1, starter_portTest.port1(), active: true)
      port1 = starter_portTest.port1()

      assert {:error, :einval} = starter_port.write(starter_port1, "a")
      assert_receive {:starter_port, ^port1, {:error, :einval}}

      starter_port.close(starter_port1)
    end
  end

  test "read timeout works", %{starter_port1: starter_port1} do
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1(), active: false)

    # 0 duration timeout
    start = System.monotonic_time(:millisecond)
    assert {:ok, <<>>} = starter_port.read(starter_port1, 0)
    elapsed_time = System.monotonic_time(:millisecond) - start
    assert_in_delta elapsed_time, 0, 100

    # 500 ms timeout
    start = System.monotonic_time(:millisecond)
    assert {:ok, <<>>} = starter_port.read(starter_port1, 500)
    elapsed_time = System.monotonic_time(:millisecond) - start
    assert_in_delta elapsed_time, 400, 600

    starter_port.close(starter_port1)
  end

  test "opened starter_port returns the configuration", %{starter_port1: starter_port1} do
    :ok = starter_port.open(starter_port1, starter_portTest.port1(), active: false, speed: 57_600)
    {name, opts} = starter_port.configuration(starter_port1)
    assert name == starter_portTest.port1()
    assert Keyword.get(opts, :active) == false
    assert Keyword.get(opts, :speed) == 57_600
    starter_port.close(starter_port1)
  end

  test "reconfiguring the starter_port updates the configuration", %{starter_port1: starter_port1} do
    :ok = starter_port.open(starter_port1, starter_portTest.port1(), active: false, speed: 9600)
    {name, opts} = starter_port.configuration(starter_port1)
    assert name == starter_portTest.port1()
    assert Keyword.get(opts, :active) == false
    assert Keyword.get(opts, :speed) == 9600

    :ok = starter_port.configure(starter_port1, active: true, speed: 115_200)
    {name, opts} = starter_port.configuration(starter_port1)
    assert name == starter_portTest.port1()
    assert Keyword.get(opts, :active) == true
    assert Keyword.get(opts, :speed) == 115_200

    starter_port.close(starter_port1)
  end

  # Software flow control doesn't work and I'm not sure what the deal is
  if false do
    test "xoff filtered with software flow control", %{
      starter_port1: starter_port1,
      starter_port2: starter_port2
    } do
      if !String.starts_with?(starter_portTest.port1(), "tnt") do
        assert :ok =
                 starter_port.open(starter_port1, starter_portTest.port1(),
                   flow_control: :softare,
                   active: false
                 )

        assert :ok = starter_port.open(starter_port2, starter_portTest.port2(), active: false)

        # Test that starter_port1 filters xoff
        assert :ok = starter_port.write(starter_port2, @xoff)
        assert {:ok, ""} = starter_port.read(starter_port1, 100)

        # Test that starter_port1 filters xon
        assert :ok = starter_port.write(starter_port2, @xon)
        assert {:ok, ""} = starter_port.read(starter_port1, 100)

        # Test that starter_port1 doesn't filter other things
        assert :ok = starter_port.write(starter_port2, "Z")
        assert {:ok, "Z"} = starter_port.read(starter_port1, 100)

        starter_port.close(starter_port1)
        starter_port.close(starter_port2)
      end
    end

    test "software flow control pausing", %{
      starter_port1: starter_port1,
      starter_port2: starter_port2
    } do
      if !String.starts_with?(starter_portTest.port1(), "tnt") do
        assert :ok =
                 starter_port.open(starter_port1, starter_portTest.port1(),
                   flow_control: :softare,
                   active: false
                 )

        assert :ok = starter_port.open(starter_port2, starter_portTest.port2(), active: false)

        # send XOFF to starter_port1 so that it doesn't transmit
        assert :ok = starter_port.write(starter_port2, @xoff)
        assert :ok = starter_port.write(starter_port1, "a")
        assert {:ok, ""} = starter_port.read(starter_port2, 100)

        # send XON to see if we get the "a"
        assert :ok = starter_port.write(starter_port2, @xon)
        assert {:ok, "a"} = starter_port.read(starter_port2, 100)

        starter_port.close(starter_port1)
        starter_port.close(starter_port2)
      end
    end
  end

  test "call controlling_process", %{starter_port1: starter_port1} do
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1(), active: false)
    assert :ok = starter_port.controlling_process(starter_port1, self())
    starter_port.close(starter_port1)
  end

  test "changing config on open port" do
    # Implement me.
  end

  test "opening port with custom speed", %{starter_port1: starter_port1} do
    assert :ok =
             starter_port.open(starter_port1, starter_portTest.port1(),
               active: false,
               speed: 192_000
             )

    starter_port.close(starter_port1)
  end

  test "write and read at standard speeds", %{
    starter_port1: starter_port1,
    starter_port2: starter_port2
  } do
    standard_speeds = [9600, 19200, 38400, 57600, 115_200]

    for speed <- standard_speeds do
      test_send_and_receive(starter_port1, starter_port2, speed: speed)
    end
  end

  test "write and read at custom speeds", %{
    starter_port1: starter_port1,
    starter_port2: starter_port2
  } do
    # 31250 - MIDI
    # 64000, 192_000, 200_000 - Random speeds seen in the field
    #
    # NOTE: This test is highly dependent on the starter_ports under test being able
    #       to support these baud rates, so it may not be a Starter.Port
    #       issue if it fails.
    custom_speeds = [31250, 64000, 192_000, 200_000]

    for speed <- custom_speeds do
      test_send_and_receive(starter_port1, starter_port2, speed: speed)
    end
  end
end
