defmodule MdnsLite do
  @moduledoc """
  A simple implementation of an mDNS (multicast DNS (Domain Name Server)) server. 
  Rather than accessing a DNS server directly, mDNS
  is based on multicast UDP. Hosts/services listen on a well-known ip address/port. If
  a request arrives that the service can answer, it constructs the approriate DNS response.

  This module runs as a GenServer responsible for maintaining a set of mDNS servers. The intent
  is to have one server per network interface, e.g. "eth0", "lo", etc. Upon
  receiving an mDNS request, these servers respond with mDNS (DNS) records with
  host information for the host this module is running on. Also there will be
  SRV (service) DNS records about network services that are available from this device.
  SSH and FTP are examples of such services.

  Note: the mDNS servers can be run directly. This module serves as a convenience
  for apps that are dealing with multiple network interfaces.

  This module is initialized with host information and service descriptions.
  The descriptions will be used by the mDNS servers as a response to a matching service query.

  Please refer to the README for further information.

  This package can be tested with the linux utility dig:

  ``` dig @224.0.0.251 -p 5353 -t A petes-pt.local```

  The code borrows heavily from the https://hex.pm/packages/mdns package and
  https://github.com/shortishly/mdns.
  """
  require Logger
  use GenServer

  @mdns_config Application.get_env(:mdns_lite, :mdns_config)
  @mdns_services Application.get_env(:mdns_lite, :services)

  defmodule State do
    @moduledoc """
      A map of interface names to mdns GenServers (MdnsLite.Server).
      And some configuration values that will be used when constructing a DNS
      response packet.
    """
    defstruct ifname_server_map: %{}, mdns_config: %{}, mdns_services: %{}
  end

  @doc """
  Pro forma starting.
  """
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts) do
    opts = [@mdns_config, @mdns_services]

    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start an mDNS server for a network interface
  """
  @spec start_mdns_server(ifname: String.t()) :: term()
  def start_mdns_server(ifname) do
    GenServer.call(__MODULE__, {:start_mdns_server, ifname})
  end

  @doc """
  Stop the mDNS server for a network interface
  """
  @spec stop_mdns_server(ifname: String.t()) :: term()
  def stop_mdns_server(ifname) do
    GenServer.call(__MODULE__, {:stop_mdns_server, ifname})
  end

  # TODO REMOVE ME
  def get_state() do
    GenServer.call(__MODULE__, :get_state)
  end

  # TODO REMOVE
  def get_pid(ifname) do
    GenServer.call(__MODULE__, {:get_pid, ifname})
  end

  @doc false
  @impl true
  def init([mdns_config, mdns_services]) do
    {:ok, %State{ifname_server_map: %{}, mdns_config: mdns_config, mdns_services: mdns_services}}
  end

  @impl true
  def handle_call({:start_mdns_server, ifname}, _from, state) do
    with {:ok, server_pid} <-
           MdnsLite.Server.start({ifname, state.mdns_config, state.mdns_services}) do
      Logger.debug("Start mdns server: server_pid #{inspect(server_pid)}")
      new_ifname_server_map = Map.put(state.ifname_server_map, ifname, server_pid)
      {:reply, :ok, %State{state | ifname_server_map: new_ifname_server_map}}
    else
      {:error, reason} ->
        Logger.debug("Start mdns server: #{inspect(reason)}")
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:stop_mdns_server, ifname}, _from, state) do
    new_ifname_server_map =
      case Map.get(state.ifname_server_map, ifname, :not_here) do
        :not_here ->
          state.ifname_server_map

        pid ->
          MdnsLite.Server.stop_server(pid)
          Map.delete(state.ifname_server_map, ifname)
      end

    {:reply, :ok, %State{state | ifname_server_map: new_ifname_server_map}}
  end

  # TODO REMOVE ME
  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # TODO REMOVE ME
  @impl true
  def handle_call({:get_pid, ifname}, _from, state) do
    {:reply, Map.get(state.ifname_server_map, ifname), state}
  end

  ##############################################################################
  #   Private functions
  ##############################################################################
end