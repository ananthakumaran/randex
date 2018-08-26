defmodule Randex.Parser do
  defmodule Context do
    defmodule Global do
      defstruct [:extended, :multiline, :dotall, :caseless]
    end

    defmodule Local do
      defstruct [:extended, :multiline, :dotall, :caseless]
    end

    defstruct [:global, :local]

    def mode?(context, mode) do
      case Map.get(context.local, mode) do
        false ->
          false

        true ->
          true

        nil ->
          !!Map.get(context.global, mode)
      end
    end
  end

  alias Randex.AST

  @whitespaces [" ", "\n", "\t"]
  @whitespace_codes Enum.map(@whitespaces, fn <<x::utf8>> -> x end)

  def parse(string, context \\ %Context{global: %Context.Global{}, local: %Context.Local{}}) do
    parse_loop(string, &do_parse/1, [], context)
  end

  defp do_parse("\\" <> <<x::utf8>> <> rest), do: escape(<<x::utf8>>, rest)

  defp do_parse("^" <> rest), do: {%AST.Circumflex{}, rest}
  defp do_parse("$" <> rest), do: {%AST.Dollar{}, rest}
  defp do_parse("." <> rest), do: {%AST.Dot{}, rest}

  defp do_parse("#" <> rest) do
    fun = fn old_ast, context ->
      {ast, rest} =
        if Context.mode?(context, :extended) do
          [comment, rest] = String.split(rest, "\n", parts: 2)
          {%AST.Comment{value: comment}, rest}
        else
          {%AST.Char{value: "#"}, rest}
        end

      parse_loop(rest, &do_parse/1, [ast | old_ast], context)
    end

    {:cont, fun}
  end

  defp do_parse(<<x::utf8>> <> rest) when x in @whitespace_codes do
    fun = fn old_ast, context ->
      if Context.mode?(context, :extended) do
        parse_loop(rest, &do_parse/1, old_ast, context)
      else
        parse_loop(rest, &do_parse/1, [%AST.Char{value: <<x::utf8>>} | old_ast], context)
      end
    end

    {:cont, fun}
  end

  defp do_parse("[" <> rest) do
    [class, rest] = String.split(rest, ~r/(?<=\\\\|[^\\])]/, parts: 2)

    {parse_class(class), rest}
  end

  defp do_parse("|" <> rest) do
    fun = fn ast, context ->
      [%AST.Or{left: Enum.reverse(ast), right: parse(rest, context)}]
    end

    {:cont, fun}
  end

  defp do_parse("(" <> rest) do
    case rest do
      "?:" <> rest ->
        parse_group(rest, %{capture: false})

      "?'" <> rest ->
        parse_named_group(rest, "'")

      "?<" <> rest ->
        parse_named_group(rest, ">")

      "?P<" <> rest ->
        parse_named_group(rest, ">")

      "?" <> rest ->
        parse_options(rest)

      _ ->
        parse_group(rest)
    end
  end

  defp do_parse("{" <> _rest = full), do: maybe_repetition(full)
  defp do_parse("*" <> _rest = full), do: maybe_repetition(full)
  defp do_parse("?" <> _rest = full), do: maybe_repetition(full)
  defp do_parse("+" <> _rest = full), do: maybe_repetition(full)

  defp do_parse(<<x::utf8>> <> rest) do
    {%AST.Char{value: <<x::utf8>>}, rest}
  end

  defp parse_class("^" <> string) do
    %AST.Class{values: parse_loop(string, &do_parse_class/1, [], nil), negate: true}
  end

  defp parse_class(string) do
    %AST.Class{values: parse_loop(string, &do_parse_class/1, [], nil)}
  end

  defp do_parse_class("\\" <> <<x::utf8>> <> rest), do: escape(<<x::utf8>>, rest)

  defp do_parse_class("-") do
    {%AST.Char{value: "-"}, ""}
  end

  defp do_parse_class("-" <> rest) do
    fun = fn
      [first | ast], context ->
        {last, rest} = do_parse_class(rest)
        parse_loop(rest, &do_parse_class/1, [%AST.Range{first: first, last: last} | ast], context)

      [], context ->
        parse_loop(rest, &do_parse_class/1, [%AST.Char{value: "-"}], context)
    end

    {:cont, fun}
  end

  defp do_parse_class(<<x::utf8>> <> rest) do
    {%AST.Char{value: <<x::utf8>>}, rest}
  end

  defp parse_loop("", _parser, ast, _context), do: Enum.reverse(ast)

  defp parse_loop(rest, parser, ast, context) do
    case parser.(rest) do
      {:cont, fun} ->
        fun.(ast, context)

      {result, rest} ->
        parse_loop(rest, parser, [result | ast], context)
    end
  end

  defp parse_named_group(rest, terminator) do
    [name, rest] = String.split(rest, terminator, parts: 2)
    parse_group(rest, %{name: name})
  end

  defp parse_group(rest, options \\ %{}) do
    capture = Map.get(options, :capture, true)
    name = Map.get(options, :name)
    {inner, rest} = find_matching(rest, "", 0)

    fun = fn ast, context ->
      parse_loop(
        rest,
        &do_parse/1,
        [
          %AST.Group{
            values: parse_loop(inner, &do_parse/1, [], %{context | local: %Context.Local{}}),
            capture: capture,
            name: name
          }
          | ast
        ],
        context
      )
    end

    {:cont, fun}
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
      [], context ->
        parse_loop(rest, &do_parse/1, [%AST.Char{value: char}], context)

      [current | old_ast], context ->
        cond do
          char == "?" && current.__struct__ == AST.Repetition ->
            parse_loop(rest, &do_parse/1, [%{%AST.Lazy{} | value: current} | old_ast], context)

          Enum.member?(["*", "?", "+"], char) ->
            ast =
              case char do
                "*" -> %AST.Repetition{min: 0, max: :infinity}
                "?" -> %AST.Repetition{min: 0, max: 1}
                "+" -> %AST.Repetition{min: 1, max: :infinity}
              end

            parse_loop(rest, &do_parse/1, [%{ast | value: current} | old_ast], context)

          true ->
            case Integer.parse(rest) do
              {min, rest} ->
                case rest do
                  "}" ->
                    parse_loop(
                      rest,
                      &do_parse/1,
                      [
                        %AST.Repetition{min: min, max: min, value: current} | old_ast
                      ],
                      context
                    )

                  ",}" <> rest ->
                    parse_loop(
                      rest,
                      &do_parse/1,
                      [
                        %AST.Repetition{min: min, max: :infinity, value: current} | old_ast
                      ],
                      context
                    )

                  "," <> rest ->
                    {max, "}" <> rest} = Integer.parse(rest)

                    parse_loop(
                      rest,
                      &do_parse/1,
                      [
                        %AST.Repetition{min: min, max: max, value: current} | old_ast
                      ],
                      context
                    )
                end

              :error ->
                parse_loop(
                  rest,
                  &do_parse/1,
                  [%AST.Char{value: char} | [current | old_ast]],
                  context
                )
            end
        end
    end

    {:cont, fun}
  end

  defp parse_options(rest) do
    [options, rest] = String.split(rest, ")", parts: 2)
    options = parse_loop(options, &do_parse_option/1, [], nil)

    fun = fn ast, context ->
      {local, _} =
        Enum.reduce(options, {context.local, true}, fn option, {local, pred} ->
          case option do
            :negate -> {local, false}
            %AST.Comment{} -> {local, pred}
            _ -> {%{local | option => pred}, pred}
          end
        end)

      parse_loop(rest, &do_parse/1, [%AST.Option{value: options} | ast], %{context | local: local})
    end

    {:cont, fun}
  end

  defp do_parse_option("#" <> comment) do
    {%AST.Comment{value: comment}, ""}
  end

  defp do_parse_option(<<x::utf8>> <> rest) do
    option =
      case <<x::utf8>> do
        "-" ->
          :negate

        "i" ->
          :caseless

        "m" ->
          :multiline

        "s" ->
          :dotall

        "x" ->
          :extended
      end

    {option, rest}
  end

  defp escape(x, rest) do
    case x do
      x when x in ["a", "b", "e", "f", "n", "r", "t", "v"] ->
        {%AST.Char{value: Macro.unescape_string("\\" <> x)}, rest}

      "d" ->
        {%AST.Range{first: %AST.Char{value: "0"}, last: %AST.Char{value: "9"}}, rest}

      <<x::utf8>> when x in 48..57 ->
        {n, rest} = Integer.parse(<<x::utf8>> <> rest)
        {%AST.Char{value: <<n>>}, rest}

      _ ->
        {%AST.Char{value: x}, rest}
    end
  end
end
