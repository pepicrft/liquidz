defmodule Liquidz do
  @moduledoc """
  High-performance Liquid template engine for Elixir, powered by Zig.

  ## Examples

      iex> Liquidz.render("Hello, {{ name }}!", %{name: "World"})
      {:ok, "Hello, World!"}

      iex> Liquidz.render!("{{ items | join: ', ' }}", %{items: ["a", "b", "c"]})
      "a, b, c"

  """

  alias Liquidz.Native

  @doc """
  Renders a Liquid template with the given data.

  Returns `{:ok, result}` on success or `{:error, reason}` on failure.

  ## Parameters

    - `template` - The Liquid template string
    - `data` - The data to render with (map, keyword list, or JSON string)

  ## Examples

      iex> Liquidz.render("Hello, {{ name }}!", %{name: "World"})
      {:ok, "Hello, World!"}

      iex> Liquidz.render("{% for i in items %}{{ i }}{% endfor %}", %{items: [1, 2, 3]})
      {:ok, "123"}

  """
  @spec render(String.t(), map() | Keyword.t() | String.t()) :: {:ok, String.t()} | {:error, term()}
  def render(template, data \\ %{})

  def render(template, data) when is_binary(template) and is_binary(data) do
    Native.render_nif(template, data)
  end

  def render(template, data) when is_binary(template) and is_map(data) do
    json = Jason.encode!(data)
    Native.render_nif(template, json)
  end

  def render(template, data) when is_binary(template) and is_list(data) do
    json = Jason.encode!(Map.new(data))
    Native.render_nif(template, json)
  end

  @doc """
  Renders a Liquid template with the given data.

  Raises on error.

  ## Parameters

    - `template` - The Liquid template string
    - `data` - The data to render with (map, keyword list, or JSON string)

  ## Examples

      iex> Liquidz.render!("Hello, {{ name }}!", %{name: "World"})
      "Hello, World!"

  """
  @spec render!(String.t(), map() | Keyword.t() | String.t()) :: String.t()
  def render!(template, data \\ %{}) do
    case render(template, data) do
      {:ok, result} -> result
      {:error, reason} -> raise "Liquidz render failed: #{inspect(reason)}"
    end
  end

  @doc """
  Renders a Liquid template string (alias for render/2).
  """
  @spec render_string(String.t(), map() | Keyword.t() | String.t()) :: {:ok, String.t()} | {:error, term()}
  def render_string(template, data \\ %{}), do: render(template, data)

  @doc """
  Renders a Liquid template string (alias for render!/2).
  """
  @spec render_string!(String.t(), map() | Keyword.t() | String.t()) :: String.t()
  def render_string!(template, data \\ %{}), do: render!(template, data)
end
