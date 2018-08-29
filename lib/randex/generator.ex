defmodule Randex.Generator do
  alias Randex.AST
  alias Randex.Utils

  def gen(asts) do
    gen_loop(asts, StreamData.constant({"", %{}}))
    |> StreamData.map(fn {candidate, _context} -> candidate end)
  end

  defp do_gen(%AST.Char{value: char}) do
    StreamData.constant(char)
  end

  defp do_gen(%AST.Group{values: asts, name: name, number: n}) do
    fun = fn generator ->
      bind_gen(generator, asts, fn candidate, group_candidate, context ->
        context =
          context
          |> Map.put(n, group_candidate)
          |> Map.put(name, group_candidate)

        StreamData.constant({candidate <> group_candidate, context})
      end)
    end

    {:cont, fun}
  end

  defp do_gen(%AST.BackReference{} = backref) do
    fun = fn generator ->
      StreamData.map(generator, fn {candidate, context} ->
        value =
          case backref do
            %AST.BackReference{name: name} when not is_nil(name) ->
              Map.fetch!(context, name)

            %AST.BackReference{number: n} ->
              Map.fetch!(context, n)
          end

        {candidate <> value, context}
      end)
    end

    {:cont, fun}
  end

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
    fun = fn generator ->
      gen_loop([value], generator)
    end

    {:cont, fun}
  end

  defp do_gen(%AST.Repetition{min: min, max: max, value: ast}) do
    fun = fn generator ->
      bind_gen(generator, [ast], fn candidate, repetition_candidate, context ->
        StreamData.constant(repetition_candidate)
        |> StreamData.list_of(min_length: min, max_length: max)
        |> StreamData.map(fn repeats ->
          {candidate <> Enum.join(repeats, ""), context}
        end)
      end)
    end

    {:cont, fun}
  end

  defp do_gen(%AST.Or{left: left, right: right}) do
    fun = fn generator ->
      StreamData.one_of([StreamData.constant(left), StreamData.constant(right)])
      |> StreamData.bind(fn ast ->
        gen_loop(ast, generator)
      end)
    end

    {:cont, fun}
  end

  defp do_gen(%AST.Range{first: first, last: last}) do
    fun = fn generator ->
      StreamData.bind({gen([first]), gen([last])}, fn {<<first::utf8>>, <<last::utf8>>} ->
        StreamData.integer(first..last)
        |> StreamData.map(&<<&1::utf8>>)
        |> StreamData.bind(fn char ->
          StreamData.bind(generator, fn {candidate, context} ->
            StreamData.constant({candidate <> char, context})
          end)
        end)
      end)
    end

    {:cont, fun}
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

  defp gen_loop([], generator), do: generator

  defp gen_loop([ast | rest], generator) do
    case do_gen(ast) do
      {:cont, fun} ->
        gen_loop(rest, fun.(generator))

      current ->
        generator =
          StreamData.bind(generator, fn {old, context} ->
            StreamData.bind(current, fn new ->
              StreamData.constant({old <> new, context})
            end)
          end)

        gen_loop(rest, generator)
    end
  end

  defp bind_gen(generator, sub, callback) do
    StreamData.bind(generator, fn {candidate, context} ->
      gen_loop(sub, StreamData.constant({candidate, context}))
      |> StreamData.bind(fn {new_candidate, context} ->
        sub_candidate = String.replace_prefix(new_candidate, candidate, "")
        callback.(candidate, sub_candidate, context)
      end)
    end)
  end
end
