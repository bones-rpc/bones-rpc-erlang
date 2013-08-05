-module(adapter_server).
-behaviour(bones_rpc_handler).

%% API
-export([start_listener/1, start_listener/6, stop_listener/1, get_port/1, connect/2]).

%% bones_rpc_handler callbacks
-export([bones_rpc_init/2,
         bones_rpc_synchronize/3,
         bones_rpc_request/3,
         bones_rpc_notify/2,
         bones_rpc_info/2,
         bones_rpc_terminate/3]).

-record(state, {
    name = undefined :: undefined | ranch:ref()
}).

%%%===================================================================
%%% API functions
%%%===================================================================

start_listener(Ref) ->
    start_listener(Ref, 4, ranch_tcp, [], [], []).

start_listener(Ref, NbAcceptors, Transport, TransOpts, Options, HandlerOpts) ->
    TransOpts2 = [{port, 0} | TransOpts],
    HandlerOpts2 = [{name, Ref} | HandlerOpts],
    bones_rpc:start_listener(Ref, NbAcceptors, Transport, TransOpts2, Options, ?MODULE, HandlerOpts2).

stop_listener(Ref) ->
    bones_rpc:stop_listener(Ref).

get_port(Ref) ->
    ranch:get_port(Ref).

connect(Ref, Options) ->
    ClientSpec = {Ref,
        {bones_rpc, connect, [{127,0,0,1}, get_port(Ref), Options]},
        transient, brutal_kill, worker, [bones_rpc_client]},
    ct:log("client spec: ~p", [ClientSpec]),
    supervisor:start_child(bones_rpc_sup, ClientSpec).

%%%===================================================================
%%% bones_rpc_handler callbacks
%%%===================================================================

bones_rpc_init(_Type, Options) ->
    Name = proplists:get_value(name, Options),
    State = #state{name=Name},
    {ok, State}.

bones_rpc_synchronize({_MsgID, <<"erlang">>}, _From, State) ->
    {reply, {true, bones_erlang}, State};
bones_rpc_synchronize({_MsgID, <<"json">>}, _From, State) ->
    {reply, {true, bones_json}, State};
bones_rpc_synchronize({_MsgID, <<"msgpack">>}, _From, State) ->
    {reply, {true, bones_msgpack}, State};
bones_rpc_synchronize({_MsgID, _AdapterName}, _From, State) ->
    {reply, false, State}.

bones_rpc_request({_, <<"fail">>, Params}, _From, State) ->
    {reply, {error, Params}, State};
bones_rpc_request({_, <<"echo">>, Params}, _From, State) ->
    {reply, {result, Params}, State};
bones_rpc_request({_, <<"sleep">>, [N]}, From, State) ->
    spawn(fun() ->
        timer:sleep(N),
        bones_rpc:reply(From, {result, N})
    end),
    {noreply, State};
bones_rpc_request({_, <<"sum">>, Nums}, From, State) ->
    spawn(fun() ->
        try
            bones_rpc:reply(From, {result, lists:sum(Nums)})
        catch
            _:_ ->
                bones_rpc:reply(From, {error, <<"unable to sum">>})
        end
    end),
    {noreply, State};
bones_rpc_request(Request, _, State) ->
    io:format("UNKNOWN REQUEST: ~p~n", [Request]),
    {reply, {result, true}, State}.

bones_rpc_notify({<<"ping">>, [Binary, N]}, State) when is_binary(Binary) ->
    Pid = erlang:binary_to_term(Binary),
    Pid ! {pong, N},
    {noreply, State};
bones_rpc_notify({<<"ping">>, [List, N]}, State) when is_list(List) -> %% json doesn't handle straight binary
    bones_rpc_notify({<<"ping">>, [erlang:list_to_binary(List), N]}, State);
bones_rpc_notify(Notify, State) ->
    io:format("UNKNOWN NOTIFY: ~p~n", [Notify]),
    {noreply, State}.

bones_rpc_info(_Info, State) ->
    {noreply, State}.

bones_rpc_terminate(_Reason, _Req, _State) ->
    ok.
