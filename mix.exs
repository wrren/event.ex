defmodule Event.MixProject do
  use Mix.Project

  def project do
    [
      app: :event,
      version: "0.1.2",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env),
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
      {:gen_stage, "~> 0.13.1"},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  def elixirc_paths(:test) do
    ["lib", "test/support"]
  end
  def elixirc_paths(_) do
    ["lib"]
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
