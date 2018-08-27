defmodule RandexTest do
  require TestHelper
  import TestHelper
  require Logger

  use ExUnit.Case

  def gen(c) do
    Logger.info(c)
    regex = Regex.compile!(c)

    ast = Randex.Parser.parse(c)
    Logger.info(inspect(ast))

    Randex.Generator.gen(ast)
    |> Enum.take(10)
    |> Enum.each(fn sample ->
      assert sample =~ regex
    end)
  end

  regtest("gen")
end
