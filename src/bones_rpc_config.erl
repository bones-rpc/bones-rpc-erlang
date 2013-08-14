%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :   12 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_config).

-include("bones_rpc_internal.hrl").

%% API
-export([list_to_cluster/1, list_to_conn/1]).

%%%===================================================================
%%% API functions
%%%===================================================================

-spec list_to_cluster([{atom(), term()}]) -> #cluster{}.
list_to_cluster(C) ->
    #cluster{
        name   = req(name, C),
        seeds  = [bones_rpc_address:new(Host, Port) || {Host, Port} <- req(seeds, C)],
        conn_t = list_to_conn_t(C),
        node_t = list_to_node_t(C),

        debug = opt(debug, C, false),

        refresh_interval = opt(refresh_interval, C, 30000) % 30 seconds
    }.

list_to_conn(C) ->
    #conn{
        address = req(address, C),

        debug = opt(debug, C, false),

        transport      = opt(transport, C, ranch_tcp),
        transport_opts = opt(transport_opts, C, []),

        adapter = req(adapter, C),
        session = opt(session, C, bones_rpc_session),

        reconnect       = opt(reconnect, C, true),
        reconnect_limit = opt(reconnect_limit, C, infinity),
        reconnect_min   = opt(reconnect_min, C, 100),
        reconnect_max   = opt(reconnect_max, C, 5000)
    }.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

list_to_conn_t(C) ->
    #conn{
        name = req(name, C),

        debug = opt(debug, C, false),

        transport      = opt(transport, C, ranch_tcp),
        transport_opts = opt(transport_opts, C, []),

        adapter = req(adapter, C),
        session = opt(session, C, bones_rpc_session),

        reconnect       = opt(reconnect, C, true),
        reconnect_limit = opt(reconnect_limit, C, infinity),
        reconnect_min   = opt(reconnect_min, C, 100),
        reconnect_max   = opt(reconnect_max, C, 5000)
    }.

list_to_node_t(C) ->
    #node{
        name = req(name, C),
        debug = opt(debug, C, false)
    }.

%% @doc Faster alternative to proplists:get_value/3.
opt(Key, Opts, Default) ->
  case lists:keyfind(Key, 1, Opts) of
    {_, Value} -> Value;
    _ -> Default
  end.

%% Return `Value' for `Key' in proplist `P' or crashes with an
%% informative message if no value is found.
req(Key, P) ->
    case lists:keyfind(Key, 1, P) of
        false ->
            error({missing_required_config, Key, P});
        {Key, Value} ->
            Value
    end.
