-module(adapter_SUITE).

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
    synchronize/1,
    request/1,
    notify/1,
    notify_json/1
]).

all() ->
    [
        {group, bones_erlang},
        {group, bones_json},
        {group, bones_msgpack}
    ].

groups() ->
    Tests = [
        synchronize,
        request
    ],
    [
        {bones_erlang, [parallel], Tests ++ [notify]},
        {bones_json, [parallel], Tests ++ [notify_json]}, %% json can't handle straight binary
        {bones_msgpack, [parallel], Tests ++ [notify]}
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
    Adapter = adapter_for_group(Name),
    ct:log("connecting to ~s server with ~s adapter...", [ServerName, Adapter]),
    {ok, Client} = adapter_server:connect(ServerName, [{adapter, Adapter}]),
    ct:log("connected."),
    [{adapter, Adapter}, {client, Client}, {server, ServerName} | Config].

end_per_group(_Name, Config) ->
    ct:log("disconnecting client..."),
    Client = ?config(client, Config),
    ok = bones_rpc:disconnect(Client),
    ct:log("disconnected."),
    ServerName = ?config(server, Config),
    ct:log("stopping ~s server...", [ServerName]),
    adapter_server:stop_listener(ServerName),
    ct:log("stopped."),
    ok.

%%====================================================================
%% Tests
%%====================================================================

synchronize(Config) ->
    Client = ?config(client, Config),
    % Synchronous
    {ok, {acknowledge, _, true}, _} = bones_rpc_client:sync_send(Client, synchronize),
    % Asynchronous
    {ok, Future={synack, N}} = bones_rpc_client:send(Client, synchronize),
    {ok, {acknowledge, N, true}, _} = bones_rpc_client:join(Client, Future),
    ok.

request(Config) ->
    Client = ?config(client, Config),
    % Synchronous
    {ok, {response, _, nil, 10}, _} = bones_rpc_client:sync_send(Client, {request, <<"sum">>, [1,2,3,4]}),
    {ok, {response, _, [<<"failed">>], nil}, _} = bones_rpc_client:sync_send(Client, {request, <<"fail">>, [<<"failed">>]}),
    % Asynchronous
    {ok, Future0={request, R0}} = bones_rpc_client:send(Client, {request, <<"sum">>, [100,200]}),
    {ok, {response, R0, nil, 300}, _} = bones_rpc_client:join(Client, Future0),
    {ok, Future1={request, R1}} = bones_rpc_client:send(Client, {request, <<"fail">>, [<<"failed">>]}),
    {ok, {response, R1, [<<"failed">>], nil}, _} = bones_rpc_client:join(Client, Future1),
    ok.

notify(Config) ->
    Client = ?config(client, Config),
    Self = erlang:term_to_binary(self()),
    % Synchronous (send & sync_send are the same)
    ok = bones_rpc_client:send(Client, {notify, <<"ping">>, [Self, 1]}),
    ok = receive {pong, 1} -> ok after 1000 -> timeout end,
    ok = bones_rpc_client:sync_send(Client, {notify, <<"ping">>, [Self, 2]}),
    ok = receive {pong, 2} -> ok after 1000 -> timeout end,
    % Asynchronous
    ok = bones_rpc_client:cast(Client, {notify, <<"ping">>, [Self, 3]}),
    ok = receive {pong, 3} -> ok after 1000 -> timeout end,
    ok.

notify_json(Config) ->
    Client = ?config(client, Config),
    Self = erlang:binary_to_list(erlang:term_to_binary(self())),
    % Synchronous (send & sync_send are the same)
    ok = bones_rpc_client:send(Client, {notify, <<"ping">>, [Self, 1]}),
    ok = receive {pong, 1} -> ok after 1000 -> timeout end,
    ok = bones_rpc_client:sync_send(Client, {notify, <<"ping">>, [Self, 2]}),
    ok = receive {pong, 2} -> ok after 1000 -> timeout end,
    % Asynchronous
    ok = bones_rpc_client:cast(Client, {notify, <<"ping">>, [Self, 3]}),
    ok = receive {pong, 3} -> ok after 1000 -> timeout end,
    ok.

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

%% @private
adapter_for_group(A) when A =:= bones_erlang orelse A =:= bones_json orelse A =:= bones_msgpack ->
    A.

%% @private
server_for_group(Adapter) ->
    list_to_atom("adapter_server_" ++ atom_to_list(Adapter)).
