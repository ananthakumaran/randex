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

  defp do_parse("(" <> rest) do
    {inner, rest} = find_matching(rest, "", 0)

    fun = fn state ->
      parse_loop(rest, &do_parse/1, [
        %AST.Group{values: parse_loop(inner, &do_parse/1, [])} | state
      ])
    end

    {:cont, fun}
  end

  defp do_parse("{" <> _rest = full), do: maybe_repetition(full)
  defp do_parse("*" <> _rest = full), do: maybe_repetition(full)
  defp do_parse("?" <> _rest = full), do: maybe_repetition(full)
  defp do_parse("+" <> _rest = full), do: maybe_repetition(full)

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

  defp find_matching("\\" <> <<x::utf8>> <> rest, acc, count),
    do: find_matching(rest, acc <> "\\" <> <<x::utf8>>, count)

  defp find_matching(")" <> rest, acc, 0), do: {acc, rest}
  defp find_matching(")" <> rest, acc, count), do: find_matching(rest, acc <> ")", count - 1)
  defp find_matching("(" <> rest, acc, count), do: find_matching(rest, acc <> "(", count + 1)

  defp find_matching(<<x::utf8>> <> rest, acc, count),
    do: find_matching(rest, acc <> <<x::utf8>>, count)

  defp maybe_repetition(<<x::utf8>> <> rest) do
    char = <<x::utf8>>

    fun = fn
      [] ->
        parse_loop(rest, &do_parse/1, [%AST.Char{value: char}])

      [current | state] ->
        if Enum.member?(["*", "?", "+"], char) do
          ast =
            case char do
              "*" -> %AST.Repetition{min: 0, max: :infinite}
              "?" -> %AST.Repetition{min: 0, max: 1}
              "+" -> %AST.Repetition{min: 1, max: :infinite}
            end

          parse_loop(rest, &do_parse/1, [%{ast | value: current} | state])
        else
          case Integer.parse(rest) do
            {min, rest} ->
              case rest do
                "}" ->
                  parse_loop(rest, &do_parse/1, [
                    %AST.Repetition{min: min, max: min, value: current} | state
                  ])

                ",}" <> rest ->
                  parse_loop(rest, &do_parse/1, [
                    %AST.Repetition{min: min, max: :infinite, value: current} | state
                  ])

                "," <> rest ->
                  {max, rest} = Integer.parse(rest)

                  parse_loop(rest, &do_parse/1, [
                    %AST.Repetition{min: min, max: max, value: current} | state
                  ])
              end

            :error ->
              parse_loop(rest, &do_parse/1, [%AST.Char{value: char}])
          end
        end
    end

    {:cont, fun}
  end
end
