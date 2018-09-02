defmodule Randex.Amb do
  def to_stream(amb) do
    amb
  end

  def fail() do
    []
  end

  def constant(value) do
    [value]
  end

  def either(a, b) do
    [a, b]
  end

  def member_of(list) do
    list
  end

  def one_of(list) do
    Stream.flat_map(list, fn x -> x end)
  end

  def integer(range) do
    Stream.map(range, fn x -> x end)
  end

  def string() do
    Enum.map(?\s..?~, fn x ->
      List.to_string([x])
    end)
    |> Enum.shuffle()
  end

  def repeat(amb, n, fun) do
    if n == 0 do
      amb
    else
      repeat(fun.(amb), n - 1, fun)
    end
  end

  def bind_filter(s, fun) do
    Stream.flat_map(s, fn x ->
      case fun.(x) do
        :skip -> []
        {:cont, amb} -> amb
      end
    end)
  end

  def bind(s, fun) do
    Stream.flat_map(s, fun)
  end

  def map(s, fun) do
    Stream.map(s, fun)
  end
end
