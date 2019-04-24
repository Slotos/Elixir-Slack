defmodule Slack.State do
  @moduledoc "Slack state"
  @behaviour Access

  def fetch(client, key)
  defdelegate fetch(client, key), to: Map

  def get(client, key, default)
  defdelegate get(client, key, default), to: Map

  def get_and_update(client, key, function)
  defdelegate get_and_update(client, key, function), to: Map

  def pop(client, key)
  defdelegate pop(client, key), to: Map

  defstruct process: nil,
    client: nil,
    token: nil,
    me: nil,
    team: %{},
    bots: %{},
    channels: %{},
    groups: %{},
    users: %{},
    ims: %{}

  defp put_at(state = %__MODULE__{}, path, new_value) when is_list(path) do
    put_in(state, Enum.map(path, fn key -> Access.key(key, %{}) end), new_value)
  end

  defp update_at(state = %__MODULE__{}, path, updater) when is_function(updater) and is_list(path) do
    update_in(state, Enum.map(path, fn key -> Access.key(key, %{}) end), updater)
  end

  @doc """
  Pattern matches against messages and returns updated Slack state.
  """
  @spec update(Map, Map) :: {Symbol, Map}
  def update(%{type: "channel_created", channel: channel}, slack) do
    put_at(slack, [:channels, channel.id], channel)
  end

  def update(%{type: "channel_joined", channel: channel}, slack) do
    slack
    |> put_at([:channels, channel.id, :members], channel.members)
    |> put_at([:channels, channel.id, :is_member], true)
  end

  def update(%{type: "group_joined", channel: channel}, slack) do
    put_at(slack, [:groups, channel.id], channel)
  end

  def update(%{type: "message", subtype: "channel_join", channel: channel, user: user}, slack) do
    update_at(
      slack,
      [:channels, channel],
      fn channel ->
        if is_list(channel[:members]) do
          put_in(channel, [:members], [user| channel[:members]] |> Enum.uniq)
        else
          put_in(channel, [:members], [user])
        end
      end
    )
  end

  def update(%{type: "message", subtype: "group_join", channel: channel, user: user}, slack) do
    update_at(
      slack,
      [:groups, channel],
      fn channel ->
        if is_list(channel[:members]) do
          put_in(channel, [:members], [user| channel[:members]] |> Enum.uniq)
        else
          put_in(channel, [:members], [user])
        end
      end
    )
  end

  def update(
        %{type: "message", subtype: "channel_topic", channel: channel, user: user, topic: topic},
        slack
      ) do
    put_at(slack, [:channels, channel, :topic], %{
      creator: user,
      last_set: System.system_time(:seconds),
      value: topic
    })
  end

  def update(
        %{type: "message", subtype: "group_topic", channel: channel, user: user, topic: topic},
        slack
      ) do
    put_at(slack, [:groups, channel, :topic], %{
      creator: user,
      last_set: System.system_time(:seconds),
      value: topic
    })
  end

  def update(%{type: "channel_left", channel: channel_id}, slack) do
    put_at(slack, [:channels, channel_id, :is_member], false)
  end

  def update(%{type: "group_left", channel: channel}, slack) do
    update_at(slack, [:groups], &Map.delete(&1, channel))
  end

  Enum.map(["channel", "group"], fn type ->
    plural_atom = String.to_atom(type <> "s")

    def update(%{type: unquote(type <> "_rename"), channel: channel}, slack) do
      put_at(slack, [unquote(plural_atom), channel.id, :name], channel.name)
    end

    def update(%{type: unquote(type <> "_archive"), channel: channel}, slack) do
      put_at(slack, [unquote(plural_atom), channel, :is_archived], true)
    end

    def update(%{type: unquote(type <> "_unarchive"), channel: channel}, slack) do
      put_at(slack, [unquote(plural_atom), channel, :is_archived], false)
    end

    def update(
          %{type: "message", subtype: unquote(type <> "_leave"), channel: channel, user: user},
          slack
        ) do
          update_at(
            slack,
            [unquote(plural_atom), channel],
            fn channel ->
              if is_list(channel[:members]) do
                put_in(channel, [:members], channel[:members] -- [user])
              else
                put_in(channel, [:members], [])
              end
            end
          )
    end
  end)

  def update(%{type: "team_rename", name: name}, slack) do
    put_at(slack, [:team, :name], name)
  end

  def update(%{type: "presence_change", user: user, presence: presence}, slack) do
    put_at(slack, [:users, user, :presence], presence)
  end

  def update(%{type: "presence_change", users: users, presence: presence}, slack) do
    Enum.reduce(users, slack, fn user, acc ->
      put_at(acc, [:users, user, :presence], presence)
    end)
  end

  def update(%{type: "team_join", user: user}, slack) do
    put_at(slack, [:users, user.id], user)
  end

  def update(%{type: "user_change", user: user}, slack) do
    update_at(slack, [:users, user.id], &Map.merge(&1, user))
  end

  Enum.map(["bot_added", "bot_changed"], fn type ->
    def update(%{type: unquote(type), bot: bot}, slack) do
      put_at(slack, [:bots, bot.id], bot)
    end
  end)

  def update(%{type: "im_created", channel: channel}, slack) do
    put_at(slack, [:ims, channel.id], channel)
  end

  def update(%{type: _type}, slack) do
    slack
  end
end
