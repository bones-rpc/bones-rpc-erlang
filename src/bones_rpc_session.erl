%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :  02 Aug 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_session).

-include("bones_rpc.hrl").
-include("bones_rpc_internal.hrl").

-callback init(Client::bones_rpc:client())
    -> {ok, State}
    | {shutdown, Reason::any(), State}.
-callback handle_send(Message::any(), State::any())
    -> {send, Object::any(), State}
    | {send, Object::any(), FutureKey::any(), State}
    | {ignore, State}
    | {shutdown, Reason::any(), State}.
-callback handle_recv(Message::any(), State::any())
    -> {ok, State}
    | {shutdown, Reason::any(), State}.
-callback handle_join(FutureKey::any(), From::{pid(), any()}, State::any())
    -> {reply, Reply::any(), State}
    | {noreply, State}
    | {shutdown, Reason::any(), State}.
-callback handle_down(State::any())
    -> {ok, State}
    | {shutdown, Reason::any(), State}.
-callback handle_up(State::any())
    -> {ok, State}
    | {shutdown, Reason::any(), State}.
-callback handle_info(Info::any(), State::any())
    -> {ok, State}
    | {shutdown, Reason::any(), State}.
-callback code_change(OldVsn::term() | {down, term()}, State::any(), Extra::any())
    -> {ok, State::any()}.
-callback terminate(Reason::any(), State::any())
    -> term().

%% bones_rpc_session callbacks
-export([init/1, handle_send/3, handle_recv/2, handle_join/3, handle_down/1,
         handle_up/1, handle_info/2, code_change/3, terminate/2]).

-record(state, {
    client   = undefined  :: undefined | bones_rpc:client(),
    adapter  = undefined  :: undefined | binary(),
    counters = dict:new() :: dict(),
    futures  = dict:new() :: dict()
}).

%%%===================================================================
%%% bones_rpc_session callbacks
%%%===================================================================

init(Client=#bones_rpc_client_v1{adapter=Adapter}) ->
    AdapterName = Adapter:name(),
    State = #state{client=Client, adapter=AdapterName},
    {ok, State}.

handle_send(synchronize, From, State=#state{adapter=Adapter}) ->
    {ok, ID, State2} = update_counter(synack, {1, 16#fffffffe, 0}, State), %% (1 bsl 32) - 2
    handle_send({synchronize, ID, Adapter}, From, State2);
handle_send({synchronize, ID, Adapter}, From, State) ->
    {ok, Synchronize} = bones_rpc_factory:build({synchronize, ID, Adapter}),
    FutureKey = {synack, ID},
    {ok, State2} = new_future(State, FutureKey, From),
    {send, Synchronize, FutureKey, State2};
handle_send({request, Method, Params}, From, State) ->
    {ok, ID, State2} = update_counter(request, {1, 16#7fffffff, 0}, State), %% (1 bsl 31) - 1
    handle_send({request, ID, Method, Params}, From, State2);
handle_send({request, ID, Method, Params}, From, State) ->
    {ok, Request} = bones_rpc_factory:build({request, ID, Method, Params}),
    FutureKey = {request, ID},
    {ok, State2} = new_future(State, FutureKey, From),
    {send, Request, FutureKey, State2};
handle_send({notify, Method, Params}, _From, State) ->
    {ok, Notify} = bones_rpc_factory:build({notify, Method, Params}),
    {send, Notify, State}.

handle_recv([?BONES_RPC_RESPONSE, ID, Error, Result], State) ->
    Response = {response, ID, Error, Result},
    signal_future(State, {request, ID}, Response);
handle_recv(#bones_rpc_ext_v1{head=?BONES_RPC_EXT_ACKNOWLEDGE, data = << ID:4/big-unsigned-integer-unit:8, 16#C2 >>}, State) ->
    Acknowledge = {acknowledge, ID, false},
    signal_future(State, {synack, ID}, Acknowledge);
handle_recv(#bones_rpc_ext_v1{head=?BONES_RPC_EXT_ACKNOWLEDGE, data = << ID:4/big-unsigned-integer-unit:8, 16#C3 >>}, State) ->
    Acknowledge = {acknowledge, ID, true},
    signal_future(State, {synack, ID}, Acknowledge);
handle_recv(#bones_rpc_ext_v1{head=?BONES_RPC_EXT_RING, data=Data}, State) ->
    case bones_rpc_ring_v1:from_binary(Data) of
        Ring=#bones_rpc_ring_v1{} ->
            self() ! {'$bones_rpc_ring', Ring},
            {ok, State};
        _ ->
            {ok, State}
    end.

handle_join(Key, From, State=#state{futures=Futures}) ->
    case dict:find(Key, Futures) of
        {ok, {undefined, Start, undefined, Queue}} ->
            Queue2 = queue:in(From, Queue),
            Future = {undefined, Start, undefined, Queue2},
            Futures2 = dict:store(Key, Future, Futures),
            State2 = State#state{futures=Futures2},
            {noreply, State2};
        {ok, {Value, Start, Stop, Queue}} ->
            Futures2 = dict:erase(Key, Futures),
            State2 = State#state{futures=Futures2},
            Reply = {ok, Value, timer:now_diff(Stop, Start)},
            ok = reply_to_queue(Reply, Queue),
            {reply, Reply, State2};
        error ->
            {reply, {error, {no_future, Key}}, State}
    end.

handle_down(State=#state{futures=Futures}) ->
    ok = dict:fold(fun
        (_Key, {undefined, Start, undefined, Queue}, ok) ->
            Stop = erlang:now(),
            case queue:is_empty(Queue) of
                true ->
                    ok;
                false ->
                    Reply = {error, no_connection, timer:now_diff(Stop, Start)},
                    ok = reply_to_queue(Reply, Queue),
                    ok
            end;
        (_Key, {Value, Start, Stop, Queue}, ok) ->
            case queue:is_empty(Queue) of
                true ->
                    ok;
                false ->
                    Reply = {ok, Value, timer:now_diff(Stop, Start)},
                    ok = reply_to_queue(Reply, Queue),
                    ok
            end;
        (_Key, _Value, ok) ->
            ok
    end, ok, Futures),
    State2 = State#state{futures=dict:new()},
    {ok, State2}.

handle_up(State) ->
    {ok, State}.

handle_info(_Info, State) ->
    {ok, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

%% @private
update_counter(Key, {Incr, Threshold, SetValue}, State=#state{counters=Counters}) ->
    Update = fun
        (Old) when Old =:= Threshold ->
            SetValue;
        (Old) ->
            Old + Incr
    end,
    Counters2 = dict:update(Key, Update, SetValue, Counters),
    {ok, Val} = dict:find(Key, Counters2),
    State2 = State#state{counters=Counters2},
    {ok, Val, State2};
update_counter(Key, Incr, State=#state{counters=Counters}) ->
    Counters2 = dict:update_counter(Key, Incr, Counters),
    {ok, Val} = dict:find(Key, Counters2),
    State2 = State#state{counters=Counters2},
    {ok, Val, State2}.

%% @private
reply_to_queue(Reply, Queue) ->
    case queue:out(Queue) of
        {{value, ignore}, Queue2} ->
            reply_to_queue(Reply, Queue2);
        {{value, From}, Queue2} ->
            gen_fsm:reply(From, Reply),
            reply_to_queue(Reply, Queue2);
        {empty, Queue} ->
            ok
    end.

%% @private
new_future(State=#state{futures=Futures}, FutureKey, From) ->
    Queue = queue:new(),
    Queue2 = case From of
        undefined ->
            Queue;
        _ ->
            queue:in(From, Queue)
    end,
    Futures2 = dict:store(FutureKey, {undefined, erlang:now(), undefined, Queue2}, Futures),
    State2 = State#state{futures=Futures2},
    {ok, State2}.

%% @private
signal_future(State=#state{futures=Futures}, FutureKey, Value) ->
    case dict:find(FutureKey, Futures) of
        {ok, {undefined, Start, undefined, Queue}} ->
            Stop = erlang:now(),
            Future = {Value, Start, Stop, Queue},
            case queue:is_empty(Queue) of
                true ->
                    Futures2 = dict:store(FutureKey, Future, Futures),
                    State2 = State#state{futures=Futures2},
                    {ok, State2};
                false ->
                    Futures2 = dict:erase(FutureKey, Futures),
                    State2 = State#state{futures=Futures2},
                    Reply = {ok, Value, timer:now_diff(Stop, Start)},
                    ok = reply_to_queue(Reply, Queue),
                    {ok, State2}
            end;
        error ->
            {ok, State}
    end.
