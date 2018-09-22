defmodule Randex.Generator.Base do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      def repeat(amb, n, fun) do
        if n == 0 do
          amb
        else
          repeat(fun.(amb), n - 1, fun)
        end
      end

      def string do
        member_of(?\s..?~)
        |> map(&List.to_string([&1]))
      end

      def integer(range) do
        member_of(range)
      end

      def bind(amb, fun) do
        bind_filter(amb, fn x ->
          {:cont, fun.(x)}
        end)
      end

      def map(amb, fun) do
        bind(amb, fn x ->
          constant(fun.(x))
        end)
      end
    end
  end
end
