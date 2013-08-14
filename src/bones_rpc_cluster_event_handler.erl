%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :  05 Aug 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_cluster_event_handler).
-behaviour(gen_event).

-include("bones_rpc_internal.hrl").

%% gen_event callbacks
-export([init/1, handle_event/2, handle_call/2, handle_info/2,
         terminate/2, code_change/3]).

%%%===================================================================
%%% gen_event callbacks
%%%===================================================================

init(Cluster=#cluster{}) ->
    {ok, Cluster}.

handle_event({cluster, stop, _OrigCluster, normal}, Cluster) ->
    ok = bones_rpc_ring:delete_cluster(Cluster),
    remove_handler;
handle_event({node, start, _Node}, Cluster) ->
    {ok, Cluster};
handle_event({node, stop, Node, normal}, Cluster) ->
    bones_rpc_cluster_sup:delete_node(Node),
    {ok, Cluster};
handle_event({node, up, Node}, Cluster) ->
    bones_rpc_node_sup:add_pool(Node),
    {ok, Cluster};
handle_event({node, down, Node}, Cluster) ->
    bones_rpc_node_sup:rm_pool(Node),
    {ok, Cluster};
handle_event({ring_update, Conn, Ring}, Cluster) ->
    bones_rpc_cluster:ring_update(Cluster, Conn, Ring),
    {ok, Cluster};
handle_event(_Event, Cluster) ->
    {ok, Cluster}.

handle_call(_Request, Cluster) ->
    {ok, ok, Cluster}.

handle_info({'EXIT', _Parent, shutdown}, _Cluster) ->
    remove_handler;
handle_info(_Info, Cluster) ->
    {ok, Cluster}.

terminate(_Reason, _Cluster) ->
    ok.

code_change(_OldVsn, Cluster, _Extra) ->
    {ok, Cluster}.
