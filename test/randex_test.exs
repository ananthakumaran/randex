defmodule RandexTest do
  use ExUnit.Case
  require TestHelper
  import TestHelper
  import Randex

  test "stream" do
    assert_not_empty(stream(~r/[a-z]*/i))
    assert_not_empty(stream(~r/[a-z]*/))
    assert_not_empty(stream("[a-z]*"))
    assert_not_empty(stream(~r/abcdef;-/i))
  end

  @tag capture_log: true
  test "sample" do
    gen("z\\B.+")
  end

  defp assert_not_empty(stream) do
    assert Enum.count(Enum.take(stream, 100)) == 100
  end

  regtest("gen")
end
