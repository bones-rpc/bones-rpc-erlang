%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :  02 Aug 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_client).
-behaviour(gen_fsm).

-include("bones_rpc.hrl").

%% API
-export([start_link/1]).
-export([cast/2, send/2, send/3, join/2, join/3, sync_send/2, sync_send/3, get_state/1, shutdown/1]).

%% gen_fsm callbacks
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3,
         terminate/3, code_change/4]).

-export([connecting/2, connecting/3, synchronizing/2, synchronizing/3,
         idle/2, idle/3]).

-record(state, {
    %% Client
    client = undefined :: undefined | bones_rpc:client(),

    %% Connection
    socket   = undefined :: undefined | inet:socket(),
    messages = undefined :: undefined | {atom(), atom(), atom()},
    buffer   = <<>>      :: binary(),

    %% Adapter State
    a_state = undefined :: undefined | any(),

    %% Counter State
    synack_id = 0 :: integer(),

    %% Reconnect State
    reconnect_count = 0 :: non_neg_integer(),
    reconnect_wait  = 0 :: timeout(),

    %% Session State
    session = undefined :: undefined | any()
}).

%%%===================================================================
%%% API
%%%===================================================================

-spec start_link(bones_rpc:client())
    -> {ok, pid()} | ignore | {error, term()}.
start_link(Client=#bones_rpc_client_v1{}) ->
    gen_fsm:start_link(?MODULE, Client, []).

cast(Pid, Message) ->
    gen_fsm:send_event(Pid, {cast, Message}).

send(Pid, Message) ->
    gen_fsm:sync_send_event(Pid, {send, Message}).

send(Pid, Message, Timeout) ->
    gen_fsm:sync_send_event(Pid, {send, Message}, Timeout).

join(Pid, FutureKey) ->
    gen_fsm:sync_send_event(Pid, {join, FutureKey}).

join(Pid, FutureKey, Timeout) ->
    gen_fsm:sync_send_event(Pid, {join, FutureKey}, Timeout).

sync_send(Pid, Message) ->
    gen_fsm:sync_send_event(Pid, {sync_send, Message}).

sync_send(Pid, Message, Timeout) ->
    gen_fsm:sync_send_event(Pid, {sync_send, Message}, Timeout).

get_state(Pid) ->
    gen_fsm:sync_send_all_state_event(Pid, get_state).

shutdown(Pid) ->
    gen_fsm:send_all_state_event(Pid, shutdown).

%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

%% @private
init(Client=#bones_rpc_client_v1{transport=Transport, session_module=SessionModule, adapter=Adapter}) ->
    case bones_rpc_adapter:start(Adapter) of
        {ok, AdapterState} ->
            case SessionModule:init(Client) of
                {ok, Session} ->
                    State = #state{client=Client, messages=Transport:messages(),
                        a_state=AdapterState, session=Session},
                    case try_connect(State) of
                        {next_state, NextState, State2} ->
                            {ok, NextState, State2};
                        {next_state, NextState, State2, Timeout} ->
                            {ok, NextState, State2, Timeout}
                    end;
                {shutdown, Reason} ->
                    {stop, Reason}
            end;
        AdapterError ->
            {stop, {error, {adapter, AdapterError}}}
    end.

%% @private
handle_event(shutdown, _StateName, StateData) ->
    {stop, normal, StateData};
handle_event(Event, _StateName, StateData) ->
    {stop, {error, badevent, Event}, StateData}.

%% @private
handle_sync_event(get_state, _From, StateName, StateData) ->
    {reply, {StateName, StateData}, StateName, StateData};
handle_sync_event(Event, _From, _StateName, StateData) ->
    {stop, {error, badevent, Event}, StateData}.

%% @private
handle_info({OK, Socket, Data}, StateName, State=#state{socket=Socket,
        messages={OK, _Closed, _Error}, buffer=SoFar}) ->
    parse_data(State, StateName, << SoFar/binary, Data/binary >>);
handle_info({Closed, Socket}, _StateName, State=#state{socket=Socket,
        messages={_OK, Closed, _Error}, client=#bones_rpc_client_v1{reconnect=false}}) ->
    {stop, {error, closed}, State};
handle_info({Closed, Socket}, _StateName, State=#state{socket=Socket,
        messages={_OK, Closed, _Error}, client=#bones_rpc_client_v1{reconnect=true}}) ->
    {next_state, connecting, State, 0};
handle_info({Error, Socket, Reason}, _StateName, State=#state{socket=Socket,
        messages={_OK, _Closed, Error}, client=#bones_rpc_client_v1{reconnect=false}}) ->
    {stop, {error, {Error, Reason}}, State};
handle_info({Error, Socket, _Reason}, _StateName, State=#state{socket=Socket,
        messages={_OK, _Closed, Error}, client=#bones_rpc_client_v1{reconnect=true}}) ->
    {next_state, connecting, State, 0};
handle_info(Info, _StateName, StateData) ->
    {stop, {error, badmsg, Info}, StateData}.

%% @private
terminate(Reason, _StateName, #state{a_state=AState, session=Session, client=Client=
        #bones_rpc_client_v1{session_module=SessionModule}}) ->
    catch SessionModule:terminate(Reason, Client, Session),
    catch bones_rpc_adapter:stop(AState),
    ok;
terminate(_Reason, _StateName, _StateData) ->
    ok.

%% @private
code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.

%% @private
connecting(timeout, State=#state{client=#bones_rpc_client_v1{reconnect=false}}) ->
    {stop, {reconnect, false}, State};
connecting(timeout, State=#state{reconnect_count=Limit,
        client=#bones_rpc_client_v1{reconnect_limit=Limit}}) ->
    {stop, {reconnect_limit, Limit}, State};
connecting(timeout, State) ->
    reconnect(none, State);
connecting(_Event, State) ->
    {next_state, connecting, State, 0}.

%% @private
connecting(_Event, _From, State=#state{client=#bones_rpc_client_v1{reconnect=false}}) ->
    Error = {reconnect, false},
    {stop, Error, {error, Error}, State};
connecting(_Event, _From, State=#state{reconnect_count=Limit,
        client=#bones_rpc_client_v1{reconnect_limit=Limit}}) ->
    Error = {reconnect_limit, Limit},
    {stop, Error, {error, Error}, State};
connecting(_Event, From, State) ->
    reconnect(From, State).

%% @private
synchronizing(_Event, State) ->
    {next_state, synchronizing, State}.

%% @private
synchronizing(_Event, _From, State) ->
    {reply, {error, no_connection}, synchronizing, State}.

%% @private
idle({cast, Message}, State=#state{session=Session, client=Client=
        #bones_rpc_client_v1{session_module=SessionModule}}) ->
    case SessionModule:handle_send(Message, ignore, Client, Session) of
        {send, Object, Session2} ->
            case send_object(State#state{session=Session2}, Object) of
                {ok, State2} ->
                    {next_state, idle, State2};
                {error, _Error={socket, _}, State2} ->
                    {next_state, connecting, State2, 0};
                {error, _Error, State2} ->
                    {next_state, idle, State2}
            end;
        {send, Object, _FutureKey, Session2} ->
            case send_object(State#state{session=Session2}, Object) of
                {ok, State2} ->
                    {next_state, idle, State2};
                {error, _Error={socket, _}, State2} ->
                    {next_state, connecting, State2, 0};
                {error, _Error, State2} ->
                    {next_state, idle, State2}
            end;
        {ignore, Session2} ->
            {next_state, idle, State#state{session=Session2}};
        {shutdown, Reason, Session2} ->
            {stop, Reason, State#state{session=Session2}}
    end;
idle(_Event, State) ->
    {next_state, idle, State}.

%% @private
idle({join, FutureKey}, From, State=#state{session=Session, client=Client=
        #bones_rpc_client_v1{session_module=SessionModule}}) ->
    case SessionModule:handle_join(FutureKey, From, Client, Session) of
        {reply, Reply, Session2} ->
            {reply, Reply, idle, State#state{session=Session2}};
        {noreply, Session2} ->
            {next_state, idle, State#state{session=Session2}};
        {shutdown, Reason, Session2} ->
            {stop, Reason, {error, Reason}, State#state{session=Session2}}
    end;
idle({send, Message}, _From, State=#state{session=Session, client=Client=
        #bones_rpc_client_v1{session_module=SessionModule}}) ->
    case SessionModule:handle_send(Message, undefined, Client, Session) of
        {send, Object, Session2} ->
            case send_object(State#state{session=Session2}, Object) of
                {ok, State2} ->
                    {reply, ok, idle, State2};
                {error, Error={socket, _}, State2} ->
                    {reply, {error, Error}, connecting, State2, 0};
                {error, Error, State2} ->
                    {reply, {error, Error}, idle, State2}
            end;
        {send, Object, FutureKey, Session2} ->
            case send_object(State#state{session=Session2}, Object) of
                {ok, State2} ->
                    {reply, {ok, FutureKey}, idle, State2};
                {error, Error={socket, _}, State2} ->
                    {reply, {error, Error}, connecting, State2, 0};
                {error, Error, State2} ->
                    {reply, {error, Error}, idle, State2}
            end;
        {ignore, Session2} ->
            {reply, ignore, idle, State#state{session=Session2}};
        {shutdown, Reason, Session2} ->
            {stop, Reason, {error, Reason}, State#state{session=Session2}}
    end;
idle({sync_send, Message}, From, State=#state{session=Session, client=Client=
        #bones_rpc_client_v1{session_module=SessionModule}}) ->
    case SessionModule:handle_send(Message, From, Client, Session) of
        {send, Object, Session2} ->
            case send_object(State#state{session=Session2}, Object) of
                {ok, State2} ->
                    {reply, ok, idle, State2};
                {error, Error={socket, _}, State2} ->
                    {reply, {error, Error}, connecting, State2, 0};
                {error, Error, State2} ->
                    {reply, {error, Error}, idle, State2}
            end;
        {send, Object, _FutureKey, Session2} ->
            case send_object(State#state{session=Session2}, Object) of
                {ok, State2} ->
                    {next_state, idle, State2};
                {error, Error={socket, _}, State2} ->
                    {reply, {error, Error}, connecting, State2, 0};
                {error, Error, State2} ->
                    {reply, {error, Error}, idle, State2}
            end;
        {ignore, Session2} ->
            {reply, ignore, idle, State#state{session=Session2}};
        {shutdown, Reason, Session2} ->
            {stop, Reason, {error, Reason}, State#state{session=Session2}}
    end;
idle(_Event, _From, State) ->
    {reply, {error, badevent}, idle, State}.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

%% Connection

%% @private
try_connect(State=#state{socket=OldSocket, reconnect_count=Count,
        client=#bones_rpc_client_v1{host=Host, port=Port, debug=Debug,
            transport=Transport, transport_opts=TransportOpts}}) ->
    _ = case OldSocket of
        undefined -> ok;
        _         -> (catch Transport:close(OldSocket))
    end,
    case Transport:connect(Host, Port, TransportOpts) of
        {ok, Socket} ->
            Transport:controlling_process(Socket, self()),
            ok = Transport:setopts(Socket, [{active, once}]),
            try_synchronize(State#state{socket=Socket, reconnect_count=0, reconnect_wait=0});
        {E, Reason} when E == error; E == exception ->
            Wait = reconnect_wait(State),
            case Debug of
                true ->
                    error_logger:warning_msg("[~w] ~w connect failed (~w), trying again in ~w ms~n",
                        [self(), ?MODULE, Reason, Wait]);
                _ ->
                    ok
            end,
            State2 = State#state{socket=undefined, reconnect_count=Count+1, reconnect_wait=Wait},
            {next_state, connecting, State2, Wait}
    end.

%% @private
try_synchronize(State=#state{client=#bones_rpc_client_v1{adapter=Adapter}}) ->
    {ok, SynackId, State2} = next_synack_id(State),
    AdapterName = Adapter:name(),
    {ok, Synchronize} = bones_rpc_factory:build({synchronize, SynackId, AdapterName}),
    case send_object(State2, Synchronize) of
        {ok, State3} ->
            {next_state, synchronizing, State3};
        {error, _Error, State3} ->
            Wait = reconnect_wait(State3),
            {next_state, connecting, State3#state{reconnect_wait=Wait}, Wait}
    end.

%% @private
reconnect(none, State) ->
    try_connect(State);
reconnect(From, State) when From =/= none ->
    case try_connect(State) of
        {next_state, NextState, State2, Timeout} ->
            {reply, {error, no_connection}, NextState, State2, Timeout}
    end.

%% @private
reconnect_wait(#state{client=#bones_rpc_client_v1{reconnect_min=Min}, reconnect_wait=0}) ->
    Min;
reconnect_wait(#state{client=#bones_rpc_client_v1{reconnect_max=Max}, reconnect_wait=Max}) ->
    Max;
reconnect_wait(#state{client=#bones_rpc_client_v1{reconnect_max=Max}, reconnect_wait=R}) ->
    Backoff = 2 * R,
    case Backoff > Max of
        true  -> Max;
        false -> Backoff
    end.

%% @private
next_synack_id(State=#state{synack_id=SynackId})
        when SynackId >= 16#fffffffe -> %% (1 bsl 32) - 2
    {ok, 0, State#state{synack_id=0}};
next_synack_id(State=#state{synack_id=SynackId}) ->
    SynackId2 = SynackId + 1,
    {ok, SynackId2, State#state{synack_id=SynackId2}}.

%% Parsing/Sending

%% @private
send_object(State=#state{socket=Socket, a_state=AState, client=#bones_rpc_client_v1{transport=Transport}}, Object) ->
    try
        case bones_rpc_adapter:pack(Object, AState) of
            Packet when is_binary(Packet) ->
                case Transport:send(Socket, Packet) of
                    ok ->
                        {ok, State};
                    {error, SocketReason} ->
                        erlang:error({socket, SocketReason})
                end;
            {error, AdapterReason} ->
                erlang:error({adapter, AdapterReason})
        end
    catch
        Class:Reason ->
            error_logger:error_msg(
                "** ~p ~p non-fatal error in ~p/~p~n"
                "   for the reason ~p:~p~n** Stacktrace: ~p~n~n",
                [?MODULE, self(), send, 2, Class, Reason, erlang:get_stacktrace()]),
            {error, Reason, State}
    end.

%% @private
parse_data(State=#state{socket=Socket, synack_id=SynackId, a_state=AState,
        session=Session, client=Client=#bones_rpc_client_v1{transport=Transport,
            session_module=SessionModule}}, synchronizing, Data) ->
    case bones_rpc_adapter:unpack_stream(Data, AState) of
        {#bones_rpc_ext_v1{head=?BONES_RPC_EXT_ACKNOWLEDGE, data = << SynackId:4/big-unsigned-integer-unit:8, 16#C2 >>}, _RemainingData} ->
            {stop, {error, adapter_not_supported}, State};
        {#bones_rpc_ext_v1{head=?BONES_RPC_EXT_ACKNOWLEDGE, data = << SynackId:4/big-unsigned-integer-unit:8, 16#C3 >>}, RemainingData} ->
            case SessionModule:handle_up(Client, Session) of
                {ok, Session2} ->
                    parse_data(State#state{session=Session2}, idle, RemainingData);
                {shutdown, Reason, Session2} ->
                    {stop, Reason, State#state{session=Session2}}
            end;
        {error, incomplete} ->
            %% Need more data.
            ok = Transport:setopts(Socket, [{active, once}]),
            {next_state, synchronizing, State#state{buffer=Data}};
        {error, _} = Error ->
            {stop, Error, State}
    end;
parse_data(State=#state{socket=Socket, a_state=AState, session=Session,
        client=Client=#bones_rpc_client_v1{transport=Transport,
            session_module=SessionModule}}, StateName, Data) ->
    case bones_rpc_adapter:unpack_stream(Data, AState) of
        {Message, RemainingData} when Message =/= error ->
            case SessionModule:handle_recv(Message, Client, Session) of
                {ok, Session2} ->
                    parse_data(State#state{session=Session2}, StateName, RemainingData);
                {shutdown, Reason, Session2} ->
                    {stop, Reason, State#state{session=Session2}}
            end;
        {error, incomplete} ->
            %% Need more data.
            ok = Transport:setopts(Socket, [{active, once}]),
            {next_state, StateName, State#state{buffer=Data}};
        {error, _} = Error ->
            {stop, Error, State}
    end.
