%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :   18 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_factory).

-include("bones_rpc.hrl").
-include("bones_rpc_internal.hrl").

%% API
-export([build/1]).

%%%===================================================================
%%% API functions
%%%===================================================================

build({ext, Head, Data}) ->
    {ok, #bones_rpc_ext_v1{head=Head, data=Data}};
build({synchronize, ID, Adapter}) when is_binary(Adapter) ->
    Head = ?BONES_RPC_EXT_SYNCHRONIZE,
    Data = << ID:4/big-unsigned-integer-unit:8, Adapter/binary >>,
    build({ext, Head, Data});
build({acknowledge, ID, Ready}) when is_boolean(Ready) ->
    Head = ?BONES_RPC_EXT_ACKNOWLEDGE,
    Data = << ID:4/big-unsigned-integer-unit:8, case Ready of false -> 16#C2; true -> 16#C3 end >>,
    build({ext, Head, Data});
build({ring, Ring}) ->
    Head = ?BONES_RPC_EXT_RING,
    Data = bones_rpc_ring_v1:to_binary(Ring),
    build({ext, Head, Data});
build({request, ID, Method, Params}) ->
    {ok, [?BONES_RPC_REQUEST, ID, Method, Params]};
build({response, ID, Error, Result}) ->
    {ok, [?BONES_RPC_RESPONSE, ID, Error, Result]};
build({notify, Method, Params}) ->
    {ok, [?BONES_RPC_NOTIFY, Method, Params]};
build(_) ->
    {error, badarg}.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------
