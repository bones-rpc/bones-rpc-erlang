%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :   18 Jul 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_protocol).

-include("bones.hrl").

%% API
-export([acknowledge/2, synchronize/2]).

%%%===================================================================
%%% API functions
%%%===================================================================

acknowledge(ID, false) ->
    acknowledge(ID, 16#C2);
acknowledge(ID, true) ->
    acknowledge(ID, 16#C3);
acknowledge(ID, Ready) when is_integer(ID) andalso is_integer(Ready) ->
    bones_adapter:new_ext(1, << ID:4/big-unsigned-integer-unit:8, Ready >>).

synchronize(ID, Adapter) when is_atom(Adapter) ->
    synchronize(ID, atom_to_binary(Adapter, utf8));
synchronize(ID, Adapter) when is_list(Adapter) ->
    synchronize(ID, iolist_to_binary(Adapter));
synchronize(ID, Adapter) when is_integer(ID) andalso is_binary(Adapter) ->
    bones_adapter:new_ext(0, << ID:4/big-unsigned-integer-unit:8, Adapter/binary >>).

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------
