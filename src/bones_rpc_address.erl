%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :   05 Aug 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_address).

-include("bones_rpc.hrl").
-include("bones_rpc_internal.hrl").
-include_lib("kernel/include/inet.hrl").

%% API
-export([new/2, resolve/1]).

-type address() :: #address{}.
-export_type([address/0]).

%%%===================================================================
%%% API functions
%%%===================================================================

new(Host, Port) when is_integer(Port) ->
    #address{host=Host, port=Port}.

resolve(Address=#address{host=Host={A,B,C,D}})
        when is_integer(A)
        andalso is_integer(B)
        andalso is_integer(C)
        andalso is_integer(D) ->
    {ok, Address#address{ip=Host}};
resolve(Address=#address{host=Host={A,B,C,D,E,F,G,H}})
        when is_integer(A)
        andalso is_integer(B)
        andalso is_integer(C)
        andalso is_integer(D)
        andalso is_integer(E)
        andalso is_integer(F)
        andalso is_integer(G)
        andalso is_integer(H) ->
    {ok, Address#address{ip=Host}};
resolve(Address=#address{host=Host}) when is_binary(Host) ->
    resolve(Address#address{host=binary_to_list(Host)});
resolve(Address=#address{host=Host}) when is_list(Host) ->
    case inet:parse_address(Host) of
        {ok, IP} ->
            {ok, Address#address{ip=IP}};
        {error, _} ->
            case inet:gethostbyname(Host) of
                {ok, #hostent{h_addr_list=Hosts}} ->
                    IP = lists:nth(random:uniform(length(Hosts)), Hosts),
                    {ok, Address#address{ip=IP}};
                Error ->
                    Error
            end
    end.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------
