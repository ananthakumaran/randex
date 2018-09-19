defmodule Randex.Generator do
  @moduledoc false

  alias Randex.AST
  alias Randex.Utils
  import Randex.Amb

  defmodule State do
    @moduledoc false
    defstruct group: %{}, stack: []
  end

  def gen(asts) do
    gen_loop(asts, constant({"", %State{}}))
    |> map(fn {candidate, _state} -> candidate end)
    |> to_stream
  end

  defp do_gen(%AST.Char{value: char, caseless: caseless}) do
    if caseless do
      member_of(Utils.swap_char_case(char))
    else
      constant(char)
    end
  end

  defp do_gen({:group_end, %AST.Group{name: name, number: n}}) do
    fun = fn generator ->
      map(generator, fn {new_candidate, state} ->
        [candidate | rest] = state.stack
        state = %{state | stack: rest}
        group_candidate = String.replace_prefix(new_candidate, candidate, "")

        group =
          state.group
          |> Map.put(n, group_candidate)
          |> Map.put(name, group_candidate)

        state = %{state | group: group}

        {new_candidate, state}
      end)
    end

    {:cont, fun}
  end

  defp do_gen(%AST.Group{values: asts} = group) do
    fun = fn generator, rest ->
      generator =
        map(generator, fn {candidate, state} ->
          state = %{state | stack: [candidate | state.stack]}
          {candidate, state}
        end)

      gen_loop(asts ++ [{:group_end, group}] ++ rest, generator)
    end

    {:cont_rest, fun}
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

  defp do_gen(%AST.LookBehind{positive: positive, value: value}) do
    fun = fn generator ->
      bind_filter(
        generator,
        fn {candidate, state} ->
          value =
            if positive do
              candidate =~ value
            else
              !(candidate =~ value)
            end

          if value do
            {:cont, constant({candidate, state})}
          else
            :skip
          end
        end
      )
    end

    {:cont, fun}
  end

  defp do_gen(%AST.LookAhead{positive: positive, value: value}) do
    fun = fn generator, rest ->
      bind_gen(generator, rest, &bind_filter/2, fn candidate, sub_candidate, state ->
        value =
          if positive do
            sub_candidate =~ value
          else
            !(sub_candidate =~ value)
          end

        if value do
          {:cont, constant({candidate <> sub_candidate, state})}
        else
          :skip
        end
      end)
    end

    {:cont_rest, fun}
  end

  defp do_gen(%AST.Assertion{value: value, ahead: false}) do
    fun = fn generator ->
      bind_filter(
        generator,
        fn {candidate, state} ->
          if candidate =~ ~r/#{value}\z/ do
            {:cont, constant({candidate, state})}
          else
            :skip
          end
        end
      )
    end

    {:cont, fun}
  end

  defp do_gen(%AST.Assertion{value: value, ahead: true}) when value in ["\\b", "\\B"] do
    fun = fn generator, rest ->
      bind_gen(generator, rest, &bind_filter/2, fn candidate, sub_candidate, state ->
        match =
          case value do
            "\\b" ->
              (candidate =~ ~r/\w\z/ && sub_candidate =~ ~r/^(\W|\Z)/) ||
                (candidate =~ ~r/(^|\W)\z/ && sub_candidate =~ ~r/^\w/)

            "\\B" ->
              (candidate =~ ~r/\w\z/ && sub_candidate =~ ~r/^\w/) ||
                (candidate =~ ~r/(^|\W)\z/ && sub_candidate =~ ~r/^(\W|\Z)/)
          end

        if match do
          {:cont, constant({candidate <> sub_candidate, state})}
        else
          :skip
        end
      end)
    end

    {:cont_rest, fun}
  end

  defp do_gen(%AST.Assertion{value: value, ahead: true}) do
    fun = fn generator, rest ->
      bind_gen(generator, rest, &bind_filter/2, fn candidate, sub_candidate, state ->
        if sub_candidate =~ ~r/\A#{value}/ do
          {:cont, constant({candidate <> sub_candidate, state})}
        else
          :skip
        end
      end)
    end

    {:cont_rest, fun}
  end

  defp do_gen(%AST.Class{} = ast) do
    gen_class(ast)
  end

  defp do_gen(%AST.Option{}) do
    constant("")
  end

  defp do_gen(%AST.Comment{}) do
    constant("")
  end

  defp do_gen(%AST.Verb{}) do
    constant("")
  end

  defp do_gen(%AST.Lazy{value: value}) do
    fun = fn generator ->
      gen_loop([value], generator)
    end

    {:cont, fun}
  end

  defp do_gen(%AST.Possesive{value: value}) do
    fun = fn generator ->
      gen_loop([value], generator)
    end

    {:cont, fun}
  end

  defp do_gen(%AST.Repetition{min: min, max: max, value: ast}) do
    fun = fn generator ->
      max =
        if max == :infinity do
          min + 100
        else
          max
        end

      integer(min..max)
      |> bind(fn n ->
        repeat(generator, n, fn g -> gen_loop([ast], g) end)
      end)
    end

    {:cont, fun}
  end

  defp do_gen(%AST.Or{left: left, right: right}) do
    fun = fn generator, rest ->
      member_of([left, right])
      |> bind(fn ast ->
        gen_loop(ast ++ rest, generator)
      end)
    end

    {:cont_rest, fun}
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

  defp gen_class(%AST.Class{values: asts, negate: negate, caseless: caseless}) do
    Enum.map(asts, fn
      %AST.Char{value: <<char::integer>>} ->
        char..char

      %AST.Range{
        first: %AST.Char{value: first},
        last: %AST.Char{value: last}
      } ->
        Utils.string_to_integer(first)..Utils.string_to_integer(last)
    end)
    |> Enum.flat_map(fn range ->
      if caseless do
        Utils.swap_case(range)
      else
        [range]
      end
    end)
    |> Enum.sort_by(fn range -> range.first end)
    |> Utils.non_overlapping([])
    |> Utils.negate_range(negate)
    |> Enum.map(fn range ->
      integer(range)
      |> map(&Utils.integer_to_string(&1))
    end)
    |> one_of()
  end

  defp gen_loop([], generator), do: generator

  defp gen_loop([ast | rest], generator) do
    case do_gen(ast) do
      {:cont, fun} ->
        gen_loop(rest, fun.(generator))

      {:cont_rest, fun} ->
        fun.(generator, rest)

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

  defp bind_gen(generator, sub, combiner, callback) do
    generator =
      map(generator, fn {candidate, state} ->
        state = %{state | stack: [candidate | state.stack]}
        {candidate, state}
      end)

    gen_loop(sub, generator)
    |> combiner.(fn {new_candidate, state} ->
      [candidate | rest] = state.stack
      state = %{state | stack: rest}
      sub_candidate = String.replace_prefix(new_candidate, candidate, "")
      callback.(candidate, sub_candidate, state)
    end)
  end
end
