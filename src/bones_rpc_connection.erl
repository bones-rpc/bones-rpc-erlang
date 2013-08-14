%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :  02 Aug 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_connection).
-behaviour(gen_fsm).

-include("bones_rpc.hrl").
-include("bones_rpc_internal.hrl").

%% API
-export([start_link/1]).

%% gen_fsm callbacks
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3,
         terminate/3, code_change/4]).

-export([connecting/2, connecting/3, synchronizing/2, synchronizing/3,
         idle/2, idle/3]).

%%%===================================================================
%%% API
%%%===================================================================

% -spec start_link(bones_rpc:client())
%     -> {ok, pid()} | ignore | {error, term()}.
start_link(Conn=#conn{ref=undefined}) ->
    gen_fsm:start_link(?MODULE, Conn, []);
start_link(Conn=#conn{ref=ConnRef}) ->
    gen_fsm:start_link({local, ConnRef}, ?MODULE, Conn, []).

%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

%% @private
init(Conn=#conn{adapter=Adapter, session=Session, transport=Transport}) ->
    case bones_rpc_adapter:start(Adapter) of
        {ok, AdapterState} ->
            Client = bones_rpc_client:conn_to_client(Conn),
            case Session:init(Client) of
                {ok, SessionState} ->
                    Conn2 = Conn#conn{messages=Transport:messages(),
                        adapter={Adapter, AdapterState},
                        session={Session, SessionState}},
                    case try_connect(Conn2) of
                        {next_state, NextState, Conn3} ->
                            {ok, NextState, Conn3};
                        {next_state, NextState, Conn3, Timeout} ->
                            {ok, NextState, Conn3, Timeout}
                    end;
                {shutdown, Reason} ->
                    {stop, Reason}
            end;
        AdapterError ->
            {stop, {error, {adapter, AdapterError}}}
    end.

%% @private
handle_event(shutdown, _StateName, Conn) ->
    {stop, normal, Conn};
handle_event(Event, _StateName, Conn) ->
    {stop, {error, badevent, Event}, Conn}.

%% @private
handle_sync_event(get_state, _From, StateName, Conn) ->
    {reply, {StateName, Conn}, StateName, Conn};
handle_sync_event(Event, _From, _StateName, Conn) ->
    {stop, {error, badevent, Event}, Conn}.

%% @private
handle_info({OK, Socket, Data}, StateName, Conn=#conn{socket=Socket,
        messages={OK, _Closed, _Error}, buffer=SoFar}) ->
    parse_data(Conn, StateName, << SoFar/binary, Data/binary >>);
handle_info({Closed, Socket}, _StateName, Conn=#conn{socket=Socket,
        messages={_OK, Closed, _Error}, reconnect=false}) ->
    {stop, {error, closed}, Conn};
handle_info({Closed, Socket}, _StateName, Conn=#conn{socket=Socket,
        messages={_OK, Closed, _Error}, reconnect=true}) ->
    {next_state, connecting, Conn, 0};
handle_info({Error, Socket, Reason}, _StateName, Conn=#conn{socket=Socket,
        messages={_OK, _Closed, Error}, reconnect=false}) ->
    {stop, {error, {Error, Reason}}, Conn};
handle_info({Error, Socket, _Reason}, _StateName, Conn=#conn{socket=Socket,
        messages={_OK, _Closed, Error}, reconnect=true}) ->
    {next_state, connecting, Conn, 0};
handle_info({'$bones_rpc_ring', Ring}, StateName, Conn) ->
    ok = bones_rpc_cluster_event:ring_update(Conn, Ring),
    {next_state, StateName, Conn, 0};
handle_info(Info, _StateName, Conn) ->
    {stop, {error, badmsg, Info}, Conn}.

%% @private
terminate(Reason, _StateName, #conn{adapter=Adapter, session={Session, State}}) ->
    catch Session:terminate(Reason, State),
    catch bones_rpc_adapter:stop(Adapter),
    ok;
terminate(_Reason, _StateName, _Conn) ->
    ok.

%% @private
code_change(_OldVsn, StateName, Conn, _Extra) ->
    {ok, StateName, Conn}.

%% @private
connecting(timeout, Conn=#conn{reconnect=false}) ->
    {stop, {reconnect, false}, Conn};
connecting(timeout, Conn=#conn{reconnect_count=Limit, reconnect_limit=Limit}) ->
    {stop, {reconnect_limit, Limit}, Conn};
connecting(timeout, Conn) ->
    reconnect(none, Conn);
connecting(_Event, Conn) ->
    {next_state, connecting, Conn, 0}.

%% @private
connecting(_Event, _From, Conn=#conn{reconnect=false}) ->
    Error = {reconnect, false},
    {stop, Error, {error, Error}, Conn};
connecting(_Event, _From, Conn=#conn{reconnect_count=Limit, reconnect_limit=Limit}) ->
    Error = {reconnect_limit, Limit},
    {stop, Error, {error, Error}, Conn};
connecting(_Event, From, Conn) ->
    reconnect(From, Conn).

%% @private
synchronizing(_Event, Conn) ->
    {next_state, synchronizing, Conn}.

%% @private
synchronizing(_Event, _From, Conn) ->
    {reply, {error, no_connection}, synchronizing, Conn}.

%% @private
idle({cast, Message}, Conn=#conn{session={Session, State}}) ->
    case Session:handle_send(Message, ignore, State) of
        {send, Object, State2} ->
            case send_object(Conn#conn{session={Session, State2}}, Object) of
                {ok, Conn2} ->
                    {next_state, idle, Conn2};
                {error, _Error={socket, _}, Conn2} ->
                    {next_state, connecting, Conn2, 0};
                {error, _Error, Conn2} ->
                    {next_state, idle, Conn2}
            end;
        {send, Object, _FutureKey, State2} ->
            case send_object(Conn#conn{session={Session, State2}}, Object) of
                {ok, Conn2} ->
                    {next_state, idle, Conn2};
                {error, _Error={socket, _}, Conn2} ->
                    {next_state, connecting, Conn2, 0};
                {error, _Error, Conn2} ->
                    {next_state, idle, Conn2}
            end;
        {ignore, State2} ->
            {next_state, idle, Conn#conn{session={Session, State2}}};
        {shutdown, Reason, State2} ->
            {stop, Reason, Conn#conn{session={Session, State2}}}
    end;
idle(_Event, Conn) ->
    {next_state, idle, Conn}.

%% @private
idle({join, FutureKey}, From, Conn=#conn{session={Session, State}}) ->
    case Session:handle_join(FutureKey, From, State) of
        {reply, Reply, State2} ->
            {reply, Reply, idle, Conn#conn{session={Session, State2}}};
        {noreply, State2} ->
            {next_state, idle, Conn#conn{session={Session, State2}}};
        {shutdown, Reason, State2} ->
            {stop, Reason, {error, Reason}, Conn#conn{session={Session, State2}}}
    end;
idle({send, Message}, _From, Conn=#conn{session={Session, State}}) ->
    case Session:handle_send(Message, undefined, State) of
        {send, Object, State2} ->
            case send_object(Conn#conn{session={Session, State2}}, Object) of
                {ok, Conn2} ->
                    {reply, ok, idle, Conn2};
                {error, Error={socket, _}, Conn2} ->
                    {reply, {error, Error}, connecting, Conn2, 0};
                {error, Error, Conn2} ->
                    {reply, {error, Error}, idle, Conn2}
            end;
        {send, Object, FutureKey, State2} ->
            case send_object(Conn#conn{session={Session, State2}}, Object) of
                {ok, Conn2} ->
                    {reply, {ok, FutureKey}, idle, Conn2};
                {error, Error={socket, _}, Conn2} ->
                    {reply, {error, Error}, connecting, Conn2, 0};
                {error, Error, Conn2} ->
                    {reply, {error, Error}, idle, Conn2}
            end;
        {ignore, State2} ->
            {reply, ignore, idle, Conn#conn{session={Session, State2}}};
        {shutdown, Reason, State2} ->
            {stop, Reason, {error, Reason}, Conn#conn{session={Session, State2}}}
    end;
idle({sync_send, Message}, From, Conn=#conn{session={Session, State}}) ->
    case Session:handle_send(Message, From, State) of
        {send, Object, State2} ->
            case send_object(Conn#conn{session={Session, State2}}, Object) of
                {ok, Conn2} ->
                    {reply, ok, idle, Conn2};
                {error, Error={socket, _}, Conn2} ->
                    {reply, {error, Error}, connecting, Conn2, 0};
                {error, Error, Conn2} ->
                    {reply, {error, Error}, idle, Conn2}
            end;
        {send, Object, _FutureKey, State2} ->
            case send_object(Conn#conn{session={Session, State2}}, Object) of
                {ok, Conn2} ->
                    {next_state, idle, Conn2};
                {error, Error={socket, _}, Conn2} ->
                    {reply, {error, Error}, connecting, Conn2, 0};
                {error, Error, Conn2} ->
                    {reply, {error, Error}, idle, Conn2}
            end;
        {ignore, State2} ->
            {reply, ignore, idle, Conn#conn{session={Session, State2}}};
        {shutdown, Reason, State2} ->
            {stop, Reason, {error, Reason}, Conn#conn{session={Session, State2}}}
    end;
idle(_Event, _From, Conn) ->
    {reply, {error, badevent}, idle, Conn}.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

%% Connection

%% @private
try_connect(Conn=#conn{address=#address{ip=IP, port=Port}, transport=Transport,
        transport_opts=TransportOpts, reconnect_count=Count}) ->
    case try_disconnect(Conn) of
        {ok, Conn2} ->
            case Transport:connect(IP, Port, TransportOpts) of
                {ok, Socket} ->
                    Transport:controlling_process(Socket, self()),
                    ok = Transport:setopts(Socket, [{active, once}]),
                    try_synchronize(Conn2#conn{socket=Socket, reconnect_count=0, reconnect_wait=0});
                {E, Reason} when E == error; E == exception ->
                    Wait = reconnect_wait(Conn2),
                    _ = case Conn2#conn.debug of
                        false ->
                            ok;
                        true ->
                            error_logger:warning_msg(
                                "[~w] ~w connect failed to ~s:~p (~w), trying again in ~w ms~n",
                                [self(), ?MODULE, inet_parse:ntoa(IP), Port, Reason, Wait])
                    end,
                    Conn3 = Conn2#conn{reconnect_count=Count+1, reconnect_wait=Wait},
                    {next_state, connecting, Conn3, Wait}
            end;
        {shutdown, Reason, Conn2} ->
            {stop, Reason, Conn2}
    end.

%% @private
try_disconnect(Conn=#conn{socket=undefined}) ->
    {ok, Conn};
try_disconnect(Conn=#conn{socket=Socket, transport=Transport, node=Node, session={Session, State}}) ->
    bones_rpc_node:status(Node, down),
    catch Transport:close(Socket),
    Conn2 = Conn#conn{socket=undefined},
    case Session:handle_down(State) of
        {ok, State2} ->
            {ok, Conn2#conn{session={Session, State2}}};
        {shutdown, Reason, State2} ->
            {shutdown, Reason, Conn2#conn{session={Session, State2}}}
    end.

%% @private
try_synchronize(Conn=#conn{adapter={Adapter, _State}}) ->
    {ok, SynackId, Conn2} = next_synack_id(Conn),
    AdapterName = Adapter:name(),
    {ok, Synchronize} = bones_rpc_factory:build({synchronize, SynackId, AdapterName}),
    case send_object(Conn2, Synchronize) of
        {ok, Conn3} ->
            {next_state, synchronizing, Conn3};
        {error, _Error, Conn3} ->
            Wait = reconnect_wait(Conn3),
            {next_state, connecting, Conn3#conn{reconnect_wait=Wait}, Wait}
    end.

%% @private
reconnect(none, Conn) ->
    try_connect(Conn);
reconnect(From, Conn) when From =/= none ->
    case try_connect(Conn) of
        {next_state, NextState, Conn2, Timeout} ->
            {reply, {error, no_connection}, NextState, Conn2, Timeout}
    end.

%% @private
reconnect_wait(#conn{reconnect_min=Min, reconnect_wait=0}) ->
    Min;
reconnect_wait(#conn{reconnect_max=Max, reconnect_wait=Max}) ->
    Max;
reconnect_wait(#conn{reconnect_max=Max, reconnect_wait=R}) ->
    Backoff = 2 * R,
    case Backoff > Max of
        true  -> Max;
        false -> Backoff
    end.

%% @private
next_synack_id(Conn=#conn{synack_id=SynackId})
        when SynackId >= 16#fffffffe -> %% (1 bsl 32) - 2
    {ok, 0, Conn#conn{synack_id=0}};
next_synack_id(Conn=#conn{synack_id=SynackId}) ->
    SynackId2 = SynackId + 1,
    {ok, SynackId2, Conn#conn{synack_id=SynackId2}}.

%% Parsing/Sending

%% @private
send_object(Conn=#conn{socket=Socket, adapter=Adapter, transport=Transport}, Object) ->
    try
        case bones_rpc_adapter:pack(Object, Adapter) of
            Packet when is_binary(Packet) ->
                case Transport:send(Socket, Packet) of
                    ok ->
                        {ok, Conn};
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
            {error, Reason, Conn}
    end.

%% @private
parse_data(Conn=#conn{socket=Socket, synack_id=SynackId, adapter=Adapter, session={Session, State}, transport=Transport, node=Node}, synchronizing, Data) ->
    case bones_rpc_adapter:unpack_stream(Data, Adapter) of
        {#bones_rpc_ext_v1{head=?BONES_RPC_EXT_ACKNOWLEDGE, data = << SynackId:4/big-unsigned-integer-unit:8, 16#C2 >>}, _RemainingData} ->
            {stop, {error, adapter_not_supported}, State};
        {#bones_rpc_ext_v1{head=?BONES_RPC_EXT_ACKNOWLEDGE, data = << SynackId:4/big-unsigned-integer-unit:8, 16#C3 >>}, RemainingData} ->
            case Session:handle_up(State) of
                {ok, State2} ->
                    bones_rpc_node:status(Node, up),
                    parse_data(Conn#conn{session={Session, State2}}, idle, RemainingData);
                {shutdown, Reason, State2} ->
                    {stop, Reason, Conn#conn{session={Session, State2}}}
            end;
        {#bones_rpc_ext_v1{head=?BONES_RPC_EXT_RING, data=RingData}, RemainingData} ->
            case bones_rpc_ring_v1:from_binary(RingData) of
                Ring=#bones_rpc_ring_v1{} ->
                    ok = bones_rpc_cluster_event:ring_update(Conn, Ring),
                    parse_data(Conn, synchronizing, RemainingData);
                _ ->
                    parse_data(Conn, synchronizing, RemainingData)
            end;
        {error, incomplete} ->
            %% Need more data.
            ok = Transport:setopts(Socket, [{active, once}]),
            {next_state, synchronizing, Conn#conn{buffer=Data}};
        {error, _} = Error ->
            {stop, Error, Conn}
    end;
parse_data(Conn=#conn{socket=Socket, adapter=Adapter, session={Session, State}, transport=Transport}, StateName, Data) ->
    case bones_rpc_adapter:unpack_stream(Data, Adapter) of
        {Message, RemainingData} when Message =/= error ->
            case Session:handle_recv(Message, State) of
                {ok, State2} ->
                    parse_data(Conn#conn{session={Session, State2}}, StateName, RemainingData);
                {shutdown, Reason, State2} ->
                    {stop, Reason, Conn#conn{session={Session, State2}}}
            end;
        {error, incomplete} ->
            %% Need more data.
            ok = Transport:setopts(Socket, [{active, once}]),
            {next_state, StateName, Conn#conn{buffer=Data}};
        {error, _} = Error ->
            {stop, Error, Conn}
    end.
