Code.require_file("starter_port_test.exs", __DIR__)

defmodule FramingTest do
  use ExUnit.Case
  alias Starter.Port

  @moduledoc """
  These tests are high level framing tests. See `framing_*_test.exs`
  for unit tests.
  """

  setup do
    starter_portTest.common_setup()
  end

  test "receive a line in passive mode", %{
    starter_port1: starter_port1,
    starter_port2: starter_port2
  } do
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1())

    assert :ok =
             starter_port.open(
               starter_port2,
               starter_portTest.port2(),
               active: false,
               framing: {
                 starter_port.Framing.Line,
                 max_length: 4
               }
             )

    # Send something that's not a line and check that we don't receive it
    assert :ok = starter_port.write(starter_port1, "A")
    assert {:ok, <<>>} = starter_port.read(starter_port2, 500)

    # Terminate the line and check that receive gets it
    assert :ok = starter_port.write(starter_port1, "\n")
    assert {:ok, "A"} = starter_port.read(starter_port2)

    # Send two lines
    assert :ok = starter_port.write(starter_port1, "B\nC\n")
    assert {:ok, "B"} = starter_port.read(starter_port2, 500)
    assert {:ok, "C"} = starter_port.read(starter_port2, 500)

    # Handle a line that's too long
    assert :ok = starter_port.write(starter_port1, "DEFGHIJK\n")
    assert {:ok, {:partial, "DEFG"}} = starter_port.read(starter_port2, 500)
    assert {:ok, "HIJK"} = starter_port.read(starter_port2, 500)

    starter_port.close(starter_port1)
    starter_port.close(starter_port2)
  end

  test "framing gets applied when transmitting", %{
    starter_port1: starter_port1,
    starter_port2: starter_port2
  } do
    assert :ok =
             starter_port.open(starter_port1, starter_portTest.port1(),
               framing: starter_port.Framing.Line
             )

    assert :ok = starter_port.open(starter_port2, starter_portTest.port2(), active: false)

    # Transmit something and check that a linefeed gets applied
    assert :ok = starter_port.write(starter_port1, "A")
    :timer.sleep(100)
    assert {:ok, "A\n"} = starter_port.read(starter_port2)

    starter_port.close(starter_port1)
    starter_port.close(starter_port2)
  end

  test "multiple read polls do not elapse the specified read timeout", %{
    starter_port1: starter_port1,
    starter_port2: starter_port2
  } do
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1())

    assert :ok =
             starter_port.open(
               starter_port2,
               starter_portTest.port2(),
               active: false,
               framing: {
                 starter_port.Framing.Line,
                 max_length: 4
               }
             )

    spawn(fn ->
      # Sleep to allow the starter_port.read some time to begin reading
      :timer.sleep(100)
      # Send something that's not a line
      assert :ok = starter_port.write(starter_port1, "A")
    end)

    assert {:ok, <<>>} = starter_port.read(starter_port2, 500)
  end

  test "framing timeouts in passive mode", %{
    starter_port1: starter_port1,
    starter_port2: starter_port2
  } do
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1())

    assert :ok =
             starter_port.open(
               starter_port2,
               starter_portTest.port2(),
               active: false,
               framing: {starter_port.Framing.Line, max_length: 10},
               rx_framing_timeout: 100
             )

    # Send something that's not a line and check that it times out
    assert :ok = starter_port.write(starter_port1, "A")
    # Initial read will timeout and the partial read will be queued in the starter_port state
    assert {:ok, <<>>} = starter_port.read(starter_port2, 200)
    # Call read again to fetch the queued data
    assert {:ok, {:partial, "A"}} = starter_port.read(starter_port2, 200)

    starter_port.close(starter_port1)
    starter_port.close(starter_port2)
  end

  test "receive a line in active mode", %{
    starter_port1: starter_port1,
    starter_port2: starter_port2
  } do
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1())

    assert :ok =
             starter_port.open(
               starter_port2,
               starter_portTest.port2(),
               active: true,
               framing: {
                 starter_port.Framing.Line,
                 max_length: 4
               }
             )

    port2 = starter_portTest.port2()

    # Send something that's not a line and check that we don't receive it
    assert :ok = starter_port.write(starter_port1, "A")
    refute_receive {:starter_port, _, _}

    # Terminate the line and check that receive gets it
    assert :ok = starter_port.write(starter_port1, "\n")
    # QUESTION: Trim the framing or not?
    #    Argument to trim: 1. the framing is at a lower level
    #                      2. framing could contain stuffing, compression, etc.
    #                         that would need to be undone anyway. not removing
    #                         the framing would effectively mean that the
    #                         framing gets removed twice.
    #                      3. Erlang ports remove their framing
    #    Argument not to trim: 1. most framing is easy to trim anyway
    #                          2. easier to debug?
    assert_receive {:starter_port, ^port2, "A"}

    # Send two lines
    assert :ok = starter_port.write(starter_port1, "B\nC\n")
    assert_receive {:starter_port, ^port2, "B"}
    assert_receive {:starter_port, ^port2, "C"}

    # Handle a line that's too long
    assert :ok = starter_port.write(starter_port1, "DEFGHIJK\n")
    assert_receive {:starter_port, ^port2, {:partial, "DEFG"}}
    assert_receive {:starter_port, ^port2, "HIJK"}

    starter_port.close(starter_port1)
    starter_port.close(starter_port2)
  end

  test "framing timeouts in active mode", %{
    starter_port1: starter_port1,
    starter_port2: starter_port2
  } do
    assert :ok = starter_port.open(starter_port1, starter_portTest.port1())

    assert :ok =
             starter_port.open(
               starter_port2,
               starter_portTest.port2(),
               active: true,
               framing: {starter_port.Framing.Line, max_length: 10},
               rx_framing_timeout: 500
             )

    port2 = starter_portTest.port2()

    # Send something that's not a line and check that it times out
    assert :ok = starter_port.write(starter_port1, "A")
    assert_receive {:starter_port, ^port2, {:partial, "A"}}, 1000

    starter_port.close(starter_port1)
    starter_port.close(starter_port2)
  end

  test "active mode gets error when write fails", %{starter_port1: starter_port1} do
    # This only works with tty0tty since it fails write operations if no
    # receiver.

    if String.starts_with?(starter_portTest.port1(), "tnt") do
      assert :ok =
               starter_port.open(starter_port1, starter_portTest.port1(),
                 active: true,
                 framing: starter_port.Framing.Line
               )

      port1 = starter_portTest.port1()

      assert {:error, :einval} = starter_port.write(starter_port1, "a")
      assert_receive {:starter_port, ^port1, {:error, :einval}}

      starter_port.close(starter_port1)
    end
  end
end
