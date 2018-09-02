defmodule Randex.Generator do
  alias Randex.AST
  alias Randex.Utils
  import Randex.Amb

  defmodule State do
    defstruct group: %{}, stack: []
  end

  def gen(asts) do
    gen_loop(asts, constant({"", %State{}}))
    |> map(fn {candidate, _state} -> candidate end)
  end

  defp do_gen(%AST.Char{value: char}) do
    constant(char)
  end

  defp do_gen(%AST.Group{values: asts, name: name, number: n}) do
    fun = fn generator ->
      bind_gen(generator, asts, fn candidate, group_candidate, state ->
        group =
          state.group
          |> Map.put(n, group_candidate)
          |> Map.put(name, group_candidate)

        state = %{state | group: group}

        constant({candidate <> group_candidate, state})
      end)
    end

    {:cont, fun}
  end

  defp do_gen(%AST.BackReference{} = backref) do
    fun = fn generator ->
      bind_filter(
        generator,
        fn {candidate, state} ->
          value =
            case backref do
              %AST.BackReference{name: name} when not is_nil(name) ->
                Map.get(state.group, name)

              %AST.BackReference{number: n} ->
                Map.get(state.group, n)
            end

          if value do
            {:cont, constant({candidate <> value, state})}
          else
            :skip
          end
        end
      )
    end

    {:cont, fun}
  end

  defp do_gen(%AST.Class{} = ast) do
    gen_class(ast)
  end

  defp do_gen(%AST.Circumflex{}) do
    constant("")
  end

  defp do_gen(%AST.Dollar{}) do
    constant("")
  end

  defp do_gen(%AST.Option{}) do
    constant("")
  end

  defp do_gen(%AST.Comment{}) do
    constant("")
  end

  defp do_gen(%AST.Lazy{value: value}) do
    fun = fn generator ->
      gen_loop([value], generator)
    end

    {:cont, fun}
  end

  defp do_gen(%AST.Repetition{min: min, max: max, value: ast}) do
    fun = fn generator ->
      bind_gen(generator, [ast], fn candidate, repetition_candidate, state ->
        constant(repetition_candidate)
        |> list_of(min, max)
        |> map(fn repeats ->
          {candidate <> Enum.join(repeats, ""), state}
        end)
      end)
    end

    {:cont, fun}
  end

  defp do_gen(%AST.Or{left: left, right: right}) do
    fun = fn generator ->
      member_of([left, right])
      |> bind(fn ast ->
        gen_loop(ast, generator)
      end)
    end

    {:cont, fun}
  end

  defp do_gen(%AST.Range{first: first, last: last}) do
    fun = fn generator ->
      bind(gen([first]), fn <<first::utf8>> ->
        bind(gen([last]), fn <<last::utf8>> ->
          integer(first..last)
          |> map(&<<&1::utf8>>)
          |> bind(fn char ->
            bind(generator, fn {candidate, state} ->
              constant({candidate <> char, state})
            end)
          end)
        end)
      end)
    end

    {:cont, fun}
  end

  defp do_gen(%AST.Dot{}) do
    string()
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
      integer(range)
      |> map(&<<&1::utf8>>)
    end)
    |> one_of()
  end

  defp gen_loop([], generator), do: generator

  defp gen_loop([ast | rest], generator) do
    case do_gen(ast) do
      {:cont, fun} ->
        gen_loop(rest, fun.(generator))

      current ->
        generator =
          bind(generator, fn {old, state} ->
            bind(current, fn new ->
              constant({old <> new, state})
            end)
          end)

        gen_loop(rest, generator)
    end
  end

  defp bind_gen(generator, sub, callback) do
    generator =
      map(generator, fn {candidate, state} ->
        state = %{state | stack: [candidate | state.stack]}
        {candidate, state}
      end)

    gen_loop(sub, generator)
    |> bind(fn {new_candidate, state} ->
      [candidate | rest] = state.stack
      state = %{state | stack: rest}
      sub_candidate = String.replace_prefix(new_candidate, candidate, "")
      callback.(candidate, sub_candidate, state)
    end)
  end
end
