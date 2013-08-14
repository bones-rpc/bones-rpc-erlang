% %%%-------------------------------------------------------------------
% %%% @author Andrew Bennett <andrew@pagodabox.com>
% %%% @copyright 2013, Pagoda Box, Inc.
% %%% @doc
% %%%
% %%% @end
% %%% Created :  05 Aug 2013 by Andrew Bennett <andrew@pagodabox.com>
% %%%-------------------------------------------------------------------
-module(bones_rpc_node).
-behaviour(gen_server).

-include("bones_rpc_internal.hrl").

-export([start_link/1, is_down/1, is_up/1, status/2, synchronize/1, shutdown/1, graceful_shutdown/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%%%===================================================================
%%% API functions
%%%===================================================================

start_link(Node=#node{ref=NodeRef}) ->
    gen_server:start_link({local, NodeRef}, ?MODULE, Node, []).

is_down(#node{ref=NodeRef}) ->
    is_down(NodeRef);
is_down(NodeRef) ->
    gen_server:call(NodeRef, is_down).

is_up(#node{ref=NodeRef}) ->
    is_up(NodeRef);
is_up(NodeRef) ->
    gen_server:call(NodeRef, is_up).

status(#node{ref=Ref}, Status) ->
    status(Ref, Status);
status(NodeRef, Status) ->
    gen_server:cast(NodeRef, {status, Status}).

synchronize(#node{ref=NodeRef}) ->
    synchronize(NodeRef);
synchronize(NodeRef) ->
    gen_server:call(NodeRef, synchronize).

shutdown(Node) ->
    gen_server:cast(Node, shutdown).

graceful_shutdown(#node{ref=Ref}) ->
    graceful_shutdown(Ref);
graceful_shutdown(Node) ->
    gen_server:call(Node, graceful_shutdown).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init(Node=#node{}) ->
    ranch:require([pooler]),
    bones_rpc_cluster_event:node_start(Node),
    {ok, Node}.

handle_call(is_down, _From, Node=#node{status=Status}) ->
    {reply, (Status == down), Node};
handle_call(is_up, _From, Node=#node{status=Status}) ->
    {reply, (Status == up), Node=#node{}};
handle_call(synchronize, _From, Node) ->
    Connection = bones_rpc_node_sup:node_connection_name(Node),
    case catch bones_rpc_client:sync_send(Connection, synchronize) of
        {ok, {acknowledge, _ID, Ready}, _Latency} ->
            {reply, Ready, Node};
        _ ->
            {reply, {error, timeout}, Node}
    end;
handle_call(get_state, _From, Node) ->
    {reply, {ok, Node}, Node};
handle_call(graceful_shutdown, _From, Node) ->
    {stop, normal, ok, Node};
handle_call(_Request, _From, Node) ->
    {reply, ok, Node}.

handle_cast({status, down}, Node) ->
    Node2 = Node#node{status=down},
    bones_rpc_cluster_event:node_down(Node2),
    {noreply, Node2};
handle_cast({status, up}, Node) ->
    Node2 = Node#node{status=up},
    bones_rpc_cluster_event:node_up(Node2),
    {noreply, Node2};
handle_cast(shutdown, Node) ->
    {stop, normal, Node};
handle_cast(_Request, Node) ->
    {noreply, Node}.

handle_info(Info, Node) ->
    _ = case Node#node.debug of
        false ->
            ok;
        true ->
            error_logger:warning_msg(
                "[~w] ~w unhandled info: ~p~n",
                [self(), ?MODULE, Info])
    end,
    {noreply, Node}.

terminate(normal, Node) ->
    bones_rpc_cluster_event:node_stop(Node, normal),
    ok;
terminate(_Reason, _Node) ->
    ok.

code_change(_OldVsn, Node, _Extra) ->
    {ok, Node}.
