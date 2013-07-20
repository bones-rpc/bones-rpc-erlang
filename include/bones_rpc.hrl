%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :  18 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------

-record(bones_rpc_ext8_v1, {
    head = 0    :: integer(),
    data = <<>> :: binary()
}).

-define(BONES_RPC_REQUEST, 0).
-define(BONES_RPC_RESPONSE, 1).
-define(BONES_RPC_NOTIFY, 2).
