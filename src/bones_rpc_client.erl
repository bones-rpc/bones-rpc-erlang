%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :  07 Aug 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_client).

-include("bones_rpc.hrl").
-include("bones_rpc_internal.hrl").

%% API
-export([cast/2, send/2, send/3, join/2, join/3, sync_send/2, sync_send/3, shutdown/1]).

%% Internal API
-export([conn_to_client/1]).

%%%===================================================================
%%% API
%%%===================================================================

cast(Pid, Message) ->
    gen_fsm:send_event(Pid, {cast, Message}).

send(Pid, Message) ->
    gen_fsm:sync_send_event(Pid, {send, Message}).

send(Pid, Message, Timeout) ->
    gen_fsm:sync_send_event(Pid, {send, Message}, Timeout).

join(Pid, FutureKey) ->
    gen_fsm:sync_send_event(Pid, {join, FutureKey}).

join(Pid, FutureKey, Timeout) ->
    gen_fsm:sync_send_event(Pid, {join, FutureKey}, Timeout).

sync_send(Pid, Message) ->
    gen_fsm:sync_send_event(Pid, {sync_send, Message}).

sync_send(Pid, Message, Timeout) ->
    gen_fsm:sync_send_event(Pid, {sync_send, Message}, Timeout).

shutdown(Pid) ->
    gen_fsm:send_all_state_event(Pid, shutdown).

%% @private
conn_to_client(#conn{address=#address{host=Host, port=Port, ip=IP},
        adapter=Adapter, transport=Transport, transport_opts=TransportOpts}) ->
    #bones_rpc_client_v1{
        host = Host,
        port = Port,
        ip   = IP,
        adapter        = Adapter,
        transport      = Transport,
        transport_opts = TransportOpts
    }.
