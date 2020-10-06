Code.require_file("starter_port_test.exs", __DIR__)

defmodule HWSignalsTest do
  use ExUnit.Case
  alias Starter.Port

  setup do
    StarterPortTest.common_setup()
  end

  test "signals has expected fields", %{starter_port1: starter_port1} do
    :ok = StarterPort.open(starter_port1, StarterPortTest.port1())
    {:ok, signals} = StarterPort.signals(starter_port1)

    assert Map.has_key?(signals, :dsr)
    assert Map.has_key?(signals, :dtr)
    assert Map.has_key?(signals, :rts)
    assert Map.has_key?(signals, :st)
    assert Map.has_key?(signals, :sr)
    assert Map.has_key?(signals, :cts)
    assert Map.has_key?(signals, :cd)
    assert Map.has_key?(signals, :rng)

    StarterPort.close(starter_port1)
  end

  test "rts set works", %{starter_port1: starter_port1} do
    :ok = StarterPort.open(starter_port1, StarterPortTest.port1())

    :ok = StarterPort.set_rts(starter_port1, true)
    {:ok, signals} = StarterPort.signals(starter_port1)
    assert true == signals.rts

    :ok = StarterPort.set_rts(starter_port1, false)
    {:ok, signals} = StarterPort.signals(starter_port1)
    assert false == signals.rts

    StarterPort.close(starter_port1)
  end

  test "dtr set works", %{starter_port1: starter_port1} do
    :ok = StarterPort.open(starter_port1, StarterPortTest.port1())

    :ok = StarterPort.set_dtr(starter_port1, true)
    {:ok, signals} = StarterPort.signals(starter_port1)
    assert true == signals.dtr

    :ok = StarterPort.set_dtr(starter_port1, false)
    {:ok, signals} = StarterPort.signals(starter_port1)
    assert false == signals.dtr

    StarterPort.close(starter_port1)
  end

  test "null modem cable wiring", %{starter_port1: starter_port1, starter_port2: starter_port2} do
    :ok = StarterPort.open(starter_port1, StarterPortTest.port1())
    :ok = StarterPort.open(starter_port2, StarterPortTest.port2())

    # If this test fails, double check that your null modem cable
    # has RTS connected to CTS, and DTR connected to DSR and CD.

    # RTS -> CTS
    :ok = StarterPort.set_rts(starter_port1, true)
    # Set isn't instantaneous on real ports
    :timer.sleep(50)
    {:ok, signals} = StarterPort.signals(starter_port2)
    assert true == signals.cts

    :ok = StarterPort.set_rts(starter_port1, false)
    :timer.sleep(50)
    {:ok, signals} = StarterPort.signals(starter_port2)
    assert false == signals.cts

    # DTR -> DSR and CD
    :ok = StarterPort.set_dtr(starter_port1, true)
    :timer.sleep(50)
    {:ok, signals} = StarterPort.signals(starter_port2)
    assert true == signals.dsr
    assert true == signals.cd

    :ok = StarterPort.set_dtr(starter_port1, false)
    :timer.sleep(50)
    {:ok, signals} = StarterPort.signals(starter_port2)
    assert false == signals.dsr
    assert false == signals.cd

    StarterPort.close(starter_port1)
    StarterPort.close(starter_port2)
  end

  test "set break api exists", %{starter_port1: starter_port1} do
    # Currently, we can't detect a break signal, so just test
    # that we can call the APIs.
    :ok = StarterPort.open(starter_port1, StarterPortTest.port1())

    :ok = StarterPort.set_break(starter_port1, true)
    :ok = StarterPort.set_break(starter_port1, false)

    start_time = System.monotonic_time(:millisecond)
    :ok = StarterPort.send_break(starter_port1, 250)
    duration = System.monotonic_time(:millisecond) - start_time
    assert duration >= 250

    StarterPort.close(starter_port1)
  end
end
