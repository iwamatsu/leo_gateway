%%====================================================================
%%
%% LeoFS Gateway
%%
%% Copyright (c) 2012
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
%% LeoFS Gateway - RPC Handler Test
%% @doc
%% @end
%%====================================================================
-module(leo_gateway_rpc_handler_tests).
-author('Yoshiyuki Kanno').

-include("leo_gateway.hrl").
-include("leo_s3_http.hrl").
-include_lib("leo_s3_bucket/include/leo_s3_bucket.hrl").
-include_lib("leo_s3_auth/include/leo_s3_auth.hrl").
-include_lib("leo_commons/include/leo_commons.hrl").
-include_lib("leo_logger/include/leo_logger.hrl").
-include_lib("leo_object_storage/include/leo_object_storage.hrl").
-include_lib("leo_redundant_manager/include/leo_redundant_manager.hrl").
-include_lib("eunit/include/eunit.hrl").


%%--------------------------------------------------------------------
%% TEST
%%--------------------------------------------------------------------
-ifdef(EUNIT).
api_test_() ->
    {setup, fun setup/0, fun teardown/1,
     {with, [
             fun get_bucket_list_error_/1,
             fun get_bucket_list_empty_/1,
             fun get_bucket_list_normal1_/1,
             fun head_object_error_/1,
             fun head_object_notfound_/1,
             fun head_object_normal1_/1,
             fun get_object_error_/1,
             fun get_object_notfound_/1,
             fun get_object_normal1_/1,
             fun get_object_with_etag_error_/1,
             fun get_object_with_etag_notfound_/1,
             fun get_object_with_etag_normal1_/1,
             fun get_object_with_etag_normal2_/1,
             fun delete_object_error_/1,
             fun delete_object_notfound_/1,
             fun delete_object_normal1_/1,
             fun put_object_error_/1,
             fun put_object_notfound_/1,
             fun put_object_normal1_/1
            ]}}.

setup() ->
    ok = leo_logger_client_message:new("./", ?LOG_LEVEL_WARN),
    io:format(user, "cwd:~p~n",[os:cmd("pwd")]),
    [] = os:cmd("epmd -daemon"),
    {ok, Hostname} = inet:gethostname(),
    Node0 = list_to_atom("node_0@" ++ Hostname),
    net_kernel:start([Node0, shortnames]),

    Args = " -pa ../deps/*/ebin "
        ++ " -kernel error_logger    '{file, \"../kernel.log\"}' "
        ++ " -sasl sasl_error_logger '{file, \"../sasl.log\"}' ",
    {ok, Node1} = slave:start_link(list_to_atom(Hostname), 'manager_0', Args),

    meck:new(leo_redundant_manager_api),
    meck:expect(leo_redundant_manager_api, get_redundancies_by_key,
                fun(_Method, _Key) ->
                        {ok, #redundancies{id = 0,
                                           nodes = [{Node0,true}, {Node1,true}],
                                           n = 2, r = 1, w = 1, d = 1}}
                end),
    [Node0, Node1].

teardown([_, Node1]) ->
    meck:unload(),
    net_kernel:stop(),
    slave:stop(Node1),
    ok.

get_bucket_list_error_([_Node0, Node1]) ->
    ok = rpc:call(Node1, meck, new,    [leo_storage_handler_directory, [no_link]]),
    ok = rpc:call(Node1, meck, expect, [leo_storage_handler_directory, find_by_parent_dir,
                                        fun(_Key,_,_,_) ->
                                                {error, some_error}
                                        end]),
    Res = leo_s3_http_bucket:get_bucket_list("accesskeyid", "bucket/", none, none, 1000, "dir"),
    ?assertEqual({error, internal_server_error}, Res),
    ok = rpc:call(Node1, meck, unload, [leo_storage_handler_directory]),
    ok.

get_bucket_list_empty_([_Node0, Node1]) ->
    ok = rpc:call(Node1, meck, new,    [leo_storage_handler_directory, [no_link]]),
    ok = rpc:call(Node1, meck, expect, [leo_storage_handler_directory, find_by_parent_dir,
                                        fun(_Key,_,_,_) ->
                                                {ok, []}
                                        end]),
    Res = leo_s3_http_bucket:get_bucket_list("accesskeyid", "bucket/", none, none, 1000, "dir"),
    Xml = io_lib:format(?XML_OBJ_LIST, [[]]),
    ?assertEqual({ok, [], Xml}, Res),
    ok = rpc:call(Node1, meck, unload, [leo_storage_handler_directory]),
    ok.

get_bucket_list_normal1_([_Node0, Node1]) ->
    ok = rpc:call(Node1, meck, new,    [leo_storage_handler_directory, [no_link]]),
    ok = rpc:call(Node1, meck, expect, [leo_storage_handler_directory, find_by_parent_dir,
                                        fun(Key,_,_,_) ->
                                                {ok, [
                                                      #metadata{
                                                         key = Key,
                                                         dsize = 10,
                                                         del = 0
                                                        }
                                                     ]}
                                        end]),
    {ok, [Head|Tail], _Xml} = leo_s3_http_bucket:get_bucket_list("accesskeyid", "bucket/", none, none, 1000, "dir"),
    ?assertEqual(10, Head#metadata.dsize),
    ?assertEqual([], Tail),
    ok = rpc:call(Node1, meck, unload, [leo_storage_handler_directory]),
    ok.

head_object_notfound_([Node0, Node1]) ->
    ok = rpc:call(Node0, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node0, meck, expect, [leo_storage_handler_object, head,
                                        fun(_Addr, _Key) ->
                                                {error, not_found}
                                        end]),
    ok = rpc:call(Node1, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node1, meck, expect, [leo_storage_handler_object, head,
                                        fun(_Addr, _Key) ->
                                                {error, not_found}
                                        end]),
    Res = leo_gateway_rpc_handler:head("bucket/key"),
    ?assertEqual({error, not_found}, Res),
    ok = rpc:call(Node0, meck, unload, [leo_storage_handler_object]),
    ok = rpc:call(Node1, meck, unload, [leo_storage_handler_object]),
    ok.

head_object_error_([_Node0, Node1]) ->
    ok = rpc:call(Node1, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node1, meck, expect, [leo_storage_handler_object, head,
                                        fun(_Addr, _Key) ->
                                                {error, foobar}
                                        end]),
    Res = leo_gateway_rpc_handler:head("bucket/key"),
    ?assertEqual({error, internal_server_error}, Res),
    ok = rpc:call(Node1, meck, unload, [leo_storage_handler_object]),
    ok.

head_object_normal1_([_Node0, Node1]) ->
    ok = rpc:call(Node1, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node1, meck, expect, [leo_storage_handler_object, head,
                                        fun(_Addr, Key) ->
                                                {ok,
                                                 #metadata{
                                                   key = Key,
                                                   dsize = 10,
                                                   del = 0
                                                  }
                                                }
                                        end]),
    {ok, Meta} = leo_gateway_rpc_handler:head("bucket/key"),
    ?assertEqual(10, Meta#metadata.dsize),
    ?assertEqual("bucket/key", Meta#metadata.key),
    ok = rpc:call(Node1, meck, unload, [leo_storage_handler_object]),
    ok.

get_object_notfound_([Node0, Node1]) ->
    ok = rpc:call(Node0, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node0, meck, expect, [leo_storage_handler_object, get,
                                        fun(_Addr, _Key, _ReqId) ->
                                                {error, not_found}
                                        end]),
    ok = rpc:call(Node1, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node1, meck, expect, [leo_storage_handler_object, get,
                                        fun(_Addr, _Key, _ReqId) ->
                                                {error, not_found}
                                        end]),
    Res = leo_gateway_rpc_handler:get("bucket/key"),
    ?assertEqual({error, not_found}, Res),
    ok = rpc:call(Node0, meck, unload, [leo_storage_handler_object]),
    ok = rpc:call(Node1, meck, unload, [leo_storage_handler_object]),
    ok.

get_object_error_([_Node0, Node1]) ->
    ok = rpc:call(Node1, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node1, meck, expect, [leo_storage_handler_object, get,
                                        fun(_Addr, _Key, _ReqId) ->
                                                {error, foobar}
                                        end]),
    Res = leo_gateway_rpc_handler:get("bucket/key"),
    ?assertEqual({error, internal_server_error}, Res),
    ok = rpc:call(Node1, meck, unload, [leo_storage_handler_object]),
    ok.

get_object_normal1_([_Node0, Node1]) ->
    ok = rpc:call(Node1, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node1, meck, expect, [leo_storage_handler_object, get,
                                        fun(_Addr, Key, _ReqId) ->
                                                {ok,
                                                 #metadata{
                                                   key = Key,
                                                   dsize = 4,
                                                   del = 0
                                                  },
                                                 <<"body">>
                                                }
                                        end]),
    {ok, Meta, Body} = leo_gateway_rpc_handler:get("bucket/key"),
    ?assertEqual(4, Meta#metadata.dsize),
    ?assertEqual("bucket/key", Meta#metadata.key),
    ?assertEqual(<<"body">>, Body),
    ok = rpc:call(Node1, meck, unload, [leo_storage_handler_object]),
    ok.

get_object_with_etag_notfound_([Node0, Node1]) ->
    ok = rpc:call(Node0, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node0, meck, expect, [leo_storage_handler_object, get,
                                        fun(_Addr, _Key, _Etag, _ReqId) ->
                                                {error, not_found}
                                        end]),
    ok = rpc:call(Node1, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node1, meck, expect, [leo_storage_handler_object, get,
                                        fun(_Addr, _Key, _Etag, _ReqId) ->
                                                {error, not_found}
                                        end]),
    Res = leo_gateway_rpc_handler:get("bucket/key", 123),
    ?assertEqual({error, not_found}, Res),
    ok = rpc:call(Node0, meck, unload, [leo_storage_handler_object]),
    ok = rpc:call(Node1, meck, unload, [leo_storage_handler_object]),
    ok.

get_object_with_etag_error_([_Node0, Node1]) ->
    ok = rpc:call(Node1, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node1, meck, expect, [leo_storage_handler_object, get,
                                        fun(_Addr, _Key, _Etag, _ReqId) ->
                                                {error, foobar}
                                        end]),
    Res = leo_gateway_rpc_handler:get("bucket/key", 123),
    ?assertEqual({error, internal_server_error}, Res),
    ok = rpc:call(Node1, meck, unload, [leo_storage_handler_object]),
    ok.

get_object_with_etag_normal1_([_Node0, Node1]) ->
    ok = rpc:call(Node1, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node1, meck, expect, [leo_storage_handler_object, get,
                                        fun(_Addr, Key, _Etag, _ReqId) ->
                                                {ok,
                                                 #metadata{
                                                   key = Key,
                                                   dsize = 4,
                                                   del = 0
                                                  },
                                                 <<"body">>
                                                }
                                        end]),
    {ok, Meta, Body} = leo_gateway_rpc_handler:get("bucket/key", 123),
    ?assertEqual(4, Meta#metadata.dsize),
    ?assertEqual("bucket/key", Meta#metadata.key),
    ?assertEqual(<<"body">>, Body),
    ok = rpc:call(Node1, meck, unload, [leo_storage_handler_object]),
    ok.

get_object_with_etag_normal2_([_Node0, Node1]) ->
    ok = rpc:call(Node1, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node1, meck, expect, [leo_storage_handler_object, get,
                                        fun(_Addr, _Key, _Etag, _ReqId) ->
                                                {ok, match}
                                        end]),
    Res = leo_gateway_rpc_handler:get("bucket/key", 123),
    ?assertEqual({ok, match}, Res),
    ok = rpc:call(Node1, meck, unload, [leo_storage_handler_object]),
    ok.

delete_object_notfound_([Node0, Node1]) ->
    ok = rpc:call(Node0, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node0, meck, expect, [leo_storage_handler_object, delete,
                                        fun(_Addr, _Key, _ReqId, _Ts) ->
                                                {error, not_found}
                                        end]),
    ok = rpc:call(Node1, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node1, meck, expect, [leo_storage_handler_object, delete,
                                        fun(_Addr, _Key, _ReqId, _Ts) ->
                                                {error, not_found}
                                        end]),
    Res = leo_gateway_rpc_handler:delete("bucket/key"),
    ?assertEqual({error, not_found}, Res),
    ok = rpc:call(Node0, meck, unload, [leo_storage_handler_object]),
    ok = rpc:call(Node1, meck, unload, [leo_storage_handler_object]),
    ok.

delete_object_error_([_Node0, Node1]) ->
    ok = rpc:call(Node1, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node1, meck, expect, [leo_storage_handler_object, delete,
                                        fun(_Addr, _Key, _ReqId, _Ts) ->
                                                {error, foobar}
                                        end]),
    Res = leo_gateway_rpc_handler:delete("bucket/key"),
    ?assertEqual({error, internal_server_error}, Res),
    ok = rpc:call(Node1, meck, unload, [leo_storage_handler_object]),
    ok.

delete_object_normal1_([_Node0, Node1]) ->
    ok = rpc:call(Node1, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node1, meck, expect, [leo_storage_handler_object, delete,
                                        fun(_Addr, _Key, _ReqId, _Ts) ->
                                                ok
                                        end]),
    Res = leo_gateway_rpc_handler:delete("bucket/key"),
    ?assertEqual(ok, Res),
    ok = rpc:call(Node1, meck, unload, [leo_storage_handler_object]),
    ok.

put_object_notfound_([Node0, Node1]) ->
    ok = rpc:call(Node0, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node0, meck, expect, [leo_storage_handler_object, put,
                                        fun(_Addr, _Key, _Body, _Size, _ReqId, _Ts) ->
                                                {error, not_found}
                                        end]),
    ok = rpc:call(Node1, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node1, meck, expect, [leo_storage_handler_object, put,
                                        fun(_Addr, _Key, _Body, _Size, _ReqId, _Ts) ->
                                                {error, not_found}
                                        end]),
    Res = leo_gateway_rpc_handler:put("bucket/key", <<"body">>, 4),
    ?assertEqual({error, not_found}, Res),
    ok = rpc:call(Node0, meck, unload, [leo_storage_handler_object]),
    ok = rpc:call(Node1, meck, unload, [leo_storage_handler_object]),
    ok.

put_object_error_([_Node0, Node1]) ->
    ok = rpc:call(Node1, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node1, meck, expect, [leo_storage_handler_object, put,
                                        fun(_Addr, _Key, _Body, _Size, _ReqId, _Ts) ->
                                                {error, foobar}
                                        end]),
    Res = leo_gateway_rpc_handler:put("bucket/key", <<"body">>, 4),
    ?assertEqual({error, internal_server_error}, Res),
    ok = rpc:call(Node1, meck, unload, [leo_storage_handler_object]),
    ok.

put_object_normal1_([_Node0, Node1]) ->
    ok = rpc:call(Node1, meck, new,    [leo_storage_handler_object, [no_link]]),
    ok = rpc:call(Node1, meck, expect, [leo_storage_handler_object, put,
                                        fun(_Addr, _Key, _Body, _Size, _ReqId, _Ts) ->
                                                ok
                                        end]),
    Res = leo_gateway_rpc_handler:put("bucket/key", <<"body">>, 4),
    ?assertEqual(ok, Res),
    ok = rpc:call(Node1, meck, unload, [leo_storage_handler_object]),
    ok.
-endif.
