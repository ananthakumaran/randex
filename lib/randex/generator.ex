defmodule Randex.Generator do
  alias Randex.AST
  alias Randex.Utils

  def gen(asts) do
    Enum.map(asts, &do_gen/1)
    |> StreamData.fixed_list()
    |> resolve
  end

  defp do_gen(%AST.Char{value: char}) do
    StreamData.constant(char)
  end

  defp do_gen(%AST.Group{values: asts} = group) do
    Enum.map(asts, &do_gen/1)
    |> StreamData.fixed_list()
    |> StreamData.map(&{group, &1})
  end

  defp do_gen(%AST.BackReference{} = backref), do: StreamData.constant(backref)

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
    |> Utils.non_overlapping([])
    |> Utils.negate_range(negate)
    |> Enum.map(fn range ->
      StreamData.integer(range)
      |> StreamData.map(&<<&1::utf8>>)
    end)
    |> StreamData.one_of()
  end

  defp resolve(g) do
    StreamData.map(g, fn values ->
      do_resolve(values) |> elem(1)
    end)
  end

  defp do_resolve(values) do
    List.flatten(values)
    |> Enum.reduce({%{}, ""}, fn value, {groups, acc} ->
      case value do
        {%AST.Group{number: n, name: name}, values} ->
          {sub_groups, string} = do_resolve(values)

          groups =
            Map.merge(groups, sub_groups)
            |> Map.put(n, string)
            |> Map.put(name, string)

          {groups, acc <> string}

        %AST.BackReference{name: name} when not is_nil(name) ->
          {groups, acc <> Map.fetch!(groups, name)}

        %AST.BackReference{number: n} ->
          {groups, acc <> Map.fetch!(groups, n)}

        string ->
          {groups, acc <> string}
      end
    end)
  end
end
