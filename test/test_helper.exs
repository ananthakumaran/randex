defmodule TestHelper do
  require Logger
  import ExUnit.Assertions

  def cases(path) do
    File.read!(Path.join([__DIR__, "fixtures", path]))
    |> String.trim()
    |> String.split("\n\n")
    |> Enum.filter(&(!String.starts_with?(&1, "#")))
  end

  def gen(c, opts, config) do
    Logger.info("Regex: " <> inspect(c))
    regex = Regex.compile!(c)

    ast = Randex.Parser.parse(c)
    Logger.info("AST: " <> inspect(ast, pretty: true))

    candidates =
      Randex.Generator.gen(ast, config)
      |> Enum.take(100)

    if Keyword.get(opts, :validate_length) do
      assert length(candidates) == 100
    end

    Enum.each(candidates, fn sample ->
      assert sample =~ regex
    end)
  end

  defmacro assert_amb(amb, expected) do
    quote do
      actual = Enum.to_list(unquote(amb))
      assert actual == unquote(expected)
    end
  end

  defmacro regtest(name, opts, config) do
    path = Keyword.fetch!(opts, :path)

    Enum.with_index(cases(path))
    |> Enum.chunk_every(50)
    |> Enum.with_index()
    |> Enum.map(fn {cases, i} ->
      quote do
        defmodule unquote(String.to_atom("RandexTest #{name} #{path} #{i}")) do
          use ExUnit.Case, async: true

          unquote do
            Enum.map(cases, fn {c, j} ->
              quote do
                test unquote("#{name} #{j} #{String.slice(c, 0..50)}") do
                  unquote(__MODULE__).unquote(Macro.var(:gen, __MODULE__))(
                    unquote(c),
                    unquote(opts),
                    unquote(config)
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

Application.ensure_all_started(:stream_data)
ExUnit.start(capture_log: true)
