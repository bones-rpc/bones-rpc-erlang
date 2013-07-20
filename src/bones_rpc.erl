%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc Convenience API to start and stop TCP/SSL clients and listeners.
%%%
%%% @end
%%% Created :  18 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc).

-include("bones_rpc.hrl").

%% API
-export([manual_start/0]).
-export([start_listener/7, stop_listener/1, child_spec/7, reply/2]).

%% Types
-type message_id() :: integer().
-type method()     :: any().
-type params()     :: [any()].
-type error()      :: any().
-type result()     :: any().
-export_type([message_id/0, method/0, params/0, error/0, result/0]).

-type request()    :: {0, message_id(), method(), params()}.
-type response()   :: {1, message_id(), nil, request()} | {1, message_id(), error(), nil}.
-type notify()     :: {2, method(), params()}.
-export_type([request/0, response/0, notify/0]).

-type adapter()     :: binary().
-type synchronize() :: {0, message_id(), adapter()}.
-type acknowledge() :: {1, message_id(), boolean()}.
-export_type([adapter/0, synchronize/0, acknowledge/0]).

%%%===================================================================
%%% API functions
%%%===================================================================

manual_start() ->
    application:start(sasl),
    application:start(crypto),
    application:start(ranch),
    application:start(bones_rpc).

-spec start_listener(ranch:ref(), non_neg_integer(), module(), any(), any(), module(), any())
    -> {ok, pid()} | {error, badarg}.
start_listener(Ref, NbAcceptors, Transport, TransOpts, Options, Handler, HandlerOpts)
        when is_integer(NbAcceptors) andalso is_atom(Transport)
        andalso is_atom(Handler) ->
    ranch:start_listener(Ref, NbAcceptors, Transport, TransOpts, bones_rpc_protocol, [
        {handler, Handler},
        {handler_opts, HandlerOpts},
        {options, Options}
    ]).

-spec stop_listener(ranch:ref()) -> ok | {error, not_found}.
stop_listener(Ref) ->
    ranch:stop_listener(Ref).

%% @doc Return a child spec suitable for embedding.
%%
%% When you want to embed Bones RPC in another application, you can use this
%% function to create a <em>ChildSpec</em> suitable for use in a supervisor.
%% The parameters are the same as in <em>start_listener/7</em> but rather
%% than hooking the listener to the Ranch internal supervisor, it just returns
%% the spec.
-spec child_spec(ranch:ref(), non_neg_integer(), module(), any(), any(), module(), any())
    -> supervisor:child_spec().
child_spec(Ref, NbAcceptors, Transport, TransOpts, Options, Handler, HandlerOpts)
        when is_integer(NbAcceptors) andalso is_atom(Transport)
        andalso is_atom(Handler) ->
    ranch:child_spec(Ref, NbAcceptors, Transport, TransOpts, bones_rpc_protocol, [
        {handler, Handler},
        {handler_opts, HandlerOpts},
        {options, Options}
    ]).

reply({To, MsgID}, {error, Error}) ->
    catch To ! {'$bones_rpc_reply', MsgID, Error, nil};
reply({To, MsgID}, {result, Result}) ->
    catch To ! {'$bones_rpc_reply', MsgID, nil, Result}.
