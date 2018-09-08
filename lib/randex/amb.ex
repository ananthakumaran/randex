defmodule Randex.Amb do
  @skip :__skip__

  def to_stream(amb) do
    Stream.repeatedly(amb)
    |> Stream.filter(&(&1 != @skip))
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
    fn ->
      if n == 0 do
        amb.()
      else
        repeat(fun.(amb), n - 1, fun).()
      end
    end
  end

  def bind_filter(s, fun) when is_function(s) do
    fn ->
      case s.() do
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

  def bind(s, fun) when is_function(s) do
    fn ->
      case s.() do
        @skip ->
          @skip

        x ->
          fun.(x).()
      end
    end
  end

  def map(s, fun) when is_function(s) do
    fn ->
      case s.() do
        @skip ->
          @skip

        x ->
          fun.(x)
      end
    end
  end
end
