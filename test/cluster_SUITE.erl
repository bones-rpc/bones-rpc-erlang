-module(cluster_SUITE).

-include_lib("common_test/include/ct.hrl").

%% ct.
-export([all/0]).
-export([groups/0]).
-export([init_per_suite/1]).
-export([end_per_suite/1]).
-export([init_per_group/2]).
-export([end_per_group/2]).

%% Tests.
-export([
    smoke/1
]).

all() ->
    [
        {group, test_cluster}
    ].

groups() ->
    Tests = [
        smoke
    ],
    [
        {test_cluster, [parallel], Tests}
    ].

init_per_suite(Config) ->
    application:start(sasl),
    application:start(crypto),
    application:start(ranch),
    application:start(bones_rpc),
    Config.

end_per_suite(_Config) ->
    application:stop(bones_rpc),
    application:stop(ranch),
    application:stop(crypto),
    application:stop(sasl),
    ok.

init_per_group(Name, Config) ->
    ServerName = server_for_group(Name),
    ct:log("starting ~s server...", [ServerName]),
    {ok, _Pid} = adapter_server:start_listener(ServerName),
    ct:log("started."),
    Adapter = bones_msgpack,
    ct:log("connecting to ~s server with ~s adapter...", [ServerName, Adapter]),
    ClusterConfig = [
        {name, Name},
        {adapter, Adapter}
    ],
    {ok, _} = adapter_server:cluster(ServerName, ClusterConfig),
    ct:log("connected."),
    [{adapter, Adapter}, {cluster, Name}, {server, ServerName} | Config].

end_per_group(_Name, Config) ->
    ct:log("disconnecting cluster..."),
    Cluster = ?config(cluster, Config),
    ok = bones_rpc:rm_cluster(Cluster),
    ct:log("disconnected."),
    ServerName = ?config(server, Config),
    ct:log("stopping ~s server...", [ServerName]),
    adapter_server:stop_listener(ServerName),
    ct:log("stopped."),
    ok.

%%====================================================================
%% Tests
%%====================================================================

smoke(Config) ->
    Cluster = ?config(cluster, Config),
    Client = pooler:take_group_member(Cluster),
    % Synchronous
    {ok, {acknowledge, _, true}, _} = bones_rpc_client:sync_send(Client, synchronize),
    % Asynchronous
    {ok, Future={synack, N}} = bones_rpc_client:send(Client, synchronize),
    {ok, {acknowledge, N, true}, _} = bones_rpc_client:join(Client, Future),
    pooler:return_group_member(Cluster, Client),
    ok.

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

%% @private
server_for_group(Group) ->
    list_to_atom(atom_to_list(Group) ++ "_server").
