defmodule Randex.Context do
  @moduledoc false

  defmodule Global do
    @moduledoc false
    defstruct [:extended, :multiline, :dotall, :caseless, group: 0]
  end

  defmodule Local do
    @moduledoc false
    defstruct [:extended, :multiline, :dotall, :caseless]
  end

  defstruct [:global, :local]

  def mode?(context, mode) do
    case Map.get(context.local, mode) do
      false ->
        false

      true ->
        true

      nil ->
        !!Map.get(context.global, mode)
    end
  end

  def update_global(context, key, fun) do
    global = Map.update!(context.global, key, fun)
    %{context | global: global}
  end
end
