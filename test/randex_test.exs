defmodule RandexTest do
  require TestHelper
  import TestHelper
  require Logger

  use ExUnit.Case

  def gen(c) do
    Logger.info("Regex: " <> inspect(c))
    regex = Regex.compile!(c)

    ast = Randex.Parser.parse(c)
    Logger.info("AST: " <> inspect(ast, pretty: true))

    Randex.Generator.gen(ast)
    |> Enum.take(10)
    |> Enum.each(fn sample ->
      assert sample =~ regex
    end)
  end

  regtest("gen")
end
