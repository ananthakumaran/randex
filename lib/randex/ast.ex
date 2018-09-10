defmodule Randex.AST do
  @moduledoc false

  defmodule Char do
    @moduledoc false
    defstruct [:value, caseless: false]
  end

  defmodule Assertion do
    @moduledoc false
    defstruct [:value]
  end

  defmodule Dot do
    @moduledoc false
    defstruct []
  end

  defmodule Class do
    @moduledoc false
    defstruct [:values, negate: false, caseless: false]
  end

  defmodule Range do
    @moduledoc false
    defstruct [:first, :last]
  end

  defmodule Or do
    @moduledoc false
    defstruct [:left, :right]
  end

  defmodule Group do
    @moduledoc false
    defstruct [:values, :capture, :atomic, :name, :number]
  end

  defmodule Repetition do
    @moduledoc false
    defstruct [:min, :max, :value]
  end

  defmodule Lazy do
    @moduledoc false
    defstruct [:value]
  end

  defmodule Possesive do
    @moduledoc false
    defstruct [:value]
  end

  defmodule Option do
    @moduledoc false
    defstruct [:value]
  end

  defmodule Comment do
    @moduledoc false
    defstruct [:value]
  end

  defmodule BackReference do
    @moduledoc false
    defstruct [:name, :number]
  end

  defmodule LookAhead do
    @moduledoc false
    defstruct [:positive, :value]
  end

  defmodule LookBehind do
    @moduledoc false
    defstruct [:positive, :value]
  end
end
