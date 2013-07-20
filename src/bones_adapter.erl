%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :   18 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_adapter).

-include("bones.hrl").

-type config() :: any().

-type packed()   :: binary().
-type unpacked() :: term().

-type pack_return()   :: Binary::packed() | {error, Reason::any()}.
-type unpack_return() :: {ok, Term::unpacked()} | {error, Reason::any()}.
-type unpack_stream_return() :: {error, incomplete} | {error, Reason::any()} | {Term::unpacked(), Binary::packed()}.

-callback pack(Term::unpacked()) -> Result::pack_return().
-callback pack(Term::unpacked(), Config::config()) -> Result::pack_return().
-callback unpack(Binary::packed()) -> Result::unpack_return().
-callback unpack(Binary::packed(), Config::config()) -> Result::unpack_return().
-callback unpack_stream(Binary::packed()) -> Result::unpack_stream_return().
-callback unpack_stream(Binary::packed(), Config::config()) -> Result::unpack_stream_return().

%% API
-export([find/1, new_ext/2, pack_ext/1, unpack_ext_stream/1]).

%%%===================================================================
%%% API functions
%%%===================================================================

find(<<"erlang">>) ->
    bones_erlang;
find(<<"json">>) ->
    bones_json;
find(<<"msgpack">>) ->
    bones_msgpack;
find(_) ->
    undefined.

new_ext(Head, Data) when is_integer(Head) andalso is_binary(Data) ->
    #bones_ext_v1{head=Head, data=Data}.

pack_ext(#bones_ext_v1{head=Head, data=Data}) ->
    pack_ext(<< Head, Data/binary >>);
pack_ext(Packed) when is_binary(Packed) ->
    pack_ext(Packed, size(Packed)).

unpack_ext_stream(<<>>) ->
    {error, incomplete};
unpack_ext_stream(<< 16#C7, Stream/binary >>) ->
    unpack_ext8(Stream);
unpack_ext_stream(<< 16#C8, Stream/binary >>) ->
    unpack_ext16(Stream);
unpack_ext_stream(<< 16#C9, Stream/binary >>) ->
    unpack_ext32(Stream);
unpack_ext_stream(_) ->
    {error, bad_ext_stream}.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

%% @private
pack_ext(Packed, Size) when Size =< 16#FF ->
    << 16#C7, Size, 16#0D, Packed/binary >>;
pack_ext(Packed, Size) when Size =< 16#FFFF ->
    << 16#C8, Size:2/big-unsigned-integer-unit:8, 16#0D, Packed/binary >>;
pack_ext(Packed, Size) when Size =< 16#FFFFFFFF ->
    << 16#C9, Size:4/big-unsigned-integer-unit:8, 16#0D, Packed/binary >>;
pack_ext(_Packed, _Size) ->
    {error, too_large}.

%% @private
unpack_ext8(<< Size, 16#0D, Packed:Size/binary, Rest/binary >>) when Size >= 2 ->
    {Packed, Rest};
unpack_ext8(<< _, C >>) when C =/= 16#0D ->
    {error, bad_ext_stream};
unpack_ext8(_) ->
    {error, incomplete}.

%% @private
unpack_ext16(<< Size:2/big-unsigned-integer-unit:8, 16#0D, Packed:Size/binary, Rest/binary >>) when Size >= 2 ->
    {Packed, Rest};
unpack_ext16(<< _:2/big-unsigned-integer-unit:8, C >>) when C =/= 16#0D ->
    {error, bad_ext_stream};
unpack_ext16(_) ->
    {error, incomplete}.

%% @private
unpack_ext32(<< Size:4/big-unsigned-integer-unit:8, 16#0D, Packed:Size/binary, Rest/binary >>) when Size >= 2 ->
    {Packed, Rest};
unpack_ext32(<< _:4/big-unsigned-integer-unit:8, C >>) when C =/= 16#0D ->
    {error, bad_ext_stream};
unpack_ext32(_) ->
    {error, incomplete}.
