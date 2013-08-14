%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :  05 Aug 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_ring).
-behaviour(gen_server).

-include("bones_rpc.hrl").
-include("bones_rpc_internal.hrl").

-define(SERVER, ?MODULE).
-define(TAB, ?MODULE).

%% API
-export([start_link/0, delete_cluster/1, get/2, merge/1, set/1, unset/1, unset/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%%%===================================================================
%%% API functions
%%%===================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

delete_cluster(Cluster) ->
    gen_server:cast(?SERVER, {delete_cluster, Cluster}).

get(Cluster, Cookie) ->
    ets:lookup_element(?TAB, {Cluster, Cookie}, 2).

merge(Ring=#bones_rpc_ring_v1{}) ->
    gen_server:call(?SERVER, {merge, Ring}).

set(Ring=#bones_rpc_ring_v1{}) ->
    gen_server:call(?SERVER, {set, Ring}).

unset(#bones_rpc_ring_v1{clustername=Cluster, cookie=Cookie}) ->
    unset(Cluster, Cookie).

unset(Cluster, Cookie) ->
    gen_server:call(?SERVER, {unset, Cluster, Cookie}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    {ok, stateless}.

handle_call({merge, Ring=#bones_rpc_ring_v1{clustername=Cluster, cookie=Cookie, members=MembersB}}, _From, State) ->
    try get(Cluster, Cookie) of
        Ring ->
            % nothing changed
            {reply, ok, State};
        #bones_rpc_ring_v1{members=MembersA} ->
            % existing ring
            Members = dict:merge(fun
                (_Key, _ValueA, ValueB) ->
                    ValueB
            end, MembersA, MembersB),
            ok = case Members of
                MembersB ->
                    % nothing changed
                    ok;
                _ ->
                    bones_rpc_ring_event:ring_update(Ring#bones_rpc_ring_v1{members=Members}),
                    ok
            end,
            {reply, ok, State}
    catch
        _:_ ->
            % new ring
            true = ets:insert(?TAB, {{Cluster, Cookie}, Ring}),
            bones_rpc_ring_event:ring_update(Ring),
            {reply, ok, State}
    end;
handle_call({set, Ring=#bones_rpc_ring_v1{clustername=Cluster, cookie=Cookie}}, _From, State) ->
    try get(Cluster, Cookie) of
        Ring ->
            % nothing changed
            {reply, ok, State};
        #bones_rpc_ring_v1{} ->
            % existing ring
            true = ets:insert(?TAB, {{Cluster, Cookie}, Ring}),
            bones_rpc_ring_event:ring_update(Ring),
            {reply, ok, State}
    catch
        _:_ ->
            % new ring
            true = ets:insert(?TAB, {{Cluster, Cookie}, Ring}),
            bones_rpc_ring_event:ring_update(Ring),
            {reply, ok, State}
    end;
handle_call({unset, Cluster, Cookie}, _From, State) ->
    true = ets:delete(?TAB, {Cluster, Cookie}),
    {reply, ok, State};
handle_call(_Request, _From, State) ->
    {reply, {error, badrequest}, State}.

handle_cast({delete_cluster, Cluster}, State) ->
    ok = bones_rpc:delete_cluster(Cluster),
    {noreply, State};
handle_cast(_Request, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------
