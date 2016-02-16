%%%-------------------------------------------------------------------
%%% @author Sir
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 19. 十二月 2015 21:08
%%%-------------------------------------------------------------------
-module(pool_worker).

-behaviour(gen_server).

%% API
-export([
    start_link/1,
    apply_async/2,
    apply_sync/3
]).
%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-record(state, {pool_mgr}).

%%%===================================================================
%%% API
%%%===================================================================

-spec(start_link(PoolMgr :: term()) ->
	{ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(PoolMgr) ->
    {ok, _} = gen_server:start_link(?MODULE, [PoolMgr], []).

apply_async(Pid, Fun) ->
    gen_server:cast(Pid, {apply_async, Fun}).
apply_sync(Pid, Fun, Caller) when is_pid(Caller) ->
    gen_server:cast(Pid, {apply_sync, Fun, Caller}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([PoolMgr]) ->
    process_flag(trap_exit, true),
	pool_mgr:ready(PoolMgr, self()),
	{ok, #state{pool_mgr = PoolMgr}}.

handle_call(_Request, _From, State) ->
	{reply, ok, State}.

handle_cast({apply_async, Fun}, State) ->
    do(Fun, State),
    pool_mgr:idle(State#state.pool_mgr, self()),
	{noreply, State};
handle_cast({apply_sync, Fun, Caller}, State) ->
    Caller ! do(Fun, State),
    pool_mgr:idle(State#state.pool_mgr, self()),
	{noreply, State};
handle_cast(_Request, State) ->
	{noreply, State}.

handle_info(_Info, State) ->
	{noreply, State}.

terminate(Reason, State) ->
    io:format("Pool_worker ~p terminate :~n"
              "      manager : ~p~n"
              "      reason  : ~p~n", [self(), State#state.pool_mgr, Reason]),
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

apply(Fun) when is_function(Fun) ->
    Fun();
apply({M, F, A}) ->
    erlang:apply(M, F, A).

do(Fun, State) ->
    try apply(Fun) of
        Result ->
            {success, Result}
    catch
        _ : Reason ->
            Self = self(),
            io:format(
                "Pool_worker ~p error:~n"
                "     mgr    : ~p~n  "
                "     apply  : ~p~n"
                "     reason : ~p~n",
                [Self, State#state.pool_mgr, Fun, Reason]),
            {fail, Reason}
    end.