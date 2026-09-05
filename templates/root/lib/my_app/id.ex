defmodule MyApp.Id do
  @moduledoc """
  UUID v4 with no external dependency.

  Keeps Ecto out of the domain: if it's in `deps` at all it should be there for
  something else (forms via `phoenix_ecto`, a throwaway mirror of an external
  system), never because the domain needs an identifier.
  """

  @doc "Returns a random UUID v4 string, lowercase and hyphenated."
  def uuid4 do
    <<u0::48, _::4, u1::12, _::2, u2::62>> = :crypto.strong_rand_bytes(16)
    <<a::32, b::16, c::16, d::16, e::48>> = <<u0::48, 4::4, u1::12, 2::2, u2::62>>

    :io_lib.format("~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b", [a, b, c, d, e])
    |> IO.iodata_to_binary()
  end
end
