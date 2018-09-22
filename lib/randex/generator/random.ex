defmodule Randex.Generator.Random do
  use Randex.Generator.Base

  @moduledoc false
  @skip :__skip__

  def to_stream(amb) do
    Stream.repeatedly(amb)
    |> Stream.transform(0, fn candidate, acc ->
      cond do
        candidate != @skip -> {[candidate], 0}
        acc > 1000 -> {:halt, acc}
        true -> {[], acc + 1}
      end
    end)
  end

  def constant(value) do
    fn ->
      value
    end
  end

  def member_of(list) do
    fn ->
      Enum.random(list)
    end
  end

  def one_of(list) do
    fn ->
      Enum.random(list).()
    end
  end

  def bind_filter(amb, fun) when is_function(amb) do
    fn ->
      case amb.() do
        @skip ->
          @skip

        x ->
          case fun.(x) do
            :skip -> @skip
            {:cont, amb} -> amb.()
          end
      end
    end
  end
end
