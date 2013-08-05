%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :  18 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------

-define(BONES_RPC_EXT_SYNCHRONIZE, 0).
-define(BONES_RPC_EXT_ACKNOWLEDGE, 1).

-define(BONES_RPC_REQUEST, 0).
-define(BONES_RPC_RESPONSE, 1).
-define(BONES_RPC_NOTIFY, 2).

-record(bones_rpc_ext_v1, {
    head = undefined :: undefined | integer(),
    data = undefined :: undefined | binary()
}).

-record(bones_rpc_client_v1, {
    host = undefined :: undefined | inet:ip_address() | inet:hostname(),
    port = undefined :: undefined | inet:port_number(),

    %% Debug Options
    debug = false :: boolean(),

    %% Adapter Options
    adapter = undefined :: undefined | module(),

    %% Reconnect Options
    reconnect       = true     :: boolean(),
    reconnect_limit = infinity :: infinity | non_neg_integer(),
    reconnect_min   = 100      :: timeout(),
    reconnect_max   = 5000     :: timeout(),

    %% Session Options
    session_module = bones_rpc_session :: module(),

    %% Transport Options
    transport      = ranch_tcp :: module(),
    transport_opts = []        :: [proplists:property()]
}).
