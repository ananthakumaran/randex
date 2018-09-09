defmodule Randex.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :randex,
      version: @version,
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "A library to generate random strings that match the given Regex",
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:stream_data, "~> 0.4"},
      {:ex_doc, "~> 0.15.0", only: :dev}
    ]
  end

  defp package do
    %{
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/ananthakumaran/randex"},
      maintainers: ["ananthakumaran@gmail.com"]
    }
  end

  defp docs do
    [
      source_url: "https://github.com/ananthakumaran/randex",
      source_ref: "v#{@version}",
      main: Randex,
      extras: ["README.md"]
    ]
  end
end
