defmodule DealAgent.Delivery.Coordinates do
  @moduledoc false

  # Also apply on mount so a development hot reload cannot expose coordinates
  # before the changed application configuration has been reloaded.
  def protect_logs do
    keys = ~w(coordinates latitude longitude accuracy)

    filters =
      case Application.get_env(:phoenix, :filter_parameters, ["password"]) do
        {:keep, fields} -> {:keep, fields -- keys}
        {:discard, fields} -> {:discard, Enum.uniq(fields ++ keys)}
        fields when is_list(fields) -> Enum.uniq(fields ++ keys)
      end

    Application.put_env(:phoenix, :filter_parameters, filters)
  end

  def normalize(nil), do: {:ok, nil}

  def normalize(%{"latitude" => latitude, "longitude" => longitude} = point)
      when is_number(latitude) and is_number(longitude) and latitude >= -90 and latitude <= 90 and
             longitude >= -180 and longitude <= 180 do
    accuracy = Map.get(point, "accuracy", 0)

    if is_number(accuracy) and accuracy >= 0 and accuracy <= 100_000,
      do: {:ok, %{latitude: latitude, longitude: longitude, accuracy: accuracy}},
      else: {:error, :invalid_coordinates}
  end

  def normalize(_), do: {:error, :invalid_coordinates}
end
