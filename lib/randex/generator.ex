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

  defp do_gen(%AST.Class{values: []}) do
    StreamData.constant("")
  end

  defp do_gen(%AST.Class{values: asts}) do
    Enum.map(asts, &do_gen/1)
    |> StreamData.one_of()
  end

  defp do_gen(%AST.Circumflex{}) do
    StreamData.constant("")
  end

  defp do_gen(%AST.Dollar{}) do
    StreamData.constant("")
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
end
