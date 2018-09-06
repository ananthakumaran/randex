defmodule Randex.AST do
  defmodule Char do
    defstruct [:value]
  end

  defmodule Assertion do
    defstruct [:value]
  end

  defmodule Dot do
    defstruct []
  end

  defmodule Class do
    defstruct [:values, negate: false]
  end

  defmodule Range do
    defstruct [:first, :last]
  end

  defmodule Or do
    defstruct [:left, :right]
  end

  defmodule Group do
    defstruct [:values, :capture, :name, :number]
  end

  defmodule Repetition do
    defstruct [:min, :max, :value]
  end

  defmodule Lazy do
    defstruct [:value]
  end

  defmodule Option do
    defstruct [:value]
  end

  defmodule Comment do
    defstruct [:value]
  end

  defmodule BackReference do
    defstruct [:name, :number]
  end

  defmodule LookAhead do
    defstruct [:positive, :value]
  end

  defmodule LookBehind do
    defstruct [:positive, :value]
  end
end
