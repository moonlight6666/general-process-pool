%%%-------------------------------------------------------------------
%%% @author Sir
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(pool).

%% API
-export([
    apply_async/2,
    apply_async/4,
    apply_sync/4,
    apply_sync/2,
    apply_sync/5,
    apply_sync/3
]).
-export([
    start_pool/2,
    start_pool/1
]).

%%%===================================================================
%%% API
%%%===================================================================

start_pool(Name) ->
    start_pool(Name, erlang:system_info(schedulers)).
start_pool(Name, PCount) ->
    start_pool_mgr(Name),
    add_pool_worker(Name, PCount),
    ok.

start_pool_mgr(Name) ->
    pool_mgr:start_link(Name).

add_pool_worker(Name, PCount) ->
    Fun = fun(_N) ->
        pool_worker:start_link(Name)
    end,
    lists:foreach(Fun, lists:seq(1, PCount)).

%% @doc Apply async
apply_async(Name, Fun) when is_function(Fun) ->
	apply_async1(Name, Fun).

apply_async(Name, M, F, A) ->
	apply_async1(Name, {M, F, A}).
apply_async1(Name, FunArgs) ->
	gen_server:cast(Name, {apply_async, FunArgs}).

%% @doc Apply sync
apply_sync(Name, Fun) when is_function(Fun) ->
	apply_sync1(Name, Fun, infinity).

apply_sync(Name, Fun, TimeOut) when is_function(Fun) ->
	apply_sync1(Name, Fun, TimeOut).

apply_sync(Name, M, F, A) ->
	apply_sync1(Name, {M, F, A}, infinity).
apply_sync(Name, M, F, A, TimeOut) ->
	apply_sync1(Name, {M, F, A}, TimeOut).

apply_sync1(Name, FunArgs, TimeOut) ->
	gen_server:cast(Name, {apply_sync, FunArgs, self()}),
	receive
		{success, Result} ->
			{success, Result};
        {fail, Reason} ->
            {fail, Reason};
		Other ->
			io:format("unexpected_receive:~p~n", [Other]),
			{fail, unexpected_receive}
	after TimeOut ->
		{fail, timeout}
	end.

