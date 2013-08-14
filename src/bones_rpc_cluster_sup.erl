%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :   18 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_cluster_sup).
-behaviour(supervisor).

-include("bones_rpc_internal.hrl").

%% API
-export([start_link/1, cluster_name/1, cluster_sup_name/1, cluster_emitter_name/1,
         add_node/1, rm_node/1, delete_node/1, graceful_shutdown/1]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%%%===================================================================
%%% API functions
%%%===================================================================

start_link(Cluster=#cluster{name=Name}) ->
    SupName = cluster_sup_name(Name),
    supervisor:start_link({local, SupName}, ?MODULE, Cluster#cluster{sup=SupName}).

cluster_name(#cluster{name=Name}) ->
    cluster_name(Name);
cluster_name(Name) ->
    list_to_atom("bones_rpc_" ++ atom_to_list(Name) ++ "_cluster").

cluster_sup_name(Cluster) ->
    list_to_atom(atom_to_list(cluster_name(Cluster)) ++ "_sup").

cluster_emitter_name(Cluster) ->
    list_to_atom(atom_to_list(cluster_name(Cluster)) ++ "_emitter").

add_node(Node=#node{name=Name}) ->
    SupName = cluster_sup_name(Name),
    NodeSupName = bones_rpc_node_sup:node_sup_name(Node),
    NodeS = {NodeSupName,
        {bones_rpc_node_sup, start_link, [Node]},
        transient, 5000, supervisor, [bones_rpc_node_sup]},
    supervisor:start_child(SupName, NodeS).

rm_node(Node) ->
    case bones_rpc_node_sup:graceful_shutdown(Node) of
        ok ->
            ok;
        forced_shutdown ->
            delete_node(Node)
    end.

delete_node(Node=#node{name=Name}) ->
    SupName = cluster_sup_name(Name),
    NodeSupName = bones_rpc_node_sup:node_sup_name(Node),
    case supervisor:terminate_child(SupName, NodeSupName) of
        {error, not_found} ->
            ok;
        ok ->
            supervisor:delete_child(SupName, NodeSupName);
        Error ->
            Error
    end.

graceful_shutdown(Name) ->
    ClusterName = cluster_name(Name),
    case catch bones_rpc_cluster:graceful_shutdown(ClusterName) of
        ok ->
            ok;
        _ ->
            forced_shutdown
    end.

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%% @private
init(Cluster=#cluster{conn_t=ConnT, node_t=NodeT, seeds=Seeds}) ->
    ClusterName = cluster_name(Cluster),
    ClusterName = ets:new(ClusterName, [ordered_set, public, named_table]),
    [begin
        true = ets:insert(ClusterName, {{seed, Host, Port}, IP})
    end || #address{host=Host, port=Port, ip=IP} <- Seeds],
    Emitter = cluster_emitter_name(Cluster),
    ConnT2 = ConnT#conn{emitter=Emitter, cluster=ClusterName},
    NodeT2 = NodeT#node{emitter=Emitter, cluster=ClusterName},
    Cluster2 = Cluster#cluster{ref=ClusterName, emitter=Emitter, conn_t=ConnT2, node_t=NodeT2},
    ClusterSpec = {bones_rpc_cluster,
        {bones_rpc_cluster, start_link, [Cluster2]},
        transient, 5000, worker, [bones_rpc_cluster]},
    EmitterSpec = {bones_rpc_cluster_emitter,
        {gen_event, start_link, [{local, Emitter}]},
        transient, brutal_kill, worker, [gen_event]},
    %% five restarts in 60 seconds, then shutdown
    Restart = {one_for_all, 5, 60},
    {ok, {Restart, [EmitterSpec, ClusterSpec]}}.
