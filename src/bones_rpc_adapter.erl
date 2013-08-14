%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :   18 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_adapter).

-include("bones_rpc.hrl").

-type config() :: any().

-type packed()   :: binary().
-type unpacked() :: term().

-type pack_return()   :: Binary::packed() | {error, Reason::any()}.
-type unpack_return() :: {ok, Term::unpacked()} | {error, Reason::any()}.
-type unpack_stream_return() :: {error, incomplete} | {error, Reason::any()} | {Term::unpacked(), Binary::packed()}.

-callback start(Config::config())
    -> {ok, State::any()} | {error, Reason::any()}.
-callback stop(State::any())
    -> term().
-callback name()
    -> Name::binary().
-callback pack(Term::unpacked())
    -> Result::pack_return().
-callback pack(Term::unpacked(), Config::config())
    -> Result::pack_return().
-callback unpack(Binary::packed())
    -> Result::unpack_return().
-callback unpack(Binary::packed(), Config::config())
    -> Result::unpack_return().
-callback unpack_stream(Binary::packed())
    -> Result::unpack_stream_return().
-callback unpack_stream(Binary::packed(), Config::config())
    -> Result::unpack_stream_return().

%% API
-export([pack_ext/1, unpack_ext_stream/1]).

%% bones_rpc_adapter callbacks
-export([start/1, stop/1, name/0, pack/1, pack/2, unpack/1, unpack/2,
         unpack_stream/1, unpack_stream/2]).

%%%===================================================================
%%% API functions
%%%===================================================================

pack_ext(#bones_rpc_ext_v1{head=Head, data=Data}) ->
    pack_ext(<< Head, Data/binary >>);
pack_ext(Packed) when is_binary(Packed) ->
    ext_pack(Packed, size(Packed)).

unpack_ext_stream(<<>>) ->
    {error, incomplete};
unpack_ext_stream(<< 16#C7, Stream/binary >>) ->
    ext8_unpack_stream(Stream);
unpack_ext_stream(<< 16#C8, Stream/binary >>) ->
    ext16_unpack_stream(Stream);
unpack_ext_stream(<< 16#C9, Stream/binary >>) ->
    ext32_unpack_stream(Stream);
unpack_ext_stream(_) ->
    {error, bad_ext_stream}.

%%%===================================================================
%%% bones_rpc_adapter callbacks
%%%===================================================================

start(Adapter) ->
    case Adapter:start([]) of
        {ok, State} ->
            {ok, State};
        Error ->
            Error
    end.

stop({Adapter, State}) ->
    _ = Adapter:stop(State),
    ok.

name() ->
    <<>>.

pack(_Term) ->
    {error, no_adapter}.

pack(Ext=#bones_rpc_ext_v1{}, _State) ->
    pack_ext(Ext);
pack(Term, {Adapter, State}) ->
    Adapter:pack(Term, State);
pack(Term, Adapter) ->
    Adapter:pack(Term).

unpack(_Binary) ->
    {error, no_adapter}.

unpack(Binary, undefined) ->
    case unpack_ext_stream(Binary) of
        {<< Head, Data/binary >>, <<>>} ->
            {ok, #bones_rpc_ext_v1{head=Head, data=Data}};
        {_, Remaining} when is_binary(Remaining) andalso Remaining =/= <<>> ->
            {error, not_just_binary};
        Error ->
            Error
    end;
unpack(Binary, {Adapter, State}) ->
    case unpack_ext_stream(Binary) of
        {<< Head, Data/binary >>, <<>>} when Head =< 100 ->
            {ok, #bones_rpc_ext_v1{head=Head, data=Data}};
        {<< Head, Data/binary >>, <<>>} ->
            Adapter:unpack(#bones_rpc_ext_v1{head=Head, data=Data}, State);
        {_, Remaining} when is_binary(Remaining) andalso Remaining =/= <<>> ->
            {error, not_just_binary};
        {error, bad_ext_stream} ->
            Adapter:unpack(Binary, State);
        Error ->
            Error
    end;
unpack(Binary, Adapter) ->
    case unpack_ext_stream(Binary) of
        {<< Head, Data/binary >>, <<>>} when Head =< 100 ->
            {ok, #bones_rpc_ext_v1{head=Head, data=Data}};
        {<< Head, Data/binary >>, <<>>} ->
            Adapter:unpack(#bones_rpc_ext_v1{head=Head, data=Data});
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
    case unpack_ext_stream(Binary) of
        {<< Head, Data/binary >>, Rest} ->
            {#bones_rpc_ext_v1{head=Head, data=Data}, Rest};
        {error, bad_ext_stream} ->
            {error, no_adapter};
        Error ->
            Error
    end;
unpack_stream(Binary, {Adapter, State}) ->
    case unpack_ext_stream(Binary) of
        {<< Head, Data/binary >>, Rest} when Head =< 100 ->
            {#bones_rpc_ext_v1{head=Head, data=Data}, Rest};
        {<< Head, Data/binary >>, Rest} ->
            case Adapter:unpack(#bones_rpc_ext_v1{head=Head, data=Data}, State) of
                {ok, Term} ->
                    {Term, Rest};
                Error ->
                    Error
            end;
        {error, bad_ext_stream} ->
            Adapter:unpack_stream(Binary, State);
        Error ->
            Error
    end;
unpack_stream(Binary, Adapter) ->
    case unpack_ext_stream(Binary) of
        {<< Head, Data/binary >>, Rest} when Head =< 100 ->
            {#bones_rpc_ext_v1{head=Head, data=Data}, Rest};
        {<< Head, Data/binary >>, Rest} ->
            case Adapter:unpack(#bones_rpc_ext_v1{head=Head, data=Data}) of
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

%% @private
ext_pack(Packed, Size) when Size =< 16#FF ->
    << 16#C7, Size, 16#0D, Packed/binary >>;
ext_pack(Packed, Size) when Size =< 16#FFFF ->
    << 16#C8, Size:2/big-unsigned-integer-unit:8, 16#0D, Packed/binary >>;
ext_pack(Packed, Size) when Size =< 16#FFFFFFFF ->
    << 16#C9, Size:4/big-unsigned-integer-unit:8, 16#0D, Packed/binary >>;
ext_pack(_Packed, _Size) ->
    {error, too_large}.

%% @private
ext8_unpack_stream(<< Size, 16#0D, Packed:Size/binary, Rest/binary >>) when Size >= 2 ->
    {Packed, Rest};
ext8_unpack_stream(<< _, C >>) when C =/= 16#0D ->
    {error, bad_ext_stream};
ext8_unpack_stream(_) ->
    {error, incomplete}.

%% @private
ext16_unpack_stream(<< Size:2/big-unsigned-integer-unit:8, 16#0D, Packed:Size/binary, Rest/binary >>) when Size >= 2 ->
    {Packed, Rest};
ext16_unpack_stream(<< _:2/big-unsigned-integer-unit:8, C >>) when C =/= 16#0D ->
    {error, bad_ext_stream};
ext16_unpack_stream(_) ->
    {error, incomplete}.

%% @private
ext32_unpack_stream(<< Size:4/big-unsigned-integer-unit:8, 16#0D, Packed:Size/binary, Rest/binary >>) when Size >= 2 ->
    {Packed, Rest};
ext32_unpack_stream(<< _:4/big-unsigned-integer-unit:8, C >>) when C =/= 16#0D ->
    {error, bad_ext_stream};
ext32_unpack_stream(_) ->
    {error, incomplete}.
