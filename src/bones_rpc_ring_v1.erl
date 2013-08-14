%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pagodabox.com>
%%% @copyright 2013, Pagoda Box, Inc.
%%% @doc
%%%
%%% @end
%%% Created :  08 Aug 2013 by Andrew Bennett <andrew@pagodabox.com>
%%%-------------------------------------------------------------------
-module(bones_rpc_ring_v1).

-include("bones_rpc.hrl").
-include("bones_rpc_internal.hrl").

%% API
-export([new/4, add_member/4, remove_member/2, from_binary/1, from_obj/1, to_binary/1, to_obj/1]).

%%%===================================================================
%%% API functions
%%%===================================================================

new(Cluster, Cookie, IP, Port)
        when is_atom(Cluster)
        andalso is_atom(Cookie)
        andalso is_tuple(IP)
        andalso is_integer(Port) ->
    #bones_rpc_ring_v1{nodename=node(), clustername=Cluster, cookie=Cookie,
        ip=IP, port=Port, members=[{node(), {IP, Port}}]}.

add_member(Node, _IP, _Port, #bones_rpc_ring_v1{nodename=Node}) ->
    {error, cannot_add_ring_owner};
add_member(Node, IP, Port, Ring=#bones_rpc_ring_v1{members=Members})
        when is_atom(Node)
        andalso is_tuple(IP)
        andalso is_integer(Port) ->
    Members2 = lists:keystore(Node, 1, Members, {Node, {IP, Port}}),
    {ok, Ring#bones_rpc_ring_v1{members=Members2}}.

remove_member(Node, #bones_rpc_ring_v1{nodename=Node}) ->
    {error, cannot_remove_ring_owner};
remove_member(Node, Ring=#bones_rpc_ring_v1{members=Members}) when is_atom(Node) ->
    Members2 = lists:keydelete(Node, 1, Members),
    {ok, Ring#bones_rpc_ring_v1{members=Members2}}.

from_binary(Compressed) ->
    case catch zlib:unzip(Compressed) of
        Packed when is_binary(Packed) ->
            case msgpack:unpack(Packed, [jsx]) of
                {ok, Obj} ->
                    from_obj(Obj);
                UnpackError ->
                    UnpackError
            end;
        UnzipError ->
            UnzipError
    end.

from_obj([1, RawNode, RawCluster, RawCookie, IPList, Port, RawMembers])
        when is_binary(RawNode)
        andalso is_binary(RawCluster)
        andalso is_binary(RawCookie)
        andalso is_list(IPList)
        andalso is_integer(Port)
        andalso is_list(RawMembers) ->
    Node = binary_to_atom(RawNode, utf8),
    Cluster = binary_to_atom(RawCluster, utf8),
    Cookie = binary_to_atom(RawCookie, utf8),
    IP = list_to_tuple(IPList),
    Members = [begin
        {binary_to_atom(Member, utf8), {list_to_tuple(MemberIP), MemberPort}}
    end || {Member, [MemberIP, MemberPort]} <- RawMembers,
        is_binary(Member),
        is_list(MemberIP),
        is_integer(MemberPort)],
    #bones_rpc_ring_v1{nodename=Node, clustername=Cluster, cookie=Cookie,
        ip=IP, port=Port, members=Members}.

to_binary(Ring) ->
    case msgpack:pack(to_obj(Ring), [jsx]) of
        Binary when is_binary(Binary) ->
            zlib:zip(Binary);
        Error ->
            Error
    end.

to_obj(Ring=#bones_rpc_ring_v1{}) ->
    [_ | List] = tuple_to_list(Ring),
    [ring_element(Obj) || Obj <- [1 | List]].

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

%% @private
ring_element(undefined) ->
    nil;
ring_element(true) ->
    true;
ring_element(false) ->
    false;
ring_element(Atom) when is_atom(Atom) ->
    atom_to_binary(Atom, utf8);
ring_element(Binary) when is_binary(Binary) ->
    Binary;
ring_element(Float) when is_float(Float) ->
    Float;
ring_element(Integer) when is_integer(Integer) ->
    Integer;
ring_element(List=[{_Node, {_IP, _Port}} | _]) ->
    [begin
        {ring_element(Node), [ring_element(IP), ring_element(Port)]}
    end || {Node, {IP, Port}} <- List];
ring_element(List) when is_list(List) ->
    List;
ring_element(Tuple) when is_tuple(Tuple) ->
    tuple_to_list(Tuple).

%% Tests.

-ifdef(TEST).

roundtrip_test_() ->
    Specs = [
        new(cluster, cookie, {127,0,0,1}, 1234),
        #bones_rpc_ring_v1{
            nodename = 'another-node@123.123.123.123',
            clustername = clustername,
            cookie = '1234-1234-1234-1234',
            ip = {65152,0,0,0,0,0,0,1},
            port = 12345,
            members = [
                {'another-node@123.123.123.123', {{65152,0,0,0,0,0,0,1}, 12345}},
                {node(), {{127,0,0,1}, 1234}},
                {'yet-another@1.1.1.1', {{1,1,1,1}, 4321}}
            ]
        }
    ],
    [{lists:flatten(io_lib:format("~p", [to_obj(Ring)])), fun() ->
        Ring = from_binary(to_binary(Ring))
    end} || Ring <- Specs].

-endif.
