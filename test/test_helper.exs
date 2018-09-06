defmodule TestHelper do
  require Logger
  import ExUnit.Assertions

  def cases do
    File.read!(Path.join(__DIR__, "fixture"))
    |> String.split("\n\n")
    |> Enum.filter(&(!String.starts_with?(&1, "#")))
  end

  def gen(c) do
    Logger.info("Regex: " <> inspect(c))
    regex = Regex.compile!(c)

    ast = Randex.Parser.parse(c)
    Logger.info("AST: " <> inspect(ast, pretty: true))

    Randex.Generator.gen(ast)
    |> Enum.take(100)
    |> Enum.each(fn sample ->
      assert sample =~ regex
    end)
  end

  defmacro assert_amb(amb, expected) do
    quote do
      actual = Enum.to_list(unquote(amb))
      assert actual == unquote(expected)
    end
  end

  defmacro regtest(name) do
    prefix = name <> " "

    Enum.with_index(cases())
    |> Enum.chunk_every(50)
    |> Enum.with_index()
    |> Enum.map(fn {cases, i} ->
      quote do
        defmodule unquote(String.to_atom("RandexTest#{i}")) do
          use ExUnit.Case, async: true

          unquote do
            Enum.map(cases, fn {c, j} ->
              quote do
                test unquote(prefix) <> unquote(to_string(j)) do
                  unquote(__MODULE__).unquote(Macro.var(String.to_atom(name), __MODULE__))(
                    unquote(c)
                  )
                end
              end
            end)
          end
        end
      end
    end)
  end
end

ExUnit.start(capture_log: true)
