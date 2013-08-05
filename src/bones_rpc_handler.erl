%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :  31 May 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------

-module(bones_rpc_handler).

-type req() :: {bones_rpc:msg_id(), bones_rpc:method(), bones_rpc:params()} | {bones_rpc:method(), bones_rpc:params()}.

-callback bones_rpc_init({atom(), bones_rpc}, HandlerOpts::any())
    -> {ok, State}
    | {ok, State, hibernate}
    | {ok, State, timeout()}
    | {ok, State, timeout(), hibernate}
    | {shutdown, Reason::any(), State}.
-callback bones_rpc_synchronize({bones_rpc:msg_id(), bones_rpc:adapter()},
        From::{pid(), {synack, bones_rpc:msg_id()}}, State::any())
    -> {noreply, State}
    | {noreply, State, hibernate}
    | {noreply, State, timeout()}
    | {noreply, State, timeout(), hibernate}
    | {reply, {true, Adapter::module()} | false, State}
    | {reply, {true, Adapter::module()} | false, State, hibernate}
    | {reply, {true, Adapter::module()} | false, State, timeout()}
    | {reply, {true, Adapter::module()} | false, State, timeout(), hibernate}
    | {shutdown, Reason::any(), State}.
-callback bones_rpc_request({bones_rpc:msg_id(), bones_rpc:method(), bones_rpc:params()},
        From::{pid(), {request, bones_rpc:msg_id()}}, State::any())
    -> {noreply, State}
    | {noreply, State, hibernate}
    | {noreply, State, timeout()}
    | {noreply, State, timeout(), hibernate}
    | {reply, bones_rpc:reply(), State}
    | {reply, bones_rpc:reply(), State, hibernate}
    | {reply, bones_rpc:reply(), State, timeout()}
    | {reply, bones_rpc:reply(), State, timeout(), hibernate}
    | {shutdown, Reason::any(), State}.
-callback bones_rpc_notify({bones_rpc:method(), bones_rpc:params()}, State::any())
    -> {noreply, State}
    | {noreply, State, hibernate}
    | {noreply, State, timeout()}
    | {noreply, State, timeout(), hibernate}
    | {reply, bones_rpc:reply(), State}
    | {reply, bones_rpc:reply(), State, hibernate}
    | {reply, bones_rpc:reply(), State, timeout()}
    | {reply, bones_rpc:reply(), State, timeout(), hibernate}
    | {shutdown, Reason::any(), State}.
-callback bones_rpc_info(Info::term(), State::any())
    -> {noreply, State}
    | {noreply, State, hibernate}
    | {noreply, State, timeout()}
    | {noreply, State, timeout(), hibernate}
    | {shutdown, Reason::any(), State}.
-callback bones_rpc_terminate(Reason::term(), Req::req(), State::any())
    -> term().
