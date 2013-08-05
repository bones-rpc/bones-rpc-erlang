%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :   18 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_json).
-behaviour(bones_rpc_adapter).

%% bones_rpc_adapter callbacks
-export([start/1, stop/1, name/0, pack/1, pack/2, unpack/1, unpack/2,
         unpack_stream/1, unpack_stream/2]).

%% Internal
-export([decode_token/1, encode_token/1, handle_error/3, handle_incomplete/3]).

-record(state, {
    decoder = undefined :: undefined | function(),
    encoder = undefined :: undefined | function()
}).

%%%===================================================================
%%% bones_rpc_adapter callbacks
%%%===================================================================

start(Config) ->
    Decoder = decoder(Config),
    Encoder = encoder(Config),
    State = #state{decoder=Decoder, encoder=Encoder},
    {ok, State}.

stop(#state{}) ->
    ok.

name() ->
    <<"json">>.

pack(Term) ->
    pack(Term, []).

pack(Term, #state{encoder=Encoder}) ->
    Encoder(Term);
pack(Term, Config) ->
    pack(Term, #state{encoder=encoder(Config)}).

unpack(JSON) ->
    unpack(JSON, []).

unpack(JSON, #state{decoder=Decoder}) ->
    case Decoder(JSON) of
        {error, Reason} ->
            {error, Reason};
        Term ->
            {ok, Term}
    end;
unpack(JSON, Config) ->
    unpack(JSON, #state{decoder=decoder(Config)}).

unpack_stream(JSON) ->
    unpack_stream(JSON, []).

unpack_stream(JSON, #state{decoder=Decoder}) ->
    case Decoder(JSON) of
        {error, incomplete} ->
            {error, incomplete};
        {Term, Remaining} ->
            {Term, Remaining};
        Term ->
            {Term, <<>>}
    end;
unpack_stream(JSON, Config) ->
    unpack_stream(JSON, #state{decoder=decoder(Config)}).

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

%% @private
decode_token(null) ->
    nil;
decode_token(Token) ->
    Token.

%% @private
decoder(Config) ->
    Config1 = lists:keystore(post_decode, 1, Config, {post_decode, fun bones_json:decode_token/1}),
    Config2 = lists:keystore(error_handler, 1, Config1, {error_handler, fun bones_json:handle_error/3}),
    Config3 = lists:keystore(incomplete_handler, 1, Config2, {incomplete_handler, fun bones_json:handle_incomplete/3}),
    jsx:decoder(jsx_to_term, Config3, jsx_config:extract_config(Config3)).

%% @private
encode_token(nil) ->
    null;
encode_token(Token) ->
    Token.

%% @private
encoder(Config) ->
    Config1 = lists:keystore(error_handler, 1, Config, {error_handler, fun bones_json:handle_error/3}),
    Config2 = lists:keystore(pre_encode, 1, Config1, {pre_encode, fun bones_json:encode_token/1}),
    jsx:encoder(jsx_to_json, Config2, jsx_config:extract_config(Config2 ++ [escaped_strings])).

%% @private
handle_error(Term, {encoder, Reason, _, _, _}, _Config) ->
    {error, {Reason, Term}};
handle_error(Remaining, {decoder, done, {jsx_to_term, Term}, _, _}, _Config) ->
    {Term, Remaining};
handle_error(Subject, _InternalState, _Config) ->
    {error, {badarg, Subject}}.

%% @private
handle_incomplete(_Remaining, _InternalState, _Config) ->
    {error, incomplete}.
