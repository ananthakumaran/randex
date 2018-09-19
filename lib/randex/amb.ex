defmodule Randex.Amb do
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

  def integer(range) do
    fn ->
      Enum.random(range)
    end
  end

  def string() do
    fn ->
      char = Enum.random(?\s..?~)
      List.to_string([char])
    end
  end

  def repeat(amb, n, fun) when is_function(amb) do
    if n == 0 do
      amb
    else
      repeat(fun.(amb), n - 1, fun)
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

  def bind(amb, fun) when is_function(amb) do
    bind_filter(amb, fn x ->
      {:cont, fun.(x)}
    end)
  end

  def map(amb, fun) when is_function(amb) do
    bind(amb, fn x ->
      constant(fun.(x))
    end)
  end
end
