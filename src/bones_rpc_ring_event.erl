%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :  05 Aug 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_ring_event).

-include("bones_rpc.hrl").
-include("bones_rpc_internal.hrl").

-define(EMITTER, bones_rpc_ring_emitter).

%% API
-export([add_handler/2, ring_update/1]).

%%%===================================================================
%%% API functions
%%%===================================================================

add_handler(Handler, {Ref, Pid}) ->
    gen_event:add_handler(?EMITTER, Handler, {Ref, Pid}).

ring_update(Ring=#bones_rpc_ring_v1{}) ->
    gen_event:notify(?EMITTER, {ring_update, Ring}).
