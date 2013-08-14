#!/usr/bin/env escript
%%! -smp enable -pa ebin -env ERL_LIBS apps:deps -input -sname bones_rpc_simple
-module(simple_handler).
-mode(compile).
-behaviour(bones_rpc_handler).

%% API
-export([main/1]).

%% bones_rpc_handler callbacks
-export([bones_rpc_init/2,
         bones_rpc_synchronize/3,
         bones_rpc_request/3,
         bones_rpc_notify/2,
         bones_rpc_info/2,
         bones_rpc_terminate/3]).

%%%===================================================================
%%% API functions
%%%===================================================================

main(_) ->
    Port = 18800,
    ok = application:start(sasl),
    ok = application:start(crypto),
    ok = application:start(ranch),
    ok = application:start(bones_rpc),

    io:format(" [*] Running at localhost:~p~n", [Port]),

    bones_rpc:start_listener(bones_rpc_simple_handler, 4, ranch_tcp, [{port, Port}], [], simple_handler, []),
    % shell:start(),

    receive
        _ -> ok
    end.

%%%===================================================================
%%% bones_rpc_handler callbacks
%%%===================================================================

bones_rpc_init(_Type, _Opts) ->
    {ok, undefined}.

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
    io:format("REQUEST: ~p~n", [Request]),
    {reply, {result, true}, State}.

bones_rpc_notify(Notify, State) ->
    io:format("NOTIFY: ~p~n", [Notify]),
    {noreply, State}.

bones_rpc_info(_Info, State) ->
    {noreply, State}.

bones_rpc_terminate(_Reason, _Req, _State) ->
    ok.
