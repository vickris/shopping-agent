defmodule DealAgent.Checkout.RemoteInput do
  @moduledoc false
  @keys ~w(Enter Tab Shift+Tab Backspace Delete ArrowLeft ArrowRight ArrowUp ArrowDown Home End Escape ControlOrMeta+A Space)
  def valid?(%{"type" => "frame"} = input), do: map_size(input) == 1

  def valid?(%{"type" => "click", "x" => x, "y" => y} = input) when map_size(input) == 3,
    do: is_number(x) and x >= 0 and x < 1024 and is_number(y) and y >= 0 and y < 768

  def valid?(%{"type" => "scroll", "delta" => delta} = input) when map_size(input) == 2,
    do: is_number(delta) and abs(delta) <= 768

  def valid?(%{"type" => "text", "text" => text} = input) when map_size(input) == 2,
    do: is_binary(text) and byte_size(text) <= 8192 and String.length(text) <= 2048

  def valid?(%{"type" => "key", "key" => key} = input) when map_size(input) == 2, do: key in @keys

  def valid?(%{"type" => "tab", "index" => index} = input) when map_size(input) == 2,
    do: is_integer(index) and index >= 0 and index < 20

  def valid?(%{"type" => "dialog", "choice" => choice} = input) when map_size(input) == 2,
    do: choice in ["accept", "dismiss"]

  def valid?(%{"type" => "dialog", "choice" => choice, "text" => text} = input)
      when map_size(input) == 3,
      do:
        choice in ["accept", "dismiss"] and is_binary(text) and byte_size(text) <= 8192 and
          String.length(text) <= 2048

  def valid?(_), do: false
end
