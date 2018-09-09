defmodule Randex do
  @doc ~S"""
  generates random strings that match the given regex
  """
  @spec stream(Regex.t() | String.t()) :: Enumerable.t()
  def stream(regex) do
    regex =
      cond do
        is_binary(regex) -> Regex.compile!(regex)
        Regex.regex?(regex) -> regex
        true -> raise ArgumentError, "Invalid regex: #{inspect(regex)}"
      end

    source = Regex.source(regex)

    source =
      case Regex.opts(regex) do
        "" -> source
        opts -> "(?#{opts})#{source}"
      end

    Randex.Parser.parse(source)
    |> Randex.Generator.gen()
  end
end
