defmodule Randex do
  @moduledoc """
  Randex is a regex based random string generator.

  ## Example

  ```elixir
  iex(1)> Randex.stream(~r/(1[0-2]|0[1-9])(:[0-5]\d){2} (A|P)M/) |> Enum.take(10)
  ["10:53:29 AM", "02:54:11 AM", "09:23:04 AM", "10:41:57 AM", "11:42:13 AM",
  "10:27:37 AM", "06:15:18 AM", "03:09:58 AM", "09:15:06 AM", "04:25:28 AM"]
  ```


  ## Unsupported Features

  * [Atomic Grouping and Possessive
  Quantifiers](http://erlang.org/doc/man/re.html#sect15)

  * [Recursive Patterns](http://erlang.org/doc/man/re.html#sect20)

  * [Conditional Subpatterns](http://erlang.org/doc/man/re.html#sect18)

  * [Subpatterns as
  Subroutines](http://erlang.org/doc/man/re.html#sect21)

  * [Backtracking Control](http://erlang.org/doc/man/re.html#sect23)
  """

  alias Randex.Generator.Config

  @doc ~S"""
  Generates random strings that match the given regex

  ### Options

  * max_repetition: (integer) There is no upper limit for some of the
    quantifiers like `+`, `*` etc. This config specifies how the upper
    limit should be calculated in these cases. The range is calculated
    as `min..(min + max_repetition)`. Defaults to `100`.


  * mod: (module) The library comes with 3 different types of
    generators. Defaults to `Randex.Generator.Random`

  `Randex.Generator.Random` - Generates the string in a random manner.

  `Randex.Generator.DFS` - This does a depth first traversal. This could be used to generate all possible strings in a systematic manner.

  `Randex.Generator.StreamData` - This is built on top of the `StreamData` generators. It could be used as a generator in property testing. Note: this generator might not work well with complicated lookahead or lookbehind expressions.
  """
  @spec stream(Regex.t() | String.t()) :: Enumerable.t()
  def stream(regex, options \\ []) do
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

    config = Map.merge(%Config{}, Enum.into(options, %{}))

    Randex.Parser.parse(source)
    |> Randex.Generator.gen(config)
  end
end
