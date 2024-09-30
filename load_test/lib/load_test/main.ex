defmodule LoadTest.Main do
  use GenServer
  require Logger

  defmodule InjectionContext do
    defstruct [
      :sse_timeout,
      :sse_url,
      :sse_jwt_issuer,
      :sse_jwt_secret,
      :sse_jwt_audience,
      :sse_jwt_expiration,
      :sse_user_agent,
      :publish_url,
      :publish_timeout,
      :publish_jwt_issuer,
      :publish_jwt_secret,
      :publish_jwt_audience,
      :delay_between_messages_min,
      :delay_between_messages_max,
      :number_of_messages_min,
      :number_of_messages_max
    ]
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(start_from) do
    {:ok, nb_user} = Application.fetch_env(:load_test, :nb_user)

    {:ok, sse_timeout} = Application.fetch_env(:load_test, :sse_timeout)
    {:ok, sse_url} = Application.fetch_env(:load_test, :sse_url)
    {:ok, sse_user_agent} = Application.fetch_env(:load_test, :sse_user_agent)
    {:ok, sse_jwt_issuer} = Application.fetch_env(:load_test, :sse_jwt_issuer)
    {:ok, sse_jwt_secret} = Application.fetch_env(:load_test, :sse_jwt_secret)
    {:ok, sse_jwt_audience} = Application.fetch_env(:load_test, :sse_jwt_audience)
    {:ok, sse_jwt_expiration} = Application.fetch_env(:load_test, :sse_jwt_expiration)

    {:ok, publish_url} = Application.fetch_env(:load_test, :publish_url)
    {:ok, publish_timeout} = Application.fetch_env(:load_test, :publish_timeout)
    {:ok, publish_jwt_issuer} = Application.fetch_env(:load_test, :publish_jwt_issuer)
    {:ok, publish_jwt_secret} = Application.fetch_env(:load_test, :publish_jwt_secret)
    {:ok, publish_jwt_audience} = Application.fetch_env(:load_test, :publish_jwt_audience)

    {:ok, delay_between_messages_min} =
      Application.fetch_env(:load_test, :delay_between_messages_min)

    {:ok, delay_between_messages_max} =
      Application.fetch_env(:load_test, :delay_between_messages_max)

    {:ok, number_of_messages_min} = Application.fetch_env(:load_test, :number_of_messages_min)
    {:ok, number_of_messages_max} = Application.fetch_env(:load_test, :number_of_messages_max)

    {:ok, initial_delay_max} = Application.fetch_env(:load_test, :initial_delay_max)

    context = %InjectionContext{
      sse_timeout: sse_timeout,
      sse_url: sse_url,
      sse_user_agent: sse_user_agent,
      sse_jwt_issuer: sse_jwt_issuer,
      sse_jwt_secret: JOSE.JWK.from_oct(sse_jwt_secret),
      sse_jwt_audience: sse_jwt_audience,
      sse_jwt_expiration: sse_jwt_expiration,
      publish_url: publish_url,
      publish_timeout: publish_timeout,
      publish_jwt_issuer: publish_jwt_issuer,
      publish_jwt_secret: JOSE.JWK.from_oct(publish_jwt_secret),
      publish_jwt_audience: publish_jwt_audience,
      delay_between_messages_min: delay_between_messages_min,
      delay_between_messages_max: delay_between_messages_max,
      number_of_messages_min: number_of_messages_min,
      number_of_messages_max: number_of_messages_max
    }

    Logger.warning("SSE BASE URL: #{sse_url}")
    Logger.warning("PUBLISH BASE URL: #{publish_url}")
    Logger.warning("Starting load test with #{nb_user} users")

    Enum.map(1..nb_user, fn _ ->
      Task.Supervisor.async(LoadTest.TaskSupervisor, fn ->
        delay = :rand.uniform(initial_delay_max)

        receive do
        after
          delay -> :ok
        end

        run_virtual_user(context)
      end)
    end)

    {:ok, start_from}
  end

  defp run_virtual_user(context) do
    number_of_messages =
      :rand.uniform(context.number_of_messages_max - context.number_of_messages_min) +
        context.number_of_messages_min

    messages = Enum.map(1..number_of_messages, fn _ -> UUID.uuid4() end)
    topic = "topic_#{UUID.uuid4()}"
    user_name = "user_#{UUID.uuid4()}"

    sse_task =
      Task.Supervisor.async(LoadTest.TaskSupervisor, fn ->
        run_sse_user(context, user_name, topic, messages)
      end)

    Task.await(sse_task, :infinity)

    run_virtual_user(context)
  end

  def start_publisher(context, user_name, topic, messages) do
    GenServer.cast(__MODULE__, {:start_publisher, context, user_name, topic, messages})
  end

  @impl true
  def handle_cast({:start_publisher, context, user_name, topic, messages}, state) do
    Task.Supervisor.start_child(LoadTest.TaskSupervisor, fn ->
      run_publisher(context, user_name, topic, messages)
    end)

    {:noreply, state}
  end

  defp run_publisher(context, user_name, topic, messages) do
    try do
      LoadTest.User.Publisher.start(
        context,
        user_name,
        topic,
        messages
      )

      :ok
    rescue
      x ->
        Logger.error("publisher_#{user_name}: Error #{inspect(x)}")
        :error
    end
  end

  defp run_sse_user(context, user_name, topic, messages) do
    Stats.inc_user_running()

    try do
      SseUser.run(context, user_name, topic, messages)

      Stats.dec_user_running()
      Stats.inc_user_ok()
      :ok
    rescue
      x ->
        Logger.error("#{user_name}: Error #{inspect(x)}")
        Stats.dec_user_running()
        Stats.inc_user_error()
        :error
    end
  end

  @impl true
  def handle_info({_, :ok}, state) do
    {:noreply, state}
  end
end
