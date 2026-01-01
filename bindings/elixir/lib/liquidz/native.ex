defmodule Liquidz.Native do
  @moduledoc false

  @on_load :load_nif

  def load_nif do
    path = :filename.join(:code.priv_dir(:liquidz), ~c"liquidz_nif")
    :erlang.load_nif(path, 0)
  end

  @doc false
  def render_nif(_template, _json) do
    :erlang.nif_error(:not_loaded)
  end
end
