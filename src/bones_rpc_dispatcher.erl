%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :  18 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------

-module(bones_rpc_dispatcher).

% -callback dispatch_init({atom(), bones_rpc}, Handler::module(), HandlerOpts::any())
%     -> {ok, State}
%     | {ok, State, hibernate}
%     | {ok, State, timeout()}
%     | {ok, State, timeout(), hibernate}
%     | {shutdown, Reason::term(), State}.
% -callback dispatch_request(Request::bones_rpc:request(), State::any())
%     -> {ok, State}
%     | {ok, State, hibernate}
%     | {ok, State, timeout()}
%     | {ok, State, timeout(), hibernate}
%     | {shutdown, Reason::term(), State}.
% -callback dispatch_notify(Notify::bones_rpc:notify(), State::any())
%     -> {ok, State}
%     | {ok, State, hibernate}
%     | {ok, State, timeout()}
%     | {ok, State, timeout(), hibernate}
%     | {shutdown, Reason::term(), State}.
% -callback dispatch_info(Info::term(), State::any())
%     -> {ok, State}
%     | {ok, State, hibernate}
%     | {ok, State, timeout()}
%     | {ok, State, timeout(), hibernate}
%     | {shutdown, Reason::term(), State}.
% -callback dispatch_terminate(Reason::term(), Message :: undefined | bones_rpc:request() | bones_rpc:notify(), State::any())
%     -> term().

%% bones_rpc_dispatcher callbacks
-export([dispatch_init/3,
         dispatch_request/2,
         dispatch_notify/2,
         dispatch_info/2,
         dispatch_terminate/3]).

-record(state, {
    type = undefined :: undefined | {atom(), bones_rpc},

    %% Handler.
    handler       = undefined :: undefined | module(),
    handler_opts  = undefined :: undefined | any(),
    handler_state = undefined :: undefined | any()
}).

%%%===================================================================
%%% bones_rpc_dispatcher callbacks
%%%===================================================================

dispatch_init(_Type, undefined, _HandlerOpts) ->
    erlang:error(no_handler_defined);
dispatch_init(Type, Handler, HandlerOpts) ->
    handler_init(#state{type=Type, handler=Handler, handler_opts=HandlerOpts}).

dispatch_request({request, MsgID, Method, Params}, State) ->
    Req = {MsgID, Method, Params},
    From = {self(), MsgID},
    handler_request(State, bones_rpc_request, From, Req).

dispatch_notify({notify, Method, Params}, State) ->
    Req = {Method, Params},
    handler_notify(State, bones_rpc_notify, Req).

dispatch_info(Info, State) ->
    handler_info(State, bones_rpc_info, Info).

dispatch_terminate(TerminateReason, Req, State) ->
    handler_terminate(State, Req, TerminateReason).

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

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

handler_request(State=#state{handler=Handler, handler_opts=_HandlerOpts, handler_state=HandlerState}, Callback, From, Req) ->
    case Handler:Callback(Req, From, HandlerState) of
        {noreply, HandlerState2} ->
            {ok, State#state{handler_state=HandlerState2}};
        {noreply, HandlerState2, hibernate} ->
            {ok, State#state{handler_state=HandlerState2}, hibernate};
        {noreply, HandlerState2, Timeout} ->
            {ok, State#state{handler_state=HandlerState2}, Timeout};
        {noreply, HandlerState2, Timeout, hibernate} ->
            {ok, State#state{handler_state=HandlerState2}, Timeout, hibernate};
        {reply, Reply={Type, _}, HandlerState2} when Type =:= result orelse Type =:= error ->
            bones_rpc:reply(From, Reply),
            {ok, State#state{handler_state=HandlerState2}};
        {reply, Reply={Type, _}, HandlerState2, hibernate} when Type =:= result orelse Type =:= error ->
            bones_rpc:reply(From, Reply),
            {ok, State#state{handler_state=HandlerState2}, hibernate};
        {reply, Reply={Type, _}, HandlerState2, Timeout} when Type =:= result orelse Type =:= error ->
            bones_rpc:reply(From, Reply),
            {ok, State#state{handler_state=HandlerState2}, Timeout};
        {reply, Reply={Type, _}, HandlerState2, Timeout, hibernate} when Type =:= result orelse Type =:= error ->
            bones_rpc:reply(From, Reply),
            {ok, State#state{handler_state=HandlerState2}, Timeout, hibernate};
        {shutdown, Reason, HandlerState2} ->
            {shutdown, Reason, State#state{handler_state=HandlerState2}}
    end.

handler_notify(State=#state{handler=Handler, handler_opts=_HandlerOpts, handler_state=HandlerState}, Callback, Req) ->
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

handler_info(State=#state{handler=Handler, handler_opts=_HandlerOpts, handler_state=HandlerState}, Callback, Info) ->
    case Handler:Callback(Info, HandlerState) of
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

handler_terminate(#state{handler=Handler, handler_opts=_HandlerOpts, handler_state=HandlerState}, Req, Reason) ->
    Handler:bones_rpc_terminate(Reason, Req, HandlerState).
