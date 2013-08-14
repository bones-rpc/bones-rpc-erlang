%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :   18 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_sup).
-behaviour(supervisor).

-include("bones_rpc_internal.hrl").

%% API
-export([start_link/0, new_cluster/1, rm_cluster/1, delete_cluster/1]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%%%===================================================================
%%% API functions
%%%===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @doc Create a new cluster from proplist cluster config `ClusterConfig'.
%% The public API for this functionality is {@link bones_rpc:new_cluster/1}.
new_cluster(ClusterConfig) ->
    NewCluster = bones_rpc_config:list_to_cluster(ClusterConfig),
    Spec = cluster_sup_spec(NewCluster),
    supervisor:start_child(?MODULE, Spec).

rm_cluster(Cluster) ->
    case bones_rpc_cluster_sup:graceful_shutdown(Cluster) of
        ok ->
            ok;
        forced_shutdown ->
            delete_cluster(Cluster)
    end.

delete_cluster(#cluster{name=Name}) ->
    delete_cluster(Name);
delete_cluster(Name) ->
    SupName = cluster_sup_name(Name),
    case supervisor:terminate_child(?MODULE, SupName) of
        {error, not_found} ->
            ok;
        ok ->
            supervisor:delete_child(?MODULE, SupName);
        Error ->
            Error
    end.

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

init([]) ->
    bones_rpc_ring = ets:new(bones_rpc_ring, [ordered_set, public, named_table]),
    RingEmitter = {bones_rpc_ring_emitter,
        {gen_event, start_link, [{local, bones_rpc_ring_emitter}]},
        permanent, 5000, worker, [gen_event]},
    %% five restarts in 10 seconds, then shutdown
    Restart = {one_for_all, 5, 10},
    {ok, {Restart, [RingEmitter, ?CHILD(bones_rpc_ring, worker)]}}.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

%% @private
cluster_sup_spec(Cluster=#cluster{name=Name}) ->
    SupName = cluster_sup_name(Name),
    {SupName,
        {bones_rpc_cluster_sup, start_link, [Cluster]},
        transient, 5000, supervisor, [bones_rpc_cluster_sup]}.

%% @private
cluster_sup_name(Name) ->
    list_to_atom("bones_rpc_" ++ atom_to_list(Name) ++ "_cluster_sup").
