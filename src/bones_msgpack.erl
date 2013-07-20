%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :   18 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_msgpack).
-behaviour(bones_adapter).

%% bones_adapter callbacks
-export([pack/1, pack/2, unpack/1, unpack/2, unpack_stream/1, unpack_stream/2]).

%%%===================================================================
%%% bones_adapter callbacks
%%%===================================================================

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
