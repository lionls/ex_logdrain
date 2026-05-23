defmodule ExLogdrain.LogBufferTest do
  use ExUnit.Case, async: false

  setup do
    flush_interval = Application.get_env(:ex_logdrain, :flush_interval)
    Application.put_env(:ex_logdrain, :flush_interval, 10_000_000)
    Supervisor.start_link([{ExLogdrain.LogBuffer, []}], strategy: :one_for_one)
    on_exit(fn ->
      Application.put_env(:ex_logdrain, :flush_interval, flush_interval)
    end)
    :ok
  end

  test "enqueue stores log in buffer" do
    log = %{id: "1", message: "test"}
    ExLogdrain.LogBuffer.enqueue(log)

    state = :sys.get_state(ExLogdrain.LogBuffer)
    assert [%{id: "1", message: "test"}] = state
  end

  test "multiple enqueues store in order" do
    ExLogdrain.LogBuffer.enqueue(%{id: "1"})
    ExLogdrain.LogBuffer.enqueue(%{id: "2"})
    ExLogdrain.LogBuffer.enqueue(%{id: "3"})

    state = :sys.get_state(ExLogdrain.LogBuffer)
    assert [%{id: "3"}, %{id: "2"}, %{id: "1"}] = state
  end

  test "flush reverses and sends to Repo" do
    ExLogdrain.LogBuffer.enqueue(%{id: "a"})
    ExLogdrain.LogBuffer.enqueue(%{id: "b"})

    send(ExLogdrain.LogBuffer, :flush)
    Process.sleep(50)

    assert :sys.get_state(ExLogdrain.LogBuffer) == []
  end
end
