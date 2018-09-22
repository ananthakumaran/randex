defmodule Randex.Generator.StreamData do
  use Randex.Generator.Base

  @moduledoc false

  def to_stream(s), do: s

  defdelegate constant(value), to: StreamData
  defdelegate member_of(enum), to: StreamData
  defdelegate one_of(datas), to: StreamData

  def bind_filter(data, fun) do
    StreamData.bind_filter(data, fun, 1000)
  end
end
