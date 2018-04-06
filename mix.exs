defmodule Event.MixProject do
  use Mix.Project

  def project do
    [
      app: :event,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:gen_stage, "~> 0.13.1"}
    ]
  end

  def description do
    "GenStage wrapper for simplifying event consumption and production"
  end

  def package do
    [
      name: "event",
      maintainers: ["Warren Kenny"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/wrren/event.ex"}
    ]
  end
end
