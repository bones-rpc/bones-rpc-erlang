%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :  18 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------

-module(bones_rpc_dispatcher).

%% API
-export([dispatch_init/3,
         dispatch_message/2,
         dispatch_terminate/3]).

-record(state, {
    type = undefined :: undefined | {atom(), bones_rpc},

    %% Handler.
    handler       = undefined :: undefined | module(),
    handler_opts  = undefined :: undefined | any(),
    handler_state = undefined :: undefined | any()
}).

%%%===================================================================
%%% API functions
%%%===================================================================

-spec dispatch_init({atom(), bones_rpc}, Handler::module(), HandlerOpts::any())
    -> {ok, State}
    | {ok, State, hibernate}
    | {ok, State, timeout()}
    | {ok, State, timeout(), hibernate}
    | {shutdown, Reason::term(), State}.
dispatch_init(_Type, undefined, _HandlerOpts) ->
    erlang:error(no_handler_defined);
dispatch_init(Type, Handler, HandlerOpts) ->
    handler_init(#state{type=Type, handler=Handler, handler_opts=HandlerOpts}).

-spec dispatch_message(Request::bones_rpc:request(), State::any())
    -> {ok, State}
    | {ok, State, hibernate}
    | {ok, State, timeout()}
    | {ok, State, timeout(), hibernate}
    | {shutdown, Reason::term(), State}.
dispatch_message({'$bones_rpc_info', Info}, State) ->
    handler_cast(State, bones_rpc_info, Info);
dispatch_message({synchronize, MsgID, Adapter}, State) ->
    Message = {MsgID, Adapter},
    From = {self(), {synack, MsgID}},
    handler_call(State, bones_rpc_synchronize, From, Message);
dispatch_message({request, MsgID, Method, Params}, State) ->
    Message = {MsgID, Method, Params},
    From = {self(), {request, MsgID}},
    handler_call(State, bones_rpc_request, From, Message);
dispatch_message({notify, Method, Params}, State) ->
    Message = {Method, Params},
    handler_cast(State, bones_rpc_notify, Message).

-spec dispatch_terminate(Reason::term(), Message :: undefined | bones_rpc:request() | bones_rpc:notify(), State::any())
    -> term().
dispatch_terminate(TerminateReason, Req, State) ->
    handler_terminate(State, Req, TerminateReason).

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

%% @private
handler_init(State=#state{type=Type, handler=Handler, handler_opts=HandlerOpts}) ->
    case Handler:bones_rpc_init(Type, HandlerOpts) of
        {ok, HandlerState} ->
            {ok, State#state{handler_state=HandlerState}};
        {ok, HandlerState, hibernate} ->
            {ok, State#state{handler_state=HandlerState}, hibernate};
        {ok, HandlerState, Timeout} ->
            {ok, State#state{handler_state=HandlerState}, Timeout};
        {ok, HandlerState, Timeout, hibernate} ->
            {ok, State#state{handler_state=HandlerState}, Timeout, hibernate};
        {shutdown, Reason, HandlerState} ->
            {shutdown, Reason, State#state{handler_state=HandlerState}}
    end.

%% @private
handler_call(State=#state{handler=Handler, handler_opts=_HandlerOpts, handler_state=HandlerState}, Callback, From, Req) ->
    case Handler:Callback(Req, From, HandlerState) of
        {noreply, HandlerState2} ->
            {ok, State#state{handler_state=HandlerState2}};
        {noreply, HandlerState2, hibernate} ->
            {ok, State#state{handler_state=HandlerState2}, hibernate};
        {noreply, HandlerState2, Timeout} ->
            {ok, State#state{handler_state=HandlerState2}, Timeout};
        {noreply, HandlerState2, Timeout, hibernate} ->
            {ok, State#state{handler_state=HandlerState2}, Timeout, hibernate};
        {shutdown, Reason, HandlerState2} ->
            {shutdown, Reason, State#state{handler_state=HandlerState2}};
        {reply, Reply, HandlerState2} ->
            ok = check_reply(Callback, Reply),
            bones_rpc:reply(From, Reply),
            {ok, State#state{handler_state=HandlerState2}};
        {reply, Reply, HandlerState2, hibernate} ->
            ok = check_reply(Callback, Reply),
            bones_rpc:reply(From, Reply),
            {ok, State#state{handler_state=HandlerState2}, hibernate};
        {reply, Reply, HandlerState2, Timeout} ->
            ok = check_reply(Callback, Reply),
            bones_rpc:reply(From, Reply),
            {ok, State#state{handler_state=HandlerState2}, Timeout};
        {reply, Reply, HandlerState2, Timeout, hibernate} ->
            ok = check_reply(Callback, Reply),
            bones_rpc:reply(From, Reply),
            {ok, State#state{handler_state=HandlerState2}, Timeout, hibernate}
    end.

%% @private
check_reply(bones_rpc_synchronize, {true, Adapter}) when is_atom(Adapter) ->
    ok;
check_reply(bones_rpc_synchronize, false) ->
    ok;
check_reply(bones_rpc_request, {Type, _}) when Type =:= result orelse Type =:= error ->
    ok.

%% @private
handler_cast(State=#state{handler=Handler, handler_opts=_HandlerOpts, handler_state=HandlerState}, Callback, Req) ->
    case Handler:Callback(Req, HandlerState) of
        {noreply, HandlerState2} ->
            {ok, State#state{handler_state=HandlerState2}};
        {noreply, HandlerState2, hibernate} ->
            {ok, State#state{handler_state=HandlerState2}, hibernate};
        {noreply, HandlerState2, Timeout} ->
            {ok, State#state{handler_state=HandlerState2}, Timeout};
        {noreply, HandlerState2, Timeout, hibernate} ->
            {ok, State#state{handler_state=HandlerState2}, Timeout, hibernate};
        {shutdown, Reason, HandlerState2} ->
            {shutdown, Reason, State#state{handler_state=HandlerState2}}
    end.

%% @private
handler_terminate(#state{handler=Handler, handler_opts=_HandlerOpts, handler_state=HandlerState}, Req, Reason) ->
    Handler:bones_rpc_terminate(Reason, Req, HandlerState).
