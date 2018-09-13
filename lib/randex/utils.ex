defmodule Randex.Utils do
  @moduledoc false

  def non_overlapping([], []), do: []
  def non_overlapping([x], acc), do: Enum.reverse([x | acc])

  def non_overlapping([a | [b | rest]], acc) do
    cond do
      b.first > a.last -> non_overlapping([b | rest], [a | acc])
      true -> non_overlapping([a.first..Enum.max([a.last, b.last]) | rest], acc)
    end
  end

  def negate_range(ranges), do: negate_range(ranges, true)

  def negate_range(ranges, false), do: ranges
  def negate_range(ranges, true), do: negate_range(ranges, 32, [])

  def negate_range([], low, acc), do: Enum.reverse([low..126 | acc])

  def negate_range([a | rest], low, acc) do
    cond do
      low < a.first -> negate_range(rest, a.last + 1, [low..(a.first - 1) | acc])
      true -> negate_range(rest, a.last + 1, acc)
    end
  end

  def swap_char_case(string) do
    n = string_to_integer(string)

    swap_case(n..n)
    |> Enum.map(fn range ->
      integer_to_string(range.first)
    end)
  end

  def swap_case(range) do
    cond do
      range.last < ?A || range.first > ?z || (range.first > ?Z && range.last < ?a) -> [range]
      range.first < ?A -> [range.first..(?A - 1)] ++ swap_case(?A..range.last)
      range.last <= ?Z -> [range, (range.first + 32)..(range.last + 32)]
      range.first <= ?Z -> swap_case(range.first..?Z) ++ swap_case((?Z + 1)..range.last)
      range.last < ?a -> [range]
      range.first < ?a -> [range.first..(?a - 1)] ++ swap_case(?a..range.last)
      range.last <= ?z -> [range, (range.first - 32)..(range.last - 32)]
      range.last > ?z -> swap_case(range.first..?z) ++ [(?z + 1)..range.last]
    end
  end

  def string_to_integer(<<x::integer>>) do
    x
  end

  def integer_to_string(x) do
    <<x::integer>>
  end
end
