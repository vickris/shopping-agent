defmodule Mix.Tasks.Extension.Build do
  use Mix.Task
  @shortdoc "Package the unpacked desktop checkout extension for download"
  @requirements ["compile"]
  @impl true
  def run(_) do
    source = Path.expand("extension")

    names =
      ~w(manifest.json policy.js adapters.js background.js bridge.js checkout.html checkout.js checkout.css README.md)

    files =
      Enum.map(names, fn name ->
        {String.to_charlist(name), File.read!(Path.join(source, name))}
      end)

    path = Path.expand("priv/static/downloads/shopping-agent-extension.zip")
    File.mkdir_p!(Path.dirname(path))
    {:ok, _} = :zip.create(String.to_charlist(path), files)
    Mix.shell().info("Packaged Shopping Agent browser extension")
  end
end
