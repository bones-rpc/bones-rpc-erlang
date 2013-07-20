%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :  18 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_protocol).
-behaviour(ranch_protocol).

-include("bones.hrl").
-include("bones_rpc.hrl").

-define(DISPATCHER, bones_rpc_dispatcher).

%% ranch_protocol callbacks
-export([start_link/4]).

%% API
-export([init/1]).
-export([loop/3]).

-record(state, {
    %% Transport & Socket
    socket    = undefined :: undefined | inet:socket(),
    transport = undefined :: undefined | module(),
    messages  = undefined :: undefined | {atom(), atom(), atom()},

    %% Options
    options = undefined :: undefined | [proplists:property()],
    timeout = infinity  :: infinity | timeout(),

    adapter     = undefined :: undefined | module(),
    hibernate   = false     :: boolean(),
    timeout_ref = undefined :: undefined | reference()
}).

%%%===================================================================
%%% ranch_protocol callbacks
%%%===================================================================

%% @doc Start an bones_rpc_protocol process.
-spec start_link(ranch:ref(), inet:socket(), module(), [proplists:property()])
    -> {ok, pid()}.
start_link(Ref, Socket, Transport, ProtoOpts) ->
    ranch:require([ranch, crypto]),
    Pid = spawn_link(?MODULE, init, [[Ref, Socket, Transport, ProtoOpts]]),
    {ok, Pid}.

%%%===================================================================
%%% API functions
%%%===================================================================

init([Ref, Socket, Transport, ProtoOpts]) ->
    Options = get_value(options, ProtoOpts, []),
    Handler = get_value(handler, ProtoOpts, undefined),
    HandlerOpts = get_value(handler_opts, ProtoOpts, undefined),
    Timeout = get_value(timeout, Options, infinity),
    ok = ranch:accept_ack(Ref),
    State = #state{socket=Socket, transport=Transport, messages=Transport:messages(),
        options=Options, timeout=Timeout},
    dispatcher_init(State, Handler, HandlerOpts).

%%%-------------------------------------------------------------------
%%% dispatcher functions
%%%-------------------------------------------------------------------

dispatcher_init(State=#state{transport=Transport}, Handler, HandlerOpts) ->
    try ?DISPATCHER:dispatch_init({Transport:name(), bones_rpc}, Handler, HandlerOpts) of
        {ok, DispatchState} ->
            before_loop(State, DispatchState, <<>>);
        {ok, DispatchState, hibernate} ->
            before_loop(State#state{hibernate=true}, DispatchState, <<>>);
        {ok, DispatchState, Timeout} ->
            before_loop(State#state{timeout=Timeout}, DispatchState, <<>>);
        {ok, DispatchState, Timeout, hibernate} ->
            before_loop(State#state{timeout=Timeout, hibernate=true}, DispatchState, <<>>);
        {shutdown, Reason, DispatchState} ->
            dispatcher_terminate(Reason, DispatchState, undefined, State)
    catch
        Class:Reason ->
            error_logger:error_msg(
                "** ~p ~p terminating in ~p/~p~n"
                "   for the reason ~p:~p~n** Handler was ~p~n"
                "** Handler options were ~p~n** Stacktrace: ~p~n~n",
                [?MODULE, self(), dispatcher_init, 3, Class, Reason, Handler, HandlerOpts, erlang:get_stacktrace()]),
            terminate(Reason, State)
    end.

dispatcher_request(State, DispatchState, Data, Callback, Request, NextState) ->
    try ?DISPATCHER:Callback(Request, DispatchState) of
        {ok, DispatchState2} ->
            State2 = loop_timeout(State),
            NextState(State2, DispatchState2, Data);
        {ok, DispatchState2, hibernate} ->
            State2 = loop_timeout(State),
            NextState(State2#state{hibernate=true}, DispatchState2, Data);
        {ok, DispatchState2, Timeout} ->
            State2 = loop_timeout(State),
            NextState(State2#state{timeout=Timeout}, DispatchState2, Data);
        {ok, DispatchState2, Timeout, hibernate} ->
            State2 = loop_timeout(State),
            NextState(State2#state{timeout=Timeout, hibernate=true}, DispatchState2, Data);
        {shutdown, Reason, DispatchState2} ->
            dispatcher_terminate(State, DispatchState2, Request, Reason)
    catch
        Class:Reason ->
            error_logger:error_msg(
                "** ~p ~p terminating in ~p/~p~n"
                "   for the reason ~p:~p~n** Request was ~p~n"
                "** Options were ~p~n** Stacktrace: ~p~n~n",
                [?MODULE, self(), dispatcher_request, 6, Class, Reason, Request, State#state.options, erlang:get_stacktrace()]),
            dispatcher_terminate(State, DispatchState, Request, Reason)
    end.

dispatcher_notify(State, DispatchState, Data, Callback, Notify, NextState) ->
    try ?DISPATCHER:Callback(Notify, DispatchState) of
        {ok, DispatchState2} ->
            State2 = loop_timeout(State),
            NextState(State2, DispatchState2, Data);
        {ok, DispatchState2, hibernate} ->
            State2 = loop_timeout(State),
            NextState(State2#state{hibernate=true}, DispatchState2, Data);
        {ok, DispatchState2, Timeout} ->
            State2 = loop_timeout(State),
            NextState(State2#state{timeout=Timeout}, DispatchState2, Data);
        {ok, DispatchState2, Timeout, hibernate} ->
            State2 = loop_timeout(State),
            NextState(State2#state{timeout=Timeout, hibernate=true}, DispatchState2, Data);
        {shutdown, Reason, DispatchState2} ->
            dispatcher_terminate(State, DispatchState2, Notify, Reason)
    catch
        Class:Reason ->
            error_logger:error_msg(
                "** ~p ~p terminating in ~p/~p~n"
                "   for the reason ~p:~p~n** Notify was ~p~n"
                "** Options were ~p~n** Stacktrace: ~p~n~n",
                [?MODULE, self(), dispatcher_notify, 6, Class, Reason, Notify, State#state.options, erlang:get_stacktrace()]),
            dispatcher_terminate(State, DispatchState, Notify, Reason)
    end.

dispatcher_info(State, DispatchState, Data, Callback, Info, NextState) ->
    try ?DISPATCHER:Callback(Info, DispatchState) of
        {ok, DispatchState2} ->
            State2 = loop_timeout(State),
            NextState(State2, DispatchState2, Data);
        {ok, DispatchState2, hibernate} ->
            State2 = loop_timeout(State),
            NextState(State2#state{hibernate=true}, DispatchState2, Data);
        {ok, DispatchState2, Timeout} ->
            State2 = loop_timeout(State),
            NextState(State2#state{timeout=Timeout}, DispatchState2, Data);
        {ok, DispatchState2, Timeout, hibernate} ->
            State2 = loop_timeout(State),
            NextState(State2#state{timeout=Timeout, hibernate=true}, DispatchState2, Data);
        {shutdown, Reason, DispatchState2} ->
            dispatcher_terminate(State, DispatchState2, undefined, Reason)
    catch
        Class:Reason ->
            error_logger:error_msg(
                "** ~p ~p terminating in ~p/~p~n"
                "   for the reason ~p:~p~n** Options were ~p~n"
                "** Stacktrace: ~p~n~n",
                [?MODULE, self(), dispatcher_info, 6, Class, Reason, State#state.options, erlang:get_stacktrace()]),
            dispatcher_terminate(State, DispatchState, undefined, Reason)
    end.

dispatcher_terminate(State, DispatchState, Message, TerminateReason) ->
    try
        ?DISPATCHER:dispatch_terminate(TerminateReason, Message, DispatchState)
    catch
        Class:Reason ->
            error_logger:error_msg(
                "** ~p ~p terminating in ~p/~p~n"
                "   for the reason ~p:~p~n** Options were ~p~n"
                "** Message was ~p~n** Stacktrace: ~p~n~n",
                [?MODULE, self(), dispatcher_terminate, 4, Class, Reason, State#state.options, Message, erlang:get_stacktrace()]),
            terminate(Reason, State)
    end.

%%%-------------------------------------------------------------------
%%% loop functions
%%%-------------------------------------------------------------------

%% @private
before_loop(State=#state{hibernate=true, transport=Transport, socket=Socket}, DispatchState, SoFar) ->
    Transport:setopts(Socket, [{active, once}]),
    erlang:hibernate(?MODULE, loop, [State#state{hibernate=false}, DispatchState, SoFar]);
before_loop(State=#state{transport=Transport, socket=Socket}, DispatchState, SoFar) ->
    Transport:setopts(Socket, [{active, once}]),
    loop(State, DispatchState, SoFar).

%% @private
loop(State=#state{socket=Socket, messages={OK, Closed, Error}, timeout_ref=TRef}, DispatchState, SoFar) ->
    receive
        {OK, Socket, Data} ->
            State2 = loop_timeout(State),
            parse_data(State2, DispatchState, << SoFar/binary, Data/binary >>);
        {Closed, Socket} ->
            dispatcher_terminate(State, DispatchState, undefined, {error, closed});
        {Error, Socket, Reason} ->
            dispatcher_terminate(State, DispatchState, undefined, {error, Reason});
        {timeout, TRef, ?MODULE} ->
            dispatcher_terminate(State, DispatchState, undefined, {normal, timeout});
        {timeout, OlderTRef, ?MODULE} when is_reference(OlderTRef) ->
            loop(State, DispatchState, SoFar);
        {'$bones_rpc_reply', MsgID, MsgError, MsgResult} ->
            Response = [?BONES_RPC_RESPONSE, MsgID, MsgError, MsgResult],
            send(State, DispatchState, SoFar, Response, fun loop/3);
        Message ->
            dispatcher_info(State, DispatchState, SoFar, dispatch_info, Message, fun loop/3)
    end.

%% @private
loop_timeout(State=#state{timeout=infinity}) ->
    State#state{timeout_ref=undefined};
loop_timeout(State=#state{timeout=Timeout, timeout_ref=PrevRef}) ->
    _ = case PrevRef of
        undefined -> ignore;
        PrevRef -> erlang:cancel_timer(PrevRef)
    end,
    TRef = erlang:start_timer(Timeout, self(), ?MODULE),
    State#state{timeout_ref=TRef}.

parse_data(State=#state{adapter=Adapter}, DispatchState, Data) ->
    case bones_rpc_adapter:unpack_stream(Data, Adapter) of
        {#bones_ext_v1{head=0, data = << ID:4/big-unsigned-integer-unit:8, NewAdapter/binary >>}, RemainingData} ->
            case bones_adapter:find(NewAdapter) of
                undefined ->
                    send(State#state{adapter=undefined}, DispatchState, RemainingData, bones_protocol:acknowledge(ID, false), fun parse_data/3);
                AdapterModule when is_atom(AdapterModule) ->
                    send(State#state{adapter=AdapterModule}, DispatchState, RemainingData, bones_protocol:acknowledge(ID, true), fun parse_data/3)
            end;
        {[?BONES_RPC_REQUEST, MsgID, Method, Params], RemainingData} ->
            Request = {request, MsgID, Method, Params},
            dispatcher_request(State, DispatchState, RemainingData, dispatch_request, Request, fun parse_data/3);
        {[?BONES_RPC_NOTIFY, Method, Params], RemainingData} ->
            Notify = {notify, Method, Params},
            dispatcher_notify(State, DispatchState, RemainingData, dispatch_notify, Notify, fun parse_data/3);
        {error, incomplete} ->
            %% Need more data.
            before_loop(State, DispatchState, Data);
        {error, _} = Error ->
            dispatcher_terminate(State, DispatchState, undefined, Error)
    end.

send(State=#state{transport=Transport, socket=Socket, adapter=Adapter}, DispatchState, Data, Object, NextState) ->
    try bones_rpc_adapter:pack(Object, Adapter) of
        Packet when is_binary(Packet) ->
            case Transport:send(Socket, Packet) of
                ok ->
                    State2 = loop_timeout(State),
                    NextState(State2, DispatchState, Data);
                {error, SocketReason} ->
                    dispatcher_terminate(State, DispatchState, undefined, {error, SocketReason})
            end;
        {error, AdapterReason} ->
            erlang:error(AdapterReason)
    catch
        Class:Reason ->
            error_logger:error_msg(
                "** ~p ~p terminating in ~p/~p~n"
                "   for the reason ~p:~p~n** Stacktrace: ~p~n~n",
                [?MODULE, self(), send, 5, Class, Reason, erlang:get_stacktrace()]),
            dispatcher_terminate(State, DispatchState, undefined, {error, Reason})
    end.

terminate(_TerminateReason, _State=#state{transport=Transport, socket=Socket}) ->
    Transport:close(Socket),
    ok.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

%% @doc Faster alternative to proplists:get_value/3.
get_value(Key, Opts, Default) ->
  case lists:keyfind(Key, 1, Opts) of
    {_, Value} -> Value;
    _ -> Default
  end.
