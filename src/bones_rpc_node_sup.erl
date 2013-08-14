%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :   18 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_node_sup).
-behaviour(supervisor).

-include("bones_rpc_internal.hrl").

%% API
-export([start_link/1, graceful_shutdown/1, add_pool/1, rm_pool/1, node_name/1, node_sup_name/1, node_connection_name/1, node_pool_name/1]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%%%===================================================================
%%% API functions
%%%===================================================================

start_link(Node=#node{}) ->
    SupName = node_sup_name(Node),
    supervisor:start_link({local, SupName}, ?MODULE, Node).

graceful_shutdown(Node=#node{}) ->
    catch rm_pool(Node),
    case bones_rpc_node:graceful_shutdown(Node) of
        ok ->
            ok;
        _ ->
            forced_shutdown
    end.

add_pool(Node=#node{name=Name, conn_t=ConnT}) ->
    PoolName = node_pool_name(Node),
    Conn = ConnT#conn{ref=undefined},
    PoolConfig = [
        {name, PoolName},
        {group, Name},
        {max_count, 5},
        {init_count, 2},
        {start_mfa, {bones_rpc_connection, start_link, [Conn]}}
    ],
    pooler:new_pool(PoolConfig).

rm_pool(Node=#node{}) ->
    PoolName = node_pool_name(Node),
    pooler:rm_pool(PoolName).

%% Child Names

node_name(#node{name=Name, address=#address{ip=IP, port=Port}}) ->
    node_name({Name, IP, Port});
node_name({Name, IP, Port}) ->
    list_to_atom(lists:flatten(io_lib:format("bones_rpc_~s_node_~s:~p", [Name, inet_parse:ntoa(IP), Port]))).

node_sup_name(Node) ->
    list_to_atom(atom_to_list(node_name(Node)) ++ "_sup").

node_connection_name(Node) ->
    list_to_atom(atom_to_list(node_name(Node)) ++ "_connection").

node_pool_name(Node) ->
    list_to_atom(atom_to_list(node_name(Node)) ++ "_pool").

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%% @private
init(Node=#node{conn_t=ConnT}) ->
    ConnName = node_connection_name(Node),
    Conn = ConnT#conn{ref=ConnName},
    NodeSpec = {bones_rpc_node,
        {bones_rpc_node, start_link, [Node]},
        transient, 5000, worker, [bones_rpc_node]},
    ConnSpec = {bones_rpc_connection,
        {bones_rpc_connection, start_link, [Conn]},
        transient, 5000, worker, [bones_rpc_connection]},
    %% five restarts in 60 seconds, then shutdown
    Restart = {rest_for_one, 5, 60},
    {ok, {Restart, [NodeSpec, ConnSpec]}}.
