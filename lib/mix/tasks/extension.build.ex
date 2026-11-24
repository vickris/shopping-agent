defmodule Mix.Tasks.Extension.Build do
  use Mix.Task
  @shortdoc "Package the unpacked desktop checkout extension for download"
  @requirements ["compile"]
  @impl true
  def run(_) do
    source = Path.expand("extension")
    # Keep the extension's serialized storefront controls identical to the server.
    File.cp!("priv/carrefour_browser/storefront_steps.mjs", Path.join(source, "adapters.js"))

    names =
      ~w(manifest.json policy.js adapters.js background.js local_helper.js bridge.js checkout.html checkout.js checkout.css README.md)

    files =
      Enum.map(names, fn name ->
        {String.to_charlist(name), File.read!(Path.join(source, name))}
      end)

    path = Path.expand("priv/static/downloads/shopping-agent-extension.zip")
    File.mkdir_p!(Path.dirname(path))
    {:ok, _} = :zip.create(String.to_charlist(path), files)
    helper_names = ~w(cart.mjs host.mjs protocol.mjs install.mjs README.md)
    browser_names = ~w(browser_handoff.mjs package.json package-lock.json)

    helper_files =
      Enum.map(names, fn name ->
        {String.to_charlist("extension/" <> name), File.read!(Path.join(source, name))}
      end) ++
        Enum.map(helper_names, fn name ->
          path = "priv/local_helper/" <> name
          {String.to_charlist(path), File.read!(path)}
        end) ++
        Enum.map(browser_names, fn name ->
          path = "priv/carrefour_browser/" <> name
          {String.to_charlist(path), File.read!(path)}
        end)

    helper_path = Path.expand("priv/static/downloads/shopping-agent-local-helper.zip")
    {:ok, _} = :zip.create(String.to_charlist(helper_path), helper_files)
    Mix.shell().info("Packaged Shopping Agent browser extension and local helper")
  end
end
