defmodule TestHelper do
  def cases do
    File.read!(Path.join(__DIR__, "fixture"))
    |> String.split("\n\n")
    |> Enum.filter(&(!String.starts_with?(&1, "#")))
  end

  defmacro regtest(name) do
    prefix = name <> " "

    Enum.map(cases(), fn c ->
      quote do
        test unquote(prefix) <> unquote(c) do
          __MODULE__.unquote(Macro.var(String.to_atom(name), __MODULE__))(unquote(c))
        end
      end
    end)
  end
end

ExUnit.start(capture_log: true)
