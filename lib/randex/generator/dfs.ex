defmodule Randex.Generator.DFS do
  use Randex.Generator.Base

  @moduledoc false

  def to_stream(amb), do: amb

  def constant(value) do
    [value]
  end

  def member_of(list) do
    list
  end

  def one_of(list) do
    Stream.flat_map(list, fn x -> x end)
  end

  def bind_filter(s, fun) do
    Stream.flat_map(s, fn x ->
      case fun.(x) do
        :skip -> []
        {:cont, amb} -> amb
      end
    end)
  end
end
