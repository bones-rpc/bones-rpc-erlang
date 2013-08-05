%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :   18 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_msgpack).
-behaviour(bones_rpc_adapter).

%% bones_rpc_adapter callbacks
-export([start/1, stop/1, name/0, pack/1, pack/2, unpack/1, unpack/2,
         unpack_stream/1, unpack_stream/2]).

%%%===================================================================
%%% bones_rpc_adapter callbacks
%%%===================================================================

start(Config) ->
    {ok, Config ++ [jsx]}.

stop(_Config) ->
    ok.

name() ->
    <<"msgpack">>.

pack(Term) ->
    pack(Term, [jsx]).

pack(Term, Config) ->
    msgpack:pack(Term, Config).

unpack(MSGPACK) ->
    unpack(MSGPACK, [jsx]).

unpack(MSGPACK, Config) ->
    msgpack:unpack(MSGPACK, Config).

unpack_stream(MSGPACK) ->
    unpack_stream(MSGPACK, [jsx]).

unpack_stream(MSGPACK, Config) ->
    msgpack:unpack_stream(MSGPACK, Config).

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------
