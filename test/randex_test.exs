defmodule RandexTest do
  use ExUnit.Case
  use ExUnitProperties
  require TestHelper
  import TestHelper
  import Randex
  alias Randex.Generator

  test "stream" do
    assert_not_empty(stream(~r/[a-z]*/i))
    assert_not_empty(stream(~r/[a-z]*/))
    assert_not_empty(stream("[a-z]*"))
    assert_not_empty(stream(~r/abcdef;-/i))
  end

  defp assert_not_empty(stream) do
    assert Enum.count(Enum.take(stream, 100)) == 100
  end

  @tag capture_log: true
  test "sample" do
    gen("(b$|e)", [], %Generator.Config{
      mod: Generator.StreamData,
      max_repetition: 10
    })
  end

  property "starts with cat" do
    check all(cat <- stream(~r/cat \w+/, mod: Randex.Generator.StreamData)) do
      assert String.starts_with?(cat, "cat")
    end
  end

  regtest("random", [path: "all", validate_length: true], %Generator.Config{max_repetition: 10})

  regtest("random", [path: "random", validate_length: true], %Generator.Config{max_repetition: 10})

  regtest("dfs", [path: "all"], %Generator.Config{mod: Generator.DFS, max_repetition: 10})

  regtest("stream_data", [path: "all", validate_length: true], %Generator.Config{
    mod: Generator.StreamData,
    max_repetition: 10
  })
end
