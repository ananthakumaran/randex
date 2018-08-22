defmodule Randex.AST do
  defmodule Char do
    defstruct [:value]
  end

  defmodule Circumflex do
    defstruct []
  end

  defmodule Dollar do
    defstruct []
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
    defstruct [:values, :capture]
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
end
