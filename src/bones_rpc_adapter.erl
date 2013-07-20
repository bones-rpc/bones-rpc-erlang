%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :   18 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_adapter).
-behaviour(bones_adapter).

-include("bones.hrl").
-include("bones_rpc.hrl").

%% bones_adapter callbacks
-export([pack/1, pack/2, unpack/1, unpack/2, unpack_stream/1, unpack_stream/2]).

%%%===================================================================
%%% bones_adapter callbacks
%%%===================================================================

pack(_Term) ->
    {error, no_adapter}.

pack(Ext=#bones_ext_v1{}, _Adapter) ->
    bones_adapter:pack_ext(Ext);
pack(Term, Adapter) ->
    Adapter:pack(Term).

unpack(_Binary) ->
    {error, no_adapter}.

unpack(Binary, undefined) ->
    case bones_adapter:unpack_ext_stream(Binary) of
        {<< Head, Data/binary >>, <<>>} ->
            {ok, #bones_ext_v1{head=Head, data=Data}};
        {_, Remaining} when is_binary(Remaining) andalso Remaining =/= <<>> ->
            {error, not_just_binary};
        Error ->
            Error
    end;
unpack(Binary, Adapter) ->
    case bones_adapter:unpack_ext_stream(Binary) of
        {<< Head, Data/binary >>, <<>>} when Head =< 100 ->
            {ok, #bones_ext_v1{head=Head, data=Data}};
        {<< Head, Data/binary >>, <<>>} ->
            Adapter:unpack(#bones_ext_v1{head=Head, data=Data});
        {_, Remaining} when is_binary(Remaining) andalso Remaining =/= <<>> ->
            {error, not_just_binary};
        {error, bad_ext_stream} ->
            Adapter:unpack(Binary);
        Error ->
            Error
    end.

unpack_stream(_Binary) ->
    {error, no_adapter}.

unpack_stream(Binary, undefined) ->
    case bones_adapter:unpack_ext_stream(Binary) of
        {<< Head, Data/binary >>, Rest} ->
            {#bones_ext_v1{head=Head, data=Data}, Rest};
        {error, bad_ext_stream} ->
            {error, no_adapter};
        Error ->
            Error
    end;
unpack_stream(Binary, Adapter) ->
    case bones_adapter:unpack_ext_stream(Binary) of
        {<< Head, Data/binary >>, Rest} when Head =< 100 ->
            {#bones_ext_v1{head=Head, data=Data}, Rest};
        {<< Head, Data/binary >>, Rest} ->
            case Adapter:unpack(#bones_ext_v1{head=Head, data=Data}) of
                {ok, Term} ->
                    {Term, Rest};
                Error ->
                    Error
            end;
        {error, bad_ext_stream} ->
            Adapter:unpack_stream(Binary);
        Error ->
            Error
    end.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------
