%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :   18 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_json).
-behaviour(bones_adapter).

%% bones_adapter callbacks
-export([name/0, pack/1, pack/2, unpack/1, unpack/2, unpack_stream/1, unpack_stream/2]).

%% Internal
-export([decode_token/1, encode_token/1, handle_error/3, handle_incomplete/3]).

%%%===================================================================
%%% bones_adapter callbacks
%%%===================================================================

name() ->
    <<"json">>.

pack(Term) ->
    pack(Term, []).

pack(Term, Config) ->
    Config1 = lists:keystore(error_handler, 1, Config, {error_handler, fun bones_json:handle_error/3}),
    Config2 = lists:keystore(pre_encode, 1, Config1, {pre_encode, fun bones_json:encode_token/1}),
    jsx:encode(Term, Config2).

unpack(JSON) ->
    unpack(JSON, []).

unpack(JSON, Config) ->
    Config1 = lists:keystore(post_decode, 1, Config, {post_decode, fun bones_json:decode_token/1}),
    Config2 = lists:keystore(error_handler, 1, Config1, {error_handler, fun bones_json:handle_error/3}),
    Config3 = lists:keystore(incomplete_handler, 1, Config2, {incomplete_handler, fun bones_json:handle_incomplete/3}),
    case jsx:decode(JSON, Config3) of
        {error, Reason} ->
            {error, Reason};
        Term ->
            {ok, Term}
    end.

unpack_stream(JSON) ->
    unpack_stream(JSON, []).

unpack_stream(JSON, Config) ->
    Config1 = lists:keystore(post_decode, 1, Config, {post_decode, fun bones_json:decode_token/1}),
    Config2 = lists:keystore(error_handler, 1, Config1, {error_handler, fun bones_json:handle_error/3}),
    Config3 = lists:keystore(incomplete_handler, 1, Config2, {incomplete_handler, fun bones_json:handle_incomplete/3}),
    case jsx:decode(JSON, Config3) of
        {error, incomplete} ->
            {error, incomplete};
        {Term, Remaining} ->
            {Term, Remaining};
        Term ->
            {Term, <<>>}
    end.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

%% @private
decode_token(null) ->
    nil;
decode_token(Token) ->
    Token.

%% @private
encode_token(nil) ->
    null;
encode_token(Token) ->
    Token.

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
