%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :  05 Aug 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_cluster).
-behaviour(gen_server).

-include("bones_rpc.hrl").
-include("bones_rpc_internal.hrl").

%% API
-export([start_link/1, ring_update/3, graceful_shutdown/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%%%===================================================================
%%% API functions
%%%===================================================================

start_link(Cluster=#cluster{ref=ClusterRef}) ->
    gen_server:start_link({local, ClusterRef}, ?MODULE, Cluster, []).

ring_update(#cluster{ref=ClusterRef}, Conn, Ring) ->
    ring_update(ClusterRef, Conn, Ring);
ring_update(ClusterRef, Conn, Ring) ->
    gen_server:cast(ClusterRef, {ring_update, Conn, Ring}).

graceful_shutdown(ClusterRef) ->
    gen_server:call(ClusterRef, graceful_shutdown).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init(Cluster=#cluster{}) ->
    ok = bones_rpc_cluster_event:add_handler(bones_rpc_cluster_event_handler, Cluster),
    RefreshRef = erlang:start_timer(0, self(), '$bones_rpc_refresh'),
    {ok, Cluster#cluster{refresh_ref=RefreshRef}}.

handle_call(graceful_shutdown, _From, Cluster=#cluster{name=Name, ref=Table}) ->
    ok = remove_nodes(Table, Name),
    {stop, normal, ok, Cluster};
handle_call(_Request, _From, Cluster) ->
    {reply, ok, Cluster}.

handle_cast({ring_update, _Conn, #bones_rpc_ring_v1{members=Members}}, Cluster=#cluster{ref=Table}) ->
    ok = flush_seeds(Table),
    ok = sync_seeds(Table, Members),
    {noreply, Cluster};
handle_cast(_Request, State) ->
    {noreply, State}.

handle_info({timeout, RefreshRef, '$bones_rpc_refresh'}, Cluster=#cluster{refresh_ref=RefreshRef}) ->
    {ok, Cluster2} = handle_refresh(Cluster#cluster{refresh_ref=undefined}),
    {noreply, Cluster2};
handle_info(_Info, Cluster) ->
    {noreply, Cluster}.

terminate(normal, Cluster) ->
    bones_rpc_cluster_event:cluster_stop(Cluster, normal),
    ok;
terminate(_Reason, _Cluster) ->
    ok.

code_change(_OldVsn, Cluster, _Extra) ->
    {ok, Cluster}.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

%% @private
handle_refresh(Cluster=#cluster{ref=Table, refresh_interval=RefreshInterval}) ->
    ok = resolve_seeds(Table),
    ok = nodes_from_seeds(Table, Cluster),
    ok = refresh_nodes(Table),
    RefreshRef = erlang:start_timer(RefreshInterval, self(), '$bones_rpc_refresh'),
    {ok, Cluster#cluster{refresh_ref=RefreshRef}}.

%% @private
resolve_seeds(Table) ->
    case ets:match_object(Table, {{seed, '_', '_'}, undefined}) of
        [] ->
            ok;
        Seeds ->
            _ = [resolve_seed(Table, Seed) || Seed <- Seeds],
            ok
    end.

%% @private
resolve_seed(Table, {{seed, Host, Port}, undefined}) ->
    Address = bones_rpc_address:new(Host, Port),
    case bones_rpc_address:resolve(Address) of
        {ok, #address{host=Host, port=Port, ip=IP}} ->
            true = ets:insert(Table, {{seed, Host, Port}, IP}),
            ok;
        {error, _Reason} ->
            ok
    end.

%% @private
nodes_from_seeds(Table, Cluster) ->
    case ets:select(Table, [{{{seed, '$1', '$2'}, '$3'}, [{'=/=', '$3', undefined}], [{#address{host='$1', port='$2', ip='$3'}}]}]) of
        [] ->
            ok;
        Addresses ->
            _ = [node_from_seed(Table, Address, Cluster) || Address <- Addresses],
            ok
    end.

%% @private
node_from_seed(Table, Address=#address{ip=IP, port=Port}, #cluster{conn_t=ConnT, node_t=NodeT}) ->
    Node = NodeT#node{address=Address},
    NodeName = bones_rpc_node_sup:node_name(Node),
    ConnName = bones_rpc_node_sup:node_connection_name(Node),
    ConnT2 = ConnT#conn{ref=ConnName, address=Address, node=NodeName},
    Node2 = Node#node{ref=NodeName, conn_t=ConnT2},
    case bones_rpc_cluster_sup:add_node(Node2) of
        {ok, SupPid} ->
            true = ets:insert(Table, {{node, IP, Port}, NodeName, SupPid}),
            ok;
        {error, {already_started, SupPid}} ->
            true = ets:insert(Table, {{node, IP, Port}, NodeName, SupPid}),
            ok;
        _ ->
            true = ets:delete(Table, {node, IP, Port}),
            ok
    end.

%% @private
refresh_nodes(Table) ->
    case ets:match(Table, {{node, '_', '_'}, '$1', '_'}) of
        [] ->
            ok;
        Nodes ->
            _ = [refresh_node(Node) || [Node] <- Nodes],
            ok
    end.

%% @private
refresh_node(Node) ->
    case bones_rpc_node:synchronize(Node) of
        true ->
            ok;
        false ->
            ok;
        {error, timeout} ->
            ok
    end.

%% @private
flush_seeds(Table) ->
    true = ets:match_delete(Table, {{seed, '_', '_'}, '_'}),
    ok.

%% @private
sync_seeds(_Table, []) ->
    ok;
sync_seeds(Table, [{Name, {IP, Port}} | Seeds]) ->
    Seed = {{seed, Name, Port}, IP},
    true = ets:insert(Table, Seed),
    sync_seeds(Table, Seeds).

%% @private
remove_nodes(Table, Name) ->
    case ets:match(Table, {{node, '$1', '$2'}, '$3', '_'}) of
        [] ->
            ok;
        Nodes ->
            _ = [begin
                Node = #node{
                    name = Name,
                    ref = NodeRef,
                    address = #address{
                        ip = IP,
                        port = Port
                    }
                },
                remove_node(Node)
            end || [IP, Port, NodeRef] <- Nodes],
            ok
    end.

%% @private
remove_node(Node) ->
    ok = bones_rpc_cluster_sup:rm_node(Node),
    ok.
