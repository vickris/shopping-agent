defmodule DealAgent.Delivery.CoordinatesTest do
  use ExUnit.Case, async: true
  alias DealAgent.Delivery.Coordinates

  test "validates numeric coordinates and accuracy before store startup" do
    assert {:ok, %{latitude: -1.367, longitude: 36.936, accuracy: 100}} =
             Coordinates.normalize(%{
               "latitude" => -1.367,
               "longitude" => 36.936,
               "accuracy" => 100
             })

    for point <- [
          %{},
          %{"latitude" => "-1.3", "longitude" => 36},
          %{"latitude" => 91, "longitude" => 36},
          %{"latitude" => 1, "longitude" => 181},
          %{"latitude" => 1, "longitude" => 36, "accuracy" => -1}
        ] do
      assert {:error, :invalid_coordinates} = Coordinates.normalize(point)
    end
  end

  test "precise location values are filtered from Phoenix parameter logs" do
    point = %{"latitude" => -1.367, "longitude" => 36.936, "accuracy" => 100}

    assert Phoenix.Logger.filter_values(point) == %{
             "latitude" => "[FILTERED]",
             "longitude" => "[FILTERED]",
             "accuracy" => "[FILTERED]"
           }
  end
end
