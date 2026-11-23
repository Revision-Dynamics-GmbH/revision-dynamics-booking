defmodule Tymeslot.RdVisit.Request do
  @moduledoc """
  A visit booking as the website sends it (`Tymeslot.RdVisit.book/1`), held
  to its limits before anything is read or written.
  """

  alias Tymeslot.Bookings.Institution

  # A visit is always 90 minutes, for every product (Tim, 23 November 2026).
  @minutes 90
  @max_travel 4
  @limits %{address: 300, name: 120, email: 254, title: 200, description: 2000}
  @control ~r/[\p{Cc}\p{Zl}\p{Zp}]+/u
  @control_but_newlines ~r/[\x{0}-\x{8}\x{B}\x{C}\x{E}-\x{1F}]/u

  @type travel :: %{
          start: DateTime.t(),
          end: DateTime.t(),
          title: String.t(),
          description: String.t()
        }
  @type t :: %{
          start: DateTime.t(),
          end: DateTime.t(),
          address: String.t(),
          name: String.t(),
          email: String.t(),
          institution: String.t(),
          locale: String.t(),
          product: String.t(),
          travel: [travel()]
        }

  @doc """
  The request, or `{:error, :invalid}`. String keys: `start` (ISO 8601 with
  offset, in the future), `minutes` (always #{@minutes}), `address`, `name`, `email`,
  `institution` (as the online booking form takes it), `locale` (de, en),
  `product` (humanos, organisationos) and up to #{@max_travel} `travel`
  entries within six hours of the visit, each with `start`, `end`, `title`
  and `description`.
  """
  @spec parse(map()) :: {:ok, t()} | {:error, :invalid}
  def parse(params) when is_map(params) do
    with {:ok, start_at, end_at} <- timing(params),
         {:ok, person} <- person(params),
         {:ok, address} <- text(params["address"], 3, @limits.address),
         {:ok, travel} <- travel(params["travel"], start_at, end_at) do
      {:ok, Map.merge(person, %{start: start_at, end: end_at, address: address, travel: travel})}
    else
      _invalid -> {:error, :invalid}
    end
  end

  def parse(_params), do: {:error, :invalid}

  defp timing(params) do
    with {:ok, start_at} <- instant(params["start"]),
         @minutes <- params["minutes"],
         :gt <- DateTime.compare(start_at, DateTime.utc_now()) do
      {:ok, start_at, DateTime.add(start_at, @minutes * 60, :second)}
    else
      _invalid -> :error
    end
  end

  defp person(params) do
    with {:ok, name} <- text(params["name"], 1, @limits.name),
         {:ok, email} <- email(params["email"]),
         institution when is_binary(institution) <- Institution.normalise(params["institution"]),
         true <- String.length(institution) <= Institution.max_length(),
         locale when locale in ["de", "en"] <- params["locale"],
         product when product in ["humanos", "organisationos"] <- params["product"] do
      {:ok,
       %{name: name, email: email, institution: institution, locale: locale, product: product}}
    else
      _invalid -> :error
    end
  end

  defp instant(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, DateTime.truncate(at, :second)}
      _error -> :error
    end
  end

  defp instant(_value), do: :error

  defp text(value, min, max) when is_binary(value) do
    if String.valid?(value) do
      clean = value |> String.replace(@control, " ") |> String.trim()
      length = String.length(clean)
      if length >= min and length <= max, do: {:ok, clean}, else: :error
    else
      :error
    end
  end

  defp text(_value, _min, _max), do: :error

  defp email(value) when is_binary(value) do
    clean = String.trim(value)

    if byte_size(clean) <= @limits.email and Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, clean),
      do: {:ok, clean},
      else: :error
  end

  defp email(_value), do: :error

  # The entries are the website's, which knows the roads; they are only held
  # to a sane shape and kept near the visit.
  defp travel(nil, _start_at, _end_at), do: {:ok, []}

  defp travel(entries, start_at, end_at)
       when is_list(entries) and length(entries) <= @max_travel do
    earliest = DateTime.add(start_at, -6 * 3600, :second)
    latest = DateTime.add(end_at, 6 * 3600, :second)

    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      case travel_entry(entry, earliest, latest) do
        {:ok, parsed} -> {:cont, {:ok, acc ++ [parsed]}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp travel(_entries, _start_at, _end_at), do: :error

  defp travel_entry(%{} = entry, earliest, latest) do
    with {:ok, s} <- instant(entry["start"]),
         {:ok, e} <- instant(entry["end"]),
         :lt <- DateTime.compare(s, e),
         true <- DateTime.compare(s, earliest) != :lt and DateTime.compare(e, latest) != :gt,
         {:ok, title} <- text(entry["title"], 1, @limits.title),
         {:ok, description} <- multiline(entry["description"]) do
      {:ok, %{start: s, end: e, title: title, description: description}}
    else
      _invalid -> :error
    end
  end

  defp travel_entry(_entry, _earliest, _latest), do: :error

  defp multiline(nil), do: {:ok, ""}

  defp multiline(value) when is_binary(value) do
    clean = String.replace(value, @control_but_newlines, "")

    if String.valid?(value) and String.length(clean) <= @limits.description,
      do: {:ok, clean},
      else: :error
  end

  defp multiline(_value), do: :error
end
