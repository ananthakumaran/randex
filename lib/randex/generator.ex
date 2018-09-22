defmodule Randex.Generator do
  @moduledoc false

  alias Randex.AST
  alias Randex.Utils

  defmodule Config do
    @moduledoc false
    defstruct mod: Randex.Generator.Random, max_repetition: 100
  end

  defmodule State do
    @moduledoc false
    defstruct group: %{}, stack: []
  end

  def gen(asts, config \\ %Config{}) do
    gen_loop(asts, config, config.mod.constant({"", %State{}}))
    |> config.mod.map(fn {candidate, _state} -> candidate end)
    |> config.mod.to_stream
  end

  defp do_gen(%AST.Char{value: char, caseless: caseless}, config) do
    if caseless do
      config.mod.member_of(Utils.swap_char_case(char))
    else
      config.mod.constant(char)
    end
  end

  defp do_gen({:group_end, %AST.Group{name: name, number: n}}, config) do
    fun = fn generator ->
      config.mod.map(generator, fn {new_candidate, state} ->
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

  defp do_gen(%AST.Group{values: asts} = group, config) do
    fun = fn generator, rest ->
      generator =
        config.mod.map(generator, fn {candidate, state} ->
          state = %{state | stack: [candidate | state.stack]}
          {candidate, state}
        end)

      gen_loop(asts ++ [{:group_end, group}] ++ rest, config, generator)
    end

    {:cont_rest, fun}
  end

  defp do_gen(%AST.BackReference{} = backref, config) do
    fun = fn generator ->
      config.mod.bind_filter(
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
            {:cont, config.mod.constant({candidate <> value, state})}
          else
            :skip
          end
        end
      )
    end

    {:cont, fun}
  end

  defp do_gen(%AST.LookBehind{positive: positive, value: value}, config) do
    fun = fn generator ->
      config.mod.bind_filter(
        generator,
        fn {candidate, state} ->
          value =
            if positive do
              candidate =~ value
            else
              !(candidate =~ value)
            end

          if value do
            {:cont, config.mod.constant({candidate, state})}
          else
            :skip
          end
        end
      )
    end

    {:cont, fun}
  end

  defp do_gen(%AST.LookAhead{positive: positive, value: value}, config) do
    fun = fn generator, rest ->
      bind_gen(generator, config, rest, &config.mod.bind_filter/2, fn candidate,
                                                                      sub_candidate,
                                                                      state ->
        value =
          if positive do
            sub_candidate =~ value
          else
            !(sub_candidate =~ value)
          end

        if value do
          {:cont, config.mod.constant({candidate <> sub_candidate, state})}
        else
          :skip
        end
      end)
    end

    {:cont_rest, fun}
  end

  defp do_gen(%AST.Assertion{value: value, ahead: false}, config) do
    fun = fn generator ->
      config.mod.bind_filter(
        generator,
        fn {candidate, state} ->
          if candidate =~ ~r/#{value}\z/ do
            {:cont, config.mod.constant({candidate, state})}
          else
            :skip
          end
        end
      )
    end

    {:cont, fun}
  end

  defp do_gen(%AST.Assertion{value: value, ahead: true}, config) when value in ["\\b", "\\B"] do
    fun = fn generator, rest ->
      bind_gen(generator, config, rest, &config.mod.bind_filter/2, fn candidate,
                                                                      sub_candidate,
                                                                      state ->
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
          {:cont, config.mod.constant({candidate <> sub_candidate, state})}
        else
          :skip
        end
      end)
    end

    {:cont_rest, fun}
  end

  defp do_gen(%AST.Assertion{value: value, ahead: true}, config) do
    fun = fn generator, rest ->
      bind_gen(generator, config, rest, &config.mod.bind_filter/2, fn candidate,
                                                                      sub_candidate,
                                                                      state ->
        if sub_candidate =~ ~r/\A#{value}/ do
          {:cont, config.mod.constant({candidate <> sub_candidate, state})}
        else
          :skip
        end
      end)
    end

    {:cont_rest, fun}
  end

  defp do_gen(%AST.Class{} = ast, config) do
    gen_class(ast, config)
  end

  defp do_gen(%AST.Option{}, config) do
    config.mod.constant("")
  end

  defp do_gen(%AST.Comment{}, config) do
    config.mod.constant("")
  end

  defp do_gen(%AST.Verb{}, config) do
    config.mod.constant("")
  end

  defp do_gen(%AST.Lazy{value: value}, config) do
    fun = fn generator ->
      gen_loop([value], config, generator)
    end

    {:cont, fun}
  end

  defp do_gen(%AST.Possesive{value: value}, config) do
    fun = fn generator ->
      gen_loop([value], config, generator)
    end

    {:cont, fun}
  end

  defp do_gen(%AST.Repetition{min: min, max: max, value: ast}, config) do
    fun = fn generator ->
      max =
        if max == :infinity do
          min + config.max_repetition
        else
          max
        end

      config.mod.integer(min..max)
      |> config.mod.bind(fn n ->
        config.mod.repeat(generator, n, fn g -> gen_loop([ast], config, g) end)
      end)
    end

    {:cont, fun}
  end

  defp do_gen(%AST.Or{left: left, right: right}, config) do
    fun = fn generator, rest ->
      config.mod.member_of([left, right])
      |> config.mod.bind(fn ast ->
        gen_loop(ast ++ rest, config, generator)
      end)
    end

    {:cont_rest, fun}
  end

  defp do_gen(%AST.Range{first: first, last: last}, config) do
    fun = fn generator ->
      config.mod.bind(gen([first], config), fn <<first::utf8>> ->
        config.mod.bind(gen([last], config), fn <<last::utf8>> ->
          config.mod.integer(first..last)
          |> config.mod.map(&<<&1::utf8>>)
          |> config.mod.bind(fn char ->
            config.mod.bind(generator, fn {candidate, state} ->
              config.mod.constant({candidate <> char, state})
            end)
          end)
        end)
      end)
    end

    {:cont, fun}
  end

  defp do_gen(%AST.Dot{}, config) do
    config.mod.string()
  end

  defp gen_class(%AST.Class{values: asts, negate: negate, caseless: caseless}, config) do
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
      config.mod.integer(range)
      |> config.mod.map(&Utils.integer_to_string(&1))
    end)
    |> config.mod.one_of()
  end

  defp gen_loop([], _config, generator), do: generator

  defp gen_loop([ast | rest], config, generator) do
    case do_gen(ast, config) do
      {:cont, fun} ->
        gen_loop(rest, config, fun.(generator))

      {:cont_rest, fun} ->
        fun.(generator, rest)

      current ->
        generator =
          config.mod.bind(generator, fn {old, state} ->
            config.mod.bind(current, fn new ->
              config.mod.constant({old <> new, state})
            end)
          end)

        gen_loop(rest, config, generator)
    end
  end

  defp bind_gen(generator, config, sub, combiner, callback) do
    generator =
      config.mod.map(generator, fn {candidate, state} ->
        state = %{state | stack: [candidate | state.stack]}
        {candidate, state}
      end)

    gen_loop(sub, config, generator)
    |> combiner.(fn {new_candidate, state} ->
      [candidate | rest] = state.stack
      state = %{state | stack: rest}
      sub_candidate = String.replace_prefix(new_candidate, candidate, "")
      callback.(candidate, sub_candidate, state)
    end)
  end
end
