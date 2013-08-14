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
-define(BONES_RPC_EXT_RING, 2).

-define(BONES_RPC_REQUEST, 0).
-define(BONES_RPC_RESPONSE, 1).
-define(BONES_RPC_NOTIFY, 2).

-record(bones_rpc_ext_v1, {
    head = undefined :: undefined | integer(),
    data = undefined :: undefined | binary()
}).

-record(bones_rpc_client_v1, {
    host           = undefined :: undefined | inet:ip_address() | inet:hostname(),
    port           = undefined :: undefined | inet:port_number(),
    ip             = undefined :: undefined | inet:ip_address(),
    adapter        = undefined :: undefined | module(),
    transport      = undefined :: undefined | module(),
    transport_opts = undefined :: undefined | module()
}).

-record(bones_rpc_ring_v1, {
    nodename    = undefined :: undefined | atom(),
    clustername = undefined :: undefined | atom(),
    cookie      = undefined :: undefined | atom(),
    ip          = undefined :: undefined | inet:ip_address(),
    port        = undefined :: undefined | inet:port_number(),
    members     = undefined :: undefined | [{atom(), {inet:ip_address(), inet:port_number()}}]
}).
