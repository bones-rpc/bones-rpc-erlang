%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :  05 Aug 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------

-record(address, {
    host = undefined :: undefined | inet:hostname() | inet:ip_address(),
    port = undefined :: undefined | inet:port_number(),
    ip   = undefined :: undefined | inet:ip_address()
}).

-record(conn, {
    name    = undefined :: undefined | atom(),
    ref     = undefined :: undefined | atom(),
    node    = undefined :: undefined | atom(),
    cluster = undefined :: undefined | atom(),
    emitter = undefined :: undefined | atom(),

    debug = false :: boolean(),

    %% Address
    address = undefined :: undefined | #address{},

    %% Transport
    transport      = undefined :: undefined | module(),
    transport_opts = undefined :: undefined | any(),
    messages       = undefined :: undefined | {atom(), atom(), atom()},

    %% Socket
    socket = undefined :: undefined | inet:socket(),
    buffer = <<>>      :: binary(),

    %% Adapter and Session State
    adapter = undefined :: undefined | module() | {module(), any()},
    session = undefined :: undefined | module() | {module(), any()},

    %% Counter State
    synack_id = 0 :: integer(),

    %% Reconnect Options
    reconnect       = true     :: boolean(),
    reconnect_limit = infinity :: infinity | non_neg_integer(),
    reconnect_min   = 100      :: timeout(),
    reconnect_max   = 5000     :: timeout(),

    %% Reconnect State
    reconnect_count = 0 :: non_neg_integer(),
    reconnect_wait  = 0 :: timeout()
}).

-record(node, {
    name     = undefined :: undefined | atom(),
    ref      = undefined :: undefined | atom(),
    cluster  = undefined :: undefined | atom(),
    emitter  = undefined :: undefined | atom(),
    address  = undefined :: undefined | #address{},
    conn_t   = undefined :: undefined | #conn{},

    debug = false :: boolean(),

    pid     = undefined :: undefined | pid(),
    monitor = undefined :: undefined | reference(),
    status  = down      :: down | up
}).

-record(cluster, {
    name    = undefined :: undefined | atom(),
    ref     = undefined :: undefined | atom(),
    emitter = undefined :: undefined | atom(),
    sup     = undefined :: undefined | atom(),
    seeds   = []        :: [#address{}],

    debug = false :: boolean(),

    node_t = undefined :: undefined | #node{},
    conn_t = undefined :: undefined | #conn{},

    refresh_interval = undefined :: undefined | integer(),
    refresh_ref      = undefined :: undefined | reference()
}).
