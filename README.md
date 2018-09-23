# Randex

[![Build Status](https://secure.travis-ci.org/ananthakumaran/randex.svg?branch=master)](http://travis-ci.org/ananthakumaran/randex)
[![Hex.pm](https://img.shields.io/hexpm/v/randex.svg)](https://hex.pm/packages/randex)

A library to generate random strings that match the given Regex

## Example

```elixir
iex> Randex.stream(~r/(1[0-2]|0[1-9])(:[0-5]\d){2} (A|P)M/) |> Enum.take(10) |> Enum.each(&IO.puts/1)
10:43:51 PM
10:41:31 PM
03:09:55 PM
11:19:50 AM
11:20:41 PM
01:15:54 PM
02:10:04 AM
03:43:47 PM
09:39:03 AM
11:23:46 PM
```

Check [documentation](https://hexdocs.pm/randex) for more information.
