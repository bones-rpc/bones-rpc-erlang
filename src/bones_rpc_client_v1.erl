%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :  02 Aug 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_client_v1).

-include("bones_rpc.hrl").

%% API
-export([new/3]).

%%%===================================================================
%%% API
%%%===================================================================

new(Host, Port, Options) ->
    Client = #bones_rpc_client_v1{},

    %% Debug Options
    Debug = get_value(debug, Options, Client#bones_rpc_client_v1.debug),
    %% Adapter Options
    Adapter = get_value(adapter, Options, Client#bones_rpc_client_v1.adapter),
    %% Reconnect Options
    Reconnect = get_value(reconnect, Options, Client#bones_rpc_client_v1.reconnect),
    ReconnectLimit = get_value(reconnect_limit, Options, Client#bones_rpc_client_v1.reconnect_limit),
    ReconnectMin = get_value(reconnect_min, Options, Client#bones_rpc_client_v1.reconnect_min),
    ReconnectMax = get_value(reconnect_max, Options, Client#bones_rpc_client_v1.reconnect_max),
    %% Session Options
    SessionModule = get_value(session_module, Options, Client#bones_rpc_client_v1.session_module),
    %% Transport Options
    Transport = get_value(transport, Options, Client#bones_rpc_client_v1.transport),
    TransportOpts = get_value(transport_opts, Options, Client#bones_rpc_client_v1.transport_opts),

    Client#bones_rpc_client_v1{host=Host, port=Port, debug=Debug,
        adapter=Adapter, reconnect=Reconnect, reconnect_limit=ReconnectLimit,
        reconnect_min=ReconnectMin, reconnect_max=ReconnectMax,
        session_module=SessionModule, transport=Transport, transport_opts=TransportOpts}.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

%% @doc Faster alternative to proplists:get_value/3.
get_value(Key, Opts, Default) ->
  case lists:keyfind(Key, 1, Opts) of
    {_, Value} -> Value;
    _ -> Default
  end.
