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
-include("bones_rpc_internal.hrl").

%% API
-export([manual_start/0]).
-export([connect/1, connect/3, disconnect/1]).
-export([new_cluster/1, rm_cluster/1, delete_cluster/1]).
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

% -type synchronize_message() :: {synchronize, ID::integer(), Adapter::binary()}.
% -type acknowledge_message() :: {acknowledge, ID::integer(), Ready::boolean()}.
% -type request_message()     :: {request, ID::integer(), Method::any(), Params::[any()]}.
% -type response_message()    :: {response, ID::integer(), Error::any(), Result::any()}.
% -type notify_message()      :: {notify, Method::any(), Params::[any()]}.

% -type message() ::
%     synchronize_message() |
%     acknowledge_message() |
%     request_message() |
%     response_message() |
%     notify_message().

%%%===================================================================
%%% API functions
%%%===================================================================

manual_start() ->
    application:start(sasl),
    application:start(crypto),
    application:start(ranch),
    application:start(bones_rpc).

connect(List) ->
    Conn = bones_rpc_config:list_to_conn(List),
    bones_rpc_connection:start_link(Conn).

connect(Host, Port, Options) ->
    Address = bones_rpc_address:new(Host, Port),
    case bones_rpc_address:resolve(Address) of
        {ok, Address2} ->
            connect([{address, Address2} | Options]);
        Error ->
            Error
    end.

disconnect(Pid) when is_pid(Pid) ->
    _ = bones_rpc_client:shutdown(Pid),
    ok.

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

new_cluster(Cluster) ->
    bones_rpc_sup:new_cluster(Cluster).

rm_cluster(Cluster) ->
    bones_rpc_sup:rm_cluster(Cluster).

delete_cluster(Cluster) ->
    bones_rpc_sup:delete_cluster(Cluster).

reply({To, Tag={synack, _MsgID}}, Message={true, Adapter}) when is_atom(Adapter) ->
    catch To ! {'$bones_rpc_reply', Tag, Message};
reply({To, Tag={synack, _MsgID}}, Message=false) ->
    catch To ! {'$bones_rpc_reply', Tag, Message};
reply({To, Tag={request, _MsgID}}, {error, Error}) ->
    catch To ! {'$bones_rpc_reply', Tag, Error, nil};
reply({To, Tag={request, _MsgID}}, {result, Result}) ->
    catch To ! {'$bones_rpc_reply', Tag, nil, Result}.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------
