defmodule ExLogdrain.JsonTest do
  use ExUnit.Case, async: true

  test "decode!/2 parses valid JSON" do
    assert ExLogdrain.Json.decode!("[1,2,3]") == [1, 2, 3]
  end

  test "decode!/2 parses JSON object" do
    assert ExLogdrain.Json.decode!("{\"key\":\"value\"}") == %{"key" => "value"}
  end

  test "decode!/2 parses nested Vercel log payload" do
    json = ~s([{"id":"a1","message":"hello","level":"info","timestamp":1700000000000}])
    assert [%{"id" => "a1", "message" => "hello", "level" => "info", "timestamp" => 1_700_000_000_000}] =
             ExLogdrain.Json.decode!(json)
  end

  test "decode!/2 returns nil for empty string" do
    assert ExLogdrain.Json.decode!("") == nil
  end

  test "decode!/2 returns nil for nil" do
    assert ExLogdrain.Json.decode!(nil) == nil
  end

  test "decode!/2 raises on invalid JSON" do
    assert_raise ErlangError, fn ->
      ExLogdrain.Json.decode!("{invalid")
    end
  end

  test "encode/1 encodes to JSON string" do
    assert ExLogdrain.Json.encode([1, 2, 3]) == "[1,2,3]"
  end

  test "encode/1 encodes map" do
    assert ExLogdrain.Json.encode(%{a: 1}) == "{\"a\":1}"
  end
end
