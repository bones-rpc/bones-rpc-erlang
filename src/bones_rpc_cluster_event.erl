%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :  05 Aug 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_cluster_event).

-include("bones_rpc.hrl").
-include("bones_rpc_internal.hrl").

%% API
-export([add_handler/2, cluster_stop/2, node_start/1, node_up/1, node_down/1, node_stop/2, ring_update/2]).

%%%===================================================================
%%% API functions
%%%===================================================================

add_handler(Handler, Cluster=#cluster{emitter=Emitter}) ->
    gen_event:add_handler(Emitter, Handler, Cluster).

cluster_stop(Cluster=#cluster{emitter=Emitter}, Reason) ->
    gen_event:notify(Emitter, {cluster, stop, Cluster, Reason}).

node_start(Node=#node{emitter=Emitter}) ->
    gen_event:notify(Emitter, {node, start, Node}).

node_up(Node=#node{emitter=Emitter}) ->
    gen_event:notify(Emitter, {node, up, Node}).

node_down(Node=#node{emitter=Emitter}) ->
    gen_event:notify(Emitter, {node, down, Node}).

node_stop(Node=#node{emitter=Emitter}, Reason) ->
    gen_event:notify(Emitter, {node, stop, Node, Reason}).

ring_update(#conn{emitter=undefined}, _Ring) ->
    ok;
ring_update(Conn=#conn{emitter=Emitter}, Ring=#bones_rpc_ring_v1{}) ->
    gen_event:notify(Emitter, {ring_update, Conn, Ring}).
