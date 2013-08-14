%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :  05 Aug 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_ring_event_handler).
-behaviour(gen_event).

-include("bones_rpc_internal.hrl").

%% gen_event callbacks
-export([init/1, handle_event/2, handle_call/2, handle_info/2,
         terminate/2, code_change/3]).

%%%===================================================================
%%% gen_event callbacks
%%%===================================================================

init(State) ->
    {ok, State}.

handle_event({ring_update, Ring}, State={_Ref, Pid}) ->
    catch Pid ! {'$bones_rpc_ring', Ring},
    {ok, State};
handle_event(_Event, State) ->
    {ok, State}.

handle_call(_Request, State) ->
    {ok, ok, State}.

handle_info({'EXIT', _Parent, shutdown}, _State) ->
    remove_handler;
handle_info(_Info, State) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
