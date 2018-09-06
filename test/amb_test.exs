defmodule AmbTest do
  require TestHelper
  import TestHelper
  import Randex.Amb
  use ExUnit.Case

  test "either" do
    assert_amb(member_of([1, 2]), [1, 2])
  end

  test "bind" do
    assert_amb(
      bind(member_of([1, 2]), fn x ->
        constant(x)
      end),
      [1, 2]
    )

    assert_amb(
      bind(member_of([1, 2]), fn x ->
        bind(member_of([3, 4]), fn y ->
          constant({x, y})
        end)
      end),
      [{1, 3}, {1, 4}, {2, 3}, {2, 4}]
    )

    assert_amb(
      integer(1..3),
      [1, 2, 3]
    )

    assert_amb(
      one_of([integer(1..2), integer(1..2)]),
      [1, 2, 1, 2]
    )
  end

  test "gen" do
    gen("[ab]")
  end
end
