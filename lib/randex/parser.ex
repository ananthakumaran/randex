defmodule Randex.Parser do
  alias Randex.AST

  def parse(string) do
    parse_loop(string, &do_parse/1, [])
  end

  defp do_parse("\\" <> <<x::utf8>> <> rest) do
    {%AST.Char{value: <<x::utf8>>}, rest}
  end

  defp do_parse("^" <> rest), do: {%AST.Circumflex{}, rest}
  defp do_parse("$" <> rest), do: {%AST.Dollar{}, rest}
  defp do_parse("." <> rest), do: {%AST.Dot{}, rest}

  defp do_parse("[" <> rest) do
    [class, rest] = String.split(rest, ~r/(?<=\\\\|[^\\])]/, parts: 2)

    {parse_class(class), rest}
  end

  defp do_parse("|" <> rest) do
    fun = fn state ->
      [%AST.Or{left: state, right: parse(rest)}]
    end

    {:cont, fun}
  end

  defp do_parse(<<x::utf8>> <> rest) do
    {%AST.Char{value: <<x::utf8>>}, rest}
  end

  defp parse_class("^" <> string) do
    %AST.Class{values: parse_loop(string, &do_parse_class/1, []), negate: true}
  end

  defp parse_class(string) do
    %AST.Class{values: parse_loop(string, &do_parse_class/1, [])}
  end

  defp do_parse_class("\\" <> <<x::utf8>> <> rest) do
    {%AST.Char{value: <<x::utf8>>}, rest}
  end

  defp do_parse_class("-") do
    {%AST.Char{value: "-"}, ""}
  end

  defp do_parse_class("-" <> rest) do
    fun = fn
      [first | state] ->
        {last, rest} = do_parse_class(rest)
        parse_loop(rest, &do_parse_class/1, [%AST.Range{first: first, last: last} | state])

      [] ->
        parse_loop(rest, &do_parse_class/1, [%AST.Char{value: "-"}])
    end

    {:cont, fun}
  end

  defp do_parse_class(<<x::utf8>> <> rest) do
    {%AST.Char{value: <<x::utf8>>}, rest}
  end

  defp parse_loop("", _parser, state), do: Enum.reverse(state)

  defp parse_loop(rest, parser, state) do
    case parser.(rest) do
      {:cont, fun} ->
        fun.(state)

      {result, rest} ->
        parse_loop(rest, parser, [result | state])
    end
  end
end
