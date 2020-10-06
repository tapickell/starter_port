defmodule StarterPortlessTest do
  use ExUnit.Case
  alias Starter.Port

  # These tests all run with or without a serial port

  test "enumerate returns a map" do
    ports = StarterPort.enumerate()
    assert is_map(ports)
  end

  test "start_link without arguments works" do
    {:ok, pid} = StarterPort.start_link()
    assert is_pid(pid)
  end

  test "open bogus serial port" do
    {:ok, pid} = StarterPort.start_link()
    assert {:error, :enoent} = StarterPort.open(pid, "bogustty")
  end

  test "using a port without opening it" do
    {:ok, pid} = StarterPort.start_link()
    assert {:error, :ebadf} = StarterPort.write(pid, "hello")
    assert {:error, :ebadf} = StarterPort.read(pid)
    assert {:error, :ebadf} = StarterPort.flush(pid)
    assert {:error, :ebadf} = StarterPort.drain(pid)
  end

  test "unopened starter_port returns a configuration" do
    {:ok, pid} = StarterPort.start_link()
    {name, opts} = StarterPort.configuration(pid)

    assert name == :closed
    assert is_list(opts)

    # Check the defaults
    assert Keyword.get(opts, :active) == true
    assert Keyword.get(opts, :speed) == 9600
    assert Keyword.get(opts, :data_bits) == 8
    assert Keyword.get(opts, :stop_bits) == 1
    assert Keyword.get(opts, :parity) == :none
    assert Keyword.get(opts, :flow_control) == :none
    assert Keyword.get(opts, :framing) == Starter.Port.Framing.None
    assert Keyword.get(opts, :rx_framing_timeout) == 0
    assert Keyword.get(opts, :id) == :name
  end

  test "find starter_ports" do
    {:ok, pid} = StarterPort.start_link()
    assert StarterPort.find_pids() == [{pid, :closed}]
  end
end
