defmodule Randex.Parser do
  @moduledoc false

  alias Randex.Context
  alias Randex.AST
  alias Randex.Utils

  @whitespaces [?\s, ?\n, ?\t, ?\v, ?\r, ?\f]
  def parse(string, context \\ %Context{global: %Context.Global{}, local: %Context.Local{}}) do
    {ast, _context} = parse_loop(string, &do_parse/1, [], context)
    ast
  end

  defp do_parse("\\" <> <<x::utf8>> <> rest), do: escape(<<x::utf8>>, rest, false)

  defp do_parse("^" <> rest), do: {%AST.Assertion{value: "^"}, rest}
  defp do_parse("$" <> rest), do: {%AST.Assertion{value: "$"}, rest}
  defp do_parse("." <> rest), do: {%AST.Dot{}, rest}

  defp do_parse("#" <> rest) do
    fn old_ast, context ->
      {ast, rest} =
        if Context.mode?(context, :extended) do
          [comment, rest] =
            case String.split(rest, "\n", parts: 2) do
              [comment, rest] -> [comment, rest]
              [comment] -> [comment, ""]
            end

          {%AST.Comment{value: comment}, rest}
        else
          {%AST.Char{value: "#"}, rest}
        end

      parse_loop(rest, &do_parse/1, [ast | old_ast], context)
    end
  end

  defp do_parse("(*" <> rest) do
    [name, rest] = String.split(rest, ")", parts: 2)
    {%AST.Verb{value: name}, rest}
  end

  defp do_parse(<<x::utf8>> <> rest) when x in @whitespaces do
    fn old_ast, context ->
      if Context.mode?(context, :extended) do
        parse_loop(rest, &do_parse/1, old_ast, context)
      else
        parse_loop(rest, &do_parse/1, [%AST.Char{value: <<x::utf8>>} | old_ast], context)
      end
    end
  end

  defp do_parse("[" <> rest) do
    fn old_ast, context ->
      [class, rest] = String.split(rest, ~r/(?<=\\\\|[^\\])]/, parts: 2)
      ast = parse_class(class, context)
      parse_loop(rest, &do_parse/1, [ast | old_ast], context)
    end
  end

  defp do_parse("|" <> rest) do
    fn ast, context ->
      {right, context} = parse_loop(rest, &do_parse/1, [], context)
      {[%AST.Or{left: Enum.reverse(ast), right: right}], context}
    end
  end

  defp do_parse("(" <> rest) do
    case rest do
      "?:" <> rest ->
        parse_group(rest, %{capture: false})

      "?>" <> rest ->
        parse_group(rest, %{capture: false, atomic: true})

      "?'" <> rest ->
        parse_named_group(rest, "'")

      "?=" <> rest ->
        parse_look(rest, %AST.LookAhead{positive: true})

      "?!" <> rest ->
        parse_look(rest, %AST.LookAhead{positive: false})

      "?<=" <> rest ->
        parse_look(rest, %AST.LookBehind{positive: true})

      "?<!" <> rest ->
        parse_look(rest, %AST.LookBehind{positive: false})

      "?<" <> rest ->
        parse_named_group(rest, ">")

      "?P=" <> rest ->
        [name, rest] = String.split(rest, ")", parts: 2)
        {%AST.BackReference{name: name}, rest}

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
    fn ast, context ->
      parse_loop(
        rest,
        &do_parse/1,
        [%AST.Char{value: <<x::utf8>>, caseless: Context.mode?(context, :caseless)} | ast],
        context
      )
    end
  end

  defp parse_class(string, context) do
    {negate, string} =
      case string do
        "^" <> string -> {true, string}
        _ -> {false, string}
      end

    {ast, _context} = parse_loop(string, &do_parse_class/1, [], context)
    %AST.Class{values: ast, negate: negate, caseless: Context.mode?(context, :caseless)}
  end

  defp do_parse_class("\\" <> <<x::utf8>> <> rest), do: escape(<<x::utf8>>, rest, true)

  defp do_parse_class("-") do
    {%AST.Char{value: "-"}, ""}
  end

  defp do_parse_class("-" <> rest) do
    fn
      [first | old_ast], context ->
        {[last | rest], context} = parse_loop(rest, &do_parse_class/1, [], context)
        {Enum.reverse(old_ast) ++ [%AST.Range{first: first, last: last}] ++ rest, context}

      [], context ->
        parse_loop(rest, &do_parse_class/1, [%AST.Char{value: "-"}], context)
    end
  end

  defp do_parse_class(<<x::utf8>> <> rest) do
    {%AST.Char{value: <<x::utf8>>}, rest}
  end

  defp parse_loop("", _parser, ast, context), do: {Enum.reverse(ast), context}

  defp parse_loop(rest, parser, ast, context) do
    case parser.(rest) do
      fun when is_function(fun) ->
        fun.(ast, context)

      {result, rest} ->
        parse_loop(rest, parser, [result | ast], context)
    end
  end

  defp parse_look(rest, ast) do
    {regex, rest} = find_matching(rest, "", 0)

    regex =
      case ast do
        %AST.LookBehind{} -> "(?:" <> regex <> ")$"
        _ -> regex
      end

    {%{ast | value: Regex.compile!(regex)}, rest}
  end

  defp parse_named_group(rest, terminator) do
    [name, rest] = String.split(rest, terminator, parts: 2)
    parse_group(rest, %{name: name})
  end

  defp parse_group(rest, options \\ %{}) do
    capture = Map.get(options, :capture, true)
    name = Map.get(options, :name)
    {inner, rest} = find_matching(rest, "", 0)

    fn ast, context ->
      {context, number} =
        if capture do
          context = Context.update_global(context, :group, &(&1 + 1))
          {context, context.global.group}
        else
          {context, nil}
        end

      current_local = context.local
      {values, context} = parse_loop(inner, &do_parse/1, [], %{context | local: %Context.Local{}})
      context = %{context | local: current_local}

      parse_loop(
        rest,
        &do_parse/1,
        [
          %AST.Group{
            values: values,
            capture: capture,
            name: name,
            number: number
          }
          | ast
        ],
        context
      )
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

    fn
      [], context ->
        parse_loop(rest, &do_parse/1, [%AST.Char{value: char}], context)

      [current | old_ast], context ->
        old_rest = rest

        cond do
          char == "?" && current.__struct__ == AST.Repetition ->
            parse_loop(rest, &do_parse/1, [%AST.Lazy{value: current} | old_ast], context)

          char == "+" && current.__struct__ == AST.Repetition ->
            parse_loop(rest, &do_parse/1, [%AST.Possesive{value: current} | old_ast], context)

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
                  "}" <> rest ->
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
                    case Integer.parse(rest) do
                      {max, "}" <> rest} ->
                        parse_loop(
                          rest,
                          &do_parse/1,
                          [
                            %AST.Repetition{min: min, max: max, value: current} | old_ast
                          ],
                          context
                        )

                      _ ->
                        parse_loop(
                          old_rest,
                          &do_parse/1,
                          [
                            %AST.Char{value: char, caseless: Context.mode?(context, :caseless)}
                            | [current | old_ast]
                          ],
                          context
                        )
                    end

                  _ ->
                    parse_loop(
                      old_rest,
                      &do_parse/1,
                      [
                        %AST.Char{value: char, caseless: Context.mode?(context, :caseless)}
                        | [current | old_ast]
                      ],
                      context
                    )
                end

              :error ->
                parse_loop(
                  rest,
                  &do_parse/1,
                  [
                    %AST.Char{value: char, caseless: Context.mode?(context, :caseless)}
                    | [current | old_ast]
                  ],
                  context
                )
            end
        end
    end
  end

  defp parse_options(rest) do
    [options, rest] = String.split(rest, ")", parts: 2)
    {options, nil} = parse_loop(options, &do_parse_option/1, [], nil)

    fn ast, context ->
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

  defp charset(code, inside_class) do
    set =
      case String.downcase(code) do
        "d" ->
          [?0..?9]

        "h" ->
          [
            "\u0009",
            "\u0020",
            "\u00A0",
            "\u1680",
            "\u180E",
            "\u2000",
            "\u2001",
            "\u2002",
            "\u2003",
            "\u2004",
            "\u2005",
            "\u2006",
            "\u2007",
            "\u2008",
            "\u2009",
            "\u200A",
            "\u202F",
            "\u205F",
            "\u3000"
          ]

        "s" ->
          @whitespaces

        "v" ->
          ["\u000A", "\u000B", "\u000C", "\u000D", "\u0085", "\u2028", "\u2029"]

        "w" ->
          [?_, ?0..?9, ?A..?Z, ?a..?z]
      end

    asts =
      Enum.map(set, fn
        x when is_binary(x) ->
          [x] = String.to_charlist(x)
          x..x

        x when is_integer(x) ->
          x..x

        x ->
          x
      end)
      |> Enum.sort_by(fn range -> range.first end)
      |> Utils.non_overlapping([])
      |> Utils.negate_range(code != String.downcase(code))
      |> Enum.map(fn range ->
        %AST.Range{
          first: %AST.Char{value: <<range.first::utf8>>},
          last: %AST.Char{value: <<range.last::utf8>>}
        }
      end)

    if inside_class do
      asts
    else
      [%AST.Class{values: asts, negate: false}]
    end
  end

  defp escape(x, rest, class) do
    fn old_ast, context ->
      {ast, rest} =
        case x do
          x when x in ["a", "b", "e", "f", "n", "r", "t", "v"] ->
            {[%AST.Char{value: Macro.unescape_string("\\" <> x)}], rest}

          x when x in ["A", "Z"] ->
            {[%AST.Assertion{value: x}], rest}

          "c" ->
            <<code::binary-1, rest::binary>> = rest
            <<code::utf8>> = String.upcase(code)
            code = code - 64

            code =
              if code < 0 do
                code + 128
              else
                code
              end

            {[%AST.Char{value: <<code::utf8>>}], rest}

          x when x in ["d", "D", "h", "s", "S", "v", "w", "W"] ->
            {charset(x, class), rest}

          "x" ->
            case rest do
              <<x::integer, y::integer, _::binary>>
              when (x in ?0..?9 or x in ?A..?F or x in ?a..?f) and
                     (y in ?0..?9 or y in ?A..?F or y in ?a..?f) ->
                <<hex::binary-2, rest::binary>> = rest
                {[%AST.Char{value: Macro.unescape_string("\\x" <> hex)}], rest}

              "{" <> rest ->
                [number, rest] = String.split(rest, "}", parts: 2)
                {n, ""} = Integer.parse(number, 16)
                {[%AST.Char{value: <<n::utf8>>}], rest}

              _ ->
                {[%AST.Char{value: <<0>>}], rest}
            end

          "k" ->
            {terminator, rest} =
              case rest do
                "<" <> rest -> {">", rest}
                "{" <> rest -> {"}", rest}
                "'" <> rest -> {"'", rest}
              end

            [name, rest] = String.split(rest, terminator, parts: 2)
            {[%AST.BackReference{name: name}], rest}

          "g" ->
            case rest do
              "{" <> rest ->
                [name_or_number, rest] = String.split(rest, "}", parts: 2)

                ast =
                  case Integer.parse(name_or_number) do
                    {n, ""} ->
                      if n >= 0 do
                        %AST.BackReference{number: n}
                      else
                        %AST.BackReference{number: context.global.group + n + 1}
                      end

                    _ ->
                      %AST.BackReference{name: name_or_number}
                  end

                {[ast], rest}

              _ ->
                {n, rest} = Integer.parse(rest)
                {[%AST.BackReference{number: n}], rest}
            end

          "o" ->
            "{" <> rest = rest
            [number, rest] = String.split(rest, "}", parts: 2)
            {n, ""} = Integer.parse(number, 8)
            {[%AST.Char{value: Utils.integer_to_string(n)}], rest}

          <<x::utf8>> when x in 48..57 ->
            base =
              case rest do
                <<x::utf8, y::utf8>> <> _ when x in 48..57 and y in 48..57 ->
                  8

                _ ->
                  10
              end

            {n, rest} = Integer.parse(<<x::utf8>> <> rest, base)

            cond do
              !class && base == 10 && n > 0 && context.global.group >= n ->
                {[%AST.BackReference{number: n}], rest}

              true ->
                {[%AST.Char{value: Utils.integer_to_string(n)}], rest}
            end

          _ ->
            {[%AST.Char{value: x}], rest}
        end

      if class do
        parse_loop(rest, &do_parse_class/1, ast ++ old_ast, context)
      else
        parse_loop(rest, &do_parse/1, ast ++ old_ast, context)
      end
    end
  end
end
