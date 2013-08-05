%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :   18 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_erlang).
-behaviour(bones_rpc_adapter).

-include("bones_rpc.hrl").

%% bones_rpc_adapter callbacks
-export([start/1, stop/1, name/0, pack/1, pack/2, unpack/1, unpack/2,
         unpack_stream/1, unpack_stream/2]).

-record(state, {
    decoder = undefined :: undefined | [proplists:property()],
    encoder = undefined :: undefined | [proplists:property()]
}).

%%%===================================================================
%%% bones_rpc_adapter callbacks
%%%===================================================================

start(Config) ->
    Decoder = Config ++ [safe],
    Encoder = Config,
    State = #state{decoder=Decoder, encoder=Encoder},
    {ok, State}.

stop(#state{}) ->
    ok.

name() ->
    <<"erlang">>.

pack(Term) ->
    pack(Term, []).

pack(Term, #state{encoder=Encoder}) ->
    pack(Term, Encoder);
pack(Term, Config) ->
    bones_rpc_adapter:pack_ext(erlang:term_to_binary(Term, Config)).

unpack(ERLANG) ->
    unpack(ERLANG, [safe]).

unpack(#bones_rpc_ext_v1{head=Head, data=Data}, Config) ->
    unpack_erlang(<< Head, Data/binary >>, Config);
unpack(ERLANG, Config) ->
    case unpack_stream(ERLANG, Config) of
        {Term, <<>>} ->
            {ok, Term};
        {_Term, Rest} when is_binary(Rest) ->
            {error, not_just_binary};
        Error ->
            Error
    end.

unpack_stream(ERLANG) ->
    unpack_stream(ERLANG, [safe]).

unpack_stream(#bones_rpc_ext_v1{head=Head, data=Data}, Config) ->
    case unpack_erlang(<< Head, Data/binary >>, Config) of
        {ok, Term} ->
            {Term, <<>>};
        Error ->
            Error
    end;
unpack_stream(EXT, Config) ->
    case bones_rpc_adapter:unpack_ext_stream(EXT) of
        {ERLANG, Rest} when is_binary(ERLANG) andalso is_binary(Rest) ->
            case unpack_erlang(ERLANG, Config) of
                {ok, Term} ->
                    {Term, Rest};
                ErlangError ->
                    ErlangError
            end;
        Error ->
            Error
    end.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

%% @private
unpack_erlang(ERLANG, #state{decoder=Decoder}) ->
    unpack_erlang(ERLANG, Decoder);
unpack_erlang(ERLANG, Config) ->
    try
        {ok, erlang:binary_to_term(ERLANG, Config)}
    catch
        _:Reason ->
            {error, Reason}
    end.
