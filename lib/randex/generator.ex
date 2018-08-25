defmodule Randex.Generator do
  alias Randex.AST

  def gen(asts) do
    Enum.map(asts, &do_gen/1)
    |> StreamData.fixed_list()
    |> StreamData.map(&Enum.join(&1, ""))
  end

  defp do_gen(%AST.Char{value: char}) do
    StreamData.constant(char)
  end

  defp do_gen(%AST.Group{values: asts}), do: gen(asts)

  defp do_gen(%AST.Class{} = ast) do
    gen_class(ast)
  end

  defp do_gen(%AST.Circumflex{}) do
    StreamData.constant("")
  end

  defp do_gen(%AST.Dollar{}) do
    StreamData.constant("")
  end

  defp do_gen(%AST.Option{}) do
    StreamData.constant("")
  end

  defp do_gen(%AST.Comment{}) do
    StreamData.constant("")
  end

  defp do_gen(%AST.Lazy{value: value}) do
    do_gen(value)
  end

  defp do_gen(%AST.Repetition{min: min, max: max, value: ast}) do
    do_gen(ast)
    |> StreamData.list_of(min_length: min, max_length: max)
    |> StreamData.map(&Enum.join(&1, ""))
  end

  defp do_gen(%AST.Or{left: left, right: right}) do
    StreamData.one_of([
      gen(left),
      gen(right)
    ])
  end

  defp do_gen(%AST.Range{first: first, last: last}) do
    StreamData.bind({do_gen(first), do_gen(last)}, fn {<<first::utf8>>, <<last::utf8>>} ->
      StreamData.integer(first..last)
      |> StreamData.map(&<<&1::utf8>>)
    end)
  end

  defp do_gen(%AST.Dot{}) do
    StreamData.string(:ascii, length: 1)
  end

  defp gen_class(%AST.Class{values: asts, negate: negate}) do
    Enum.map(asts, fn
      %AST.Char{value: <<char::utf8>>} ->
        char..char

      %AST.Range{first: %AST.Char{value: <<first::utf8>>}, last: %AST.Char{value: <<last::utf8>>}} ->
        first..last
    end)
    |> Enum.sort_by(fn range -> range.first end)
    |> non_overlapping([])
    |> negate_range(negate)
    |> Enum.map(fn range ->
      StreamData.integer(range)
      |> StreamData.map(&<<&1::utf8>>)
    end)
    |> StreamData.one_of()
  end

  defp non_overlapping([], []), do: []
  defp non_overlapping([x], acc), do: Enum.reverse([x | acc])

  defp non_overlapping([a | [b | rest]], acc) do
    cond do
      b.first > a.last -> non_overlapping([b | rest], [a | acc])
      true -> non_overlapping([a.first..Enum.max(a.last, b.last) | rest], acc)
    end
  end

  defp negate_range(ranges, false), do: ranges
  defp negate_range(ranges, true), do: negate_range(ranges, 32, [])

  defp negate_range([], low, acc), do: Enum.reverse([low..126 | acc])

  defp negate_range([a | rest], low, acc) do
    cond do
      low < a.first -> negate_range(rest, a.last + 1, [low..(a.first - 1) | acc])
      true -> negate_range(rest, a.last + 1, acc)
    end
  end
end
