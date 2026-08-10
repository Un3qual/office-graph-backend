defmodule OfficeGraph.TestSupport.PostgresDump do
  @moduledoc false

  def split_statements(dump) when is_binary(dump), do: split_sql(dump, :plain, [], [])

  def identifier_after(statement, prefix) do
    statement = String.trim_leading(statement)

    if String.starts_with?(statement, prefix) do
      statement
      |> binary_part(byte_size(prefix), byte_size(statement) - byte_size(prefix))
      |> take_identifier()
    end
  end

  def identifier_after_keyword(statement, keyword) do
    case find_keyword(statement, keyword, :plain) do
      nil -> nil
      rest -> take_identifier(rest)
    end
  end

  def take_identifier(input) when is_binary(input) do
    input = String.trim_leading(input)

    with {:ok, part, rest} <- take_identifier_part(input),
         {:ok, parts, rest} <- take_identifier_parts(rest, [part]) do
      {parts |> normalize_public_prefix() |> Enum.join("."), rest}
    else
      :error -> nil
    end
  end

  def identifier_parts(input) when is_binary(input) do
    input = String.trim(input)

    with {:ok, part, rest} <- take_identifier_part(input),
         {:ok, parts, rest} <- take_identifier_parts(rest, [part]),
         true <- String.trim(rest, " ;") == "" do
      normalize_public_prefix(parts)
    else
      _invalid -> nil
    end
  end

  def configured_identifier(input) when is_atom(input),
    do: input |> Atom.to_string() |> configured_identifier()

  def configured_identifier(input) when is_binary(input), do: canonical_identifier(input)

  def unqualified_identifier_value(input) when is_binary(input) do
    case identifier_parts(input) do
      nil -> nil
      parts -> parts |> List.last() |> identifier_value()
    end
  end

  def normalize_identifier(input) when is_binary(input) do
    case take_identifier(input) do
      {identity, rest} when rest in ["", ";"] -> identity
      {identity, rest} -> if String.trim(rest, " ;") == "", do: identity, else: input
      nil -> input
    end
  end

  def normalize_definition(definition) when is_binary(definition) do
    definition
    |> String.trim()
    |> String.trim_trailing(",")
    |> String.trim_trailing(";")
    |> normalize_whitespace(:plain, false, [])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
    |> String.trim()
  end

  def split_once_outside_quotes(input, keyword)
      when is_binary(input) and is_binary(keyword) and keyword != "" do
    case find_keyword(input, keyword, :plain) do
      nil ->
        nil

      rest ->
        prefix_size = byte_size(input) - byte_size(keyword) - byte_size(rest)
        {binary_part(input, 0, prefix_size), rest}
    end
  end

  def take_parenthesized(input) when is_binary(input) do
    case String.trim_leading(input) do
      <<"(", rest::binary>> -> take_parenthesized(rest, 1, :plain, [])
      _input -> nil
    end
  end

  defp take_identifier_parts(<<".", rest::binary>>, parts) do
    with {:ok, part, rest} <- take_identifier_part(rest) do
      take_identifier_parts(rest, [part | parts])
    else
      :error -> {:ok, Enum.reverse(parts), "." <> rest}
    end
  end

  defp take_identifier_parts(rest, parts), do: {:ok, Enum.reverse(parts), rest}

  defp normalize_public_prefix(["public" | remaining]) when remaining != [], do: remaining
  defp normalize_public_prefix(parts), do: parts

  defp take_identifier_part(<<"\"", rest::binary>>),
    do: take_quoted_identifier(rest, [])

  defp take_identifier_part(input) do
    case Regex.run(~r/^[A-Za-z_][A-Za-z0-9_$]*/, input) do
      [part] ->
        rest = binary_part(input, byte_size(part), byte_size(input) - byte_size(part))
        {:ok, String.downcase(part), rest}

      nil ->
        :error
    end
  end

  defp take_quoted_identifier(<<"\"\"", rest::binary>>, current),
    do: take_quoted_identifier(rest, ["\"" | current])

  defp take_quoted_identifier(<<"\"", rest::binary>>, current) do
    value = current |> Enum.reverse() |> IO.iodata_to_binary()
    {:ok, canonical_identifier(value), rest}
  end

  defp take_quoted_identifier(<<character::utf8, rest::binary>>, current),
    do: take_quoted_identifier(rest, [<<character::utf8>> | current])

  defp take_quoted_identifier(<<>>, _current), do: :error

  defp canonical_identifier(value) do
    if Regex.match?(~r/^[a-z_][a-z0-9_$]*$/, value) do
      value
    else
      "\"#{String.replace(value, "\"", "\"\"")}\""
    end
  end

  defp identifier_value(<<?\", rest::binary>>) do
    rest
    |> binary_part(0, byte_size(rest) - 1)
    |> String.replace("\"\"", "\"")
  end

  defp identifier_value(value), do: value

  defp find_keyword(<<>>, _keyword, _state), do: nil

  defp find_keyword(input, keyword, :plain) do
    cond do
      String.starts_with?(input, keyword) ->
        binary_part(input, byte_size(keyword), byte_size(input) - byte_size(keyword))

      String.starts_with?(input, "'") ->
        <<"'", rest::binary>> = input
        find_keyword(rest, keyword, :single_quote)

      String.starts_with?(input, "\"") ->
        <<"\"", rest::binary>> = input
        find_keyword(rest, keyword, :double_quote)

      delimiter = dollar_delimiter(input) ->
        rest = binary_part(input, byte_size(delimiter), byte_size(input) - byte_size(delimiter))
        find_keyword(rest, keyword, {:dollar_quote, delimiter})

      true ->
        <<_character::utf8, rest::binary>> = input
        find_keyword(rest, keyword, :plain)
    end
  end

  defp find_keyword(<<"''", rest::binary>>, keyword, :single_quote),
    do: find_keyword(rest, keyword, :single_quote)

  defp find_keyword(<<"'", rest::binary>>, keyword, :single_quote),
    do: find_keyword(rest, keyword, :plain)

  defp find_keyword(<<_character::utf8, rest::binary>>, keyword, :single_quote),
    do: find_keyword(rest, keyword, :single_quote)

  defp find_keyword(<<"\"\"", rest::binary>>, keyword, :double_quote),
    do: find_keyword(rest, keyword, :double_quote)

  defp find_keyword(<<"\"", rest::binary>>, keyword, :double_quote),
    do: find_keyword(rest, keyword, :plain)

  defp find_keyword(<<_character::utf8, rest::binary>>, keyword, :double_quote),
    do: find_keyword(rest, keyword, :double_quote)

  defp find_keyword(input, keyword, {:dollar_quote, delimiter} = state) do
    if String.starts_with?(input, delimiter) do
      rest = binary_part(input, byte_size(delimiter), byte_size(input) - byte_size(delimiter))
      find_keyword(rest, keyword, :plain)
    else
      <<_character::utf8, rest::binary>> = input
      find_keyword(rest, keyword, state)
    end
  end

  defp normalize_whitespace(<<>>, _state, _pending_space?, output), do: output

  defp normalize_whitespace(input, :plain, pending_space?, output) do
    cond do
      String.starts_with?(input, "'") ->
        <<"'", rest::binary>> = input

        normalize_whitespace(
          rest,
          :single_quote,
          false,
          ["'" | maybe_space(output, pending_space?)]
        )

      String.starts_with?(input, "\"") ->
        case take_identifier_part(input) do
          {:ok, identifier, rest} ->
            normalize_whitespace(
              rest,
              :plain,
              false,
              [identifier | maybe_space(output, pending_space?)]
            )

          :error ->
            <<"\"", rest::binary>> = input

            normalize_whitespace(
              rest,
              :double_quote,
              false,
              ["\"" | maybe_space(output, pending_space?)]
            )
        end

      delimiter = dollar_delimiter(input) ->
        rest = binary_part(input, byte_size(delimiter), byte_size(input) - byte_size(delimiter))

        normalize_whitespace(
          rest,
          {:dollar_quote, delimiter},
          false,
          [delimiter | maybe_space(output, pending_space?)]
        )

      whitespace_prefix?(input) ->
        <<_character::utf8, rest::binary>> = input
        normalize_whitespace(rest, :plain, output != [], output)

      true ->
        <<character::utf8, rest::binary>> = input

        normalize_whitespace(
          rest,
          :plain,
          false,
          [<<character::utf8>> | maybe_space(output, pending_space?)]
        )
    end
  end

  defp normalize_whitespace(<<"''", rest::binary>>, :single_quote, _pending, output),
    do: normalize_whitespace(rest, :single_quote, false, ["''" | output])

  defp normalize_whitespace(<<"'", rest::binary>>, :single_quote, _pending, output),
    do: normalize_whitespace(rest, :plain, false, ["'" | output])

  defp normalize_whitespace(<<character::utf8, rest::binary>>, :single_quote, _pending, output),
    do: normalize_whitespace(rest, :single_quote, false, [<<character::utf8>> | output])

  defp normalize_whitespace(<<"\"\"", rest::binary>>, :double_quote, _pending, output),
    do: normalize_whitespace(rest, :double_quote, false, ["\"\"" | output])

  defp normalize_whitespace(<<"\"", rest::binary>>, :double_quote, _pending, output),
    do: normalize_whitespace(rest, :plain, false, ["\"" | output])

  defp normalize_whitespace(<<character::utf8, rest::binary>>, :double_quote, _pending, output),
    do: normalize_whitespace(rest, :double_quote, false, [<<character::utf8>> | output])

  defp normalize_whitespace(input, {:dollar_quote, delimiter} = state, _pending, output) do
    if String.starts_with?(input, delimiter) do
      rest = binary_part(input, byte_size(delimiter), byte_size(input) - byte_size(delimiter))
      normalize_whitespace(rest, :plain, false, [delimiter | output])
    else
      <<character::utf8, rest::binary>> = input
      normalize_whitespace(rest, state, false, [<<character::utf8>> | output])
    end
  end

  defp maybe_space([], _pending_space?), do: []
  defp maybe_space(output, true), do: [" " | output]
  defp maybe_space(output, false), do: output

  defp whitespace_prefix?(<<character::utf8, _rest::binary>>),
    do: character in [9, 10, 11, 12, 13, 32]

  defp take_parenthesized(<<>>, _depth, _state, _current), do: nil

  defp take_parenthesized(<<"(", rest::binary>>, depth, :plain, current),
    do: take_parenthesized(rest, depth + 1, :plain, ["(" | current])

  defp take_parenthesized(<<")", rest::binary>>, 1, :plain, current),
    do: {current |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  defp take_parenthesized(<<")", rest::binary>>, depth, :plain, current),
    do: take_parenthesized(rest, depth - 1, :plain, [")" | current])

  defp take_parenthesized(<<"'", rest::binary>>, depth, :plain, current),
    do: take_parenthesized(rest, depth, :single_quote, ["'" | current])

  defp take_parenthesized(<<"\"", rest::binary>>, depth, :plain, current),
    do: take_parenthesized(rest, depth, :double_quote, ["\"" | current])

  defp take_parenthesized(<<"$", _rest::binary>> = input, depth, :plain, current) do
    case dollar_delimiter(input) do
      nil ->
        <<character::utf8, rest::binary>> = input
        take_parenthesized(rest, depth, :plain, [<<character::utf8>> | current])

      delimiter ->
        rest = binary_part(input, byte_size(delimiter), byte_size(input) - byte_size(delimiter))
        take_parenthesized(rest, depth, {:dollar_quote, delimiter}, [delimiter | current])
    end
  end

  defp take_parenthesized(<<"''", rest::binary>>, depth, :single_quote, current),
    do: take_parenthesized(rest, depth, :single_quote, ["''" | current])

  defp take_parenthesized(<<"'", rest::binary>>, depth, :single_quote, current),
    do: take_parenthesized(rest, depth, :plain, ["'" | current])

  defp take_parenthesized(<<"\"\"", rest::binary>>, depth, :double_quote, current),
    do: take_parenthesized(rest, depth, :double_quote, ["\"\"" | current])

  defp take_parenthesized(<<"\"", rest::binary>>, depth, :double_quote, current),
    do: take_parenthesized(rest, depth, :plain, ["\"" | current])

  defp take_parenthesized(input, depth, {:dollar_quote, delimiter} = state, current) do
    if String.starts_with?(input, delimiter) do
      rest = binary_part(input, byte_size(delimiter), byte_size(input) - byte_size(delimiter))
      take_parenthesized(rest, depth, :plain, [delimiter | current])
    else
      <<character::utf8, rest::binary>> = input
      take_parenthesized(rest, depth, state, [<<character::utf8>> | current])
    end
  end

  defp take_parenthesized(<<character::utf8, rest::binary>>, depth, state, current),
    do: take_parenthesized(rest, depth, state, [<<character::utf8>> | current])

  defp split_sql(<<>>, _state, current, statements) do
    statements
    |> finish_statement(current)
    |> Enum.reverse()
  end

  defp split_sql(<<"--", rest::binary>>, :plain, current, statements),
    do: split_sql(rest, :line_comment, current, statements)

  defp split_sql(<<"/*", rest::binary>>, :plain, current, statements),
    do: split_sql(rest, :block_comment, current, statements)

  defp split_sql(<<"'", rest::binary>>, :plain, current, statements),
    do: split_sql(rest, :single_quote, ["'" | current], statements)

  defp split_sql(<<"\"", rest::binary>>, :plain, current, statements),
    do: split_sql(rest, :double_quote, ["\"" | current], statements)

  defp split_sql(<<"$", _rest::binary>> = input, :plain, current, statements) do
    case dollar_delimiter(input) do
      nil ->
        <<character::utf8, rest::binary>> = input
        split_sql(rest, :plain, [<<character::utf8>> | current], statements)

      delimiter ->
        rest = binary_part(input, byte_size(delimiter), byte_size(input) - byte_size(delimiter))
        split_sql(rest, {:dollar_quote, delimiter}, [delimiter | current], statements)
    end
  end

  defp split_sql(<<";", rest::binary>>, :plain, current, statements) do
    statements = finish_statement(statements, [";" | current])
    split_sql(rest, :plain, [], statements)
  end

  defp split_sql(<<"''", rest::binary>>, :single_quote, current, statements),
    do: split_sql(rest, :single_quote, ["''" | current], statements)

  defp split_sql(<<"'", rest::binary>>, :single_quote, current, statements),
    do: split_sql(rest, :plain, ["'" | current], statements)

  defp split_sql(<<"\"\"", rest::binary>>, :double_quote, current, statements),
    do: split_sql(rest, :double_quote, ["\"\"" | current], statements)

  defp split_sql(<<"\"", rest::binary>>, :double_quote, current, statements),
    do: split_sql(rest, :plain, ["\"" | current], statements)

  defp split_sql(<<"\n", rest::binary>>, :line_comment, current, statements),
    do: split_sql(rest, :plain, ["\n" | current], statements)

  defp split_sql(<<_character::utf8, rest::binary>>, :line_comment, current, statements),
    do: split_sql(rest, :line_comment, current, statements)

  defp split_sql(<<"*/", rest::binary>>, :block_comment, current, statements),
    do: split_sql(rest, :plain, [" " | current], statements)

  defp split_sql(<<_character::utf8, rest::binary>>, :block_comment, current, statements),
    do: split_sql(rest, :block_comment, current, statements)

  defp split_sql(input, {:dollar_quote, delimiter} = state, current, statements) do
    if String.starts_with?(input, delimiter) do
      rest = binary_part(input, byte_size(delimiter), byte_size(input) - byte_size(delimiter))
      split_sql(rest, :plain, [delimiter | current], statements)
    else
      <<character::utf8, rest::binary>> = input
      split_sql(rest, state, [<<character::utf8>> | current], statements)
    end
  end

  defp split_sql(<<character::utf8, rest::binary>>, state, current, statements),
    do: split_sql(rest, state, [<<character::utf8>> | current], statements)

  defp finish_statement(statements, current) do
    statement = current |> Enum.reverse() |> IO.iodata_to_binary() |> String.trim()
    if statement == "", do: statements, else: [statement | statements]
  end

  defp dollar_delimiter(input) do
    case Regex.run(~r/^\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/, input) do
      [delimiter] -> delimiter
      nil -> nil
    end
  end
end
