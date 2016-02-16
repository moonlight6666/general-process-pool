%%%-------------------------------------------------------------------
%%% @author         chn.zrb@gmail.com
%%% @copyright (C)  2016, <FEIYU>
%%% @doc
%%% @end
%%% Created : 05. 二月 2016 11:04
%%%-------------------------------------------------------------------
-module(pool_mgr).

%% External interface
-export([
    get_state/1
]).

%% Internal interface
-export([
    start_link/1,
    ready/2,
    idle/2
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

-record(state, {available, pending}).

%% @doc Start the pool manager
start_link(Name) ->
    {ok, _} = gen_server:start_link({local, Name}, ?MODULE, [], []).

%% @doc Get the state
-spec(get_state(PoolName :: term()) ->
    State :: #state{}).
get_state(Name) ->
    gen_server:call(Name, get_state).

%% @doc Init the pool worker
-spec(ready(Name :: term(), PPid :: pid()) -> term()).
ready(Name, PPid) ->
    gen_server:cast(Name, {ready, PPid}).

%% @doc Tell the mgr the pool worker is idle
-spec(idle(Name :: term(), PPid :: pid()) -> term()).
idle(Name, PPid) ->
    gen_server:cast(Name, {idle, PPid}).
%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    process_flag(trap_exit, true),
    {ok, #state{available = ordsets:new(), pending = queue:new()}}.

handle_call(get_state, _From, State) ->
    {reply, State, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({ready, PPid}, State = #state{available = _Available, pending = _Pending}) ->
    erlang:monitor(process, PPid),
    handle_cast({idle, PPid}, State);
handle_cast({idle, PPid}, State = #state{available = Available, pending = Pending}) ->
    {
        noreply,
        case queue:out(Pending) of
            {empty, Pending} ->
                State#state{available = ordsets:add_element(PPid, Available)};
            {{value, {apply_async, Fun}}, Pending1} ->
                pool_worker:apply_async(PPid, Fun),
                State#state{pending = Pending1}
        end
    };
handle_cast({apply_async, Fun}, State = #state{available = [], pending = Pending}) ->
    {noreply, State#state{pending = queue:in({apply_async, Fun}, Pending)}};
handle_cast({apply_async, Fun}, State = #state{available = [H | T], pending = _Pending}) ->
    pool_worker:apply_async(H, Fun),
    {noreply, State#state{available = T}};
handle_cast({apply_sync, Fun, Caller}, State = #state{available = [], pending = Pending}) ->
    {noreply, State#state{pending = queue:in({apply_sync, Fun, Caller}, Pending)}};
handle_cast({apply_sync, Fun, Caller}, State = #state{available = [H | T], pending = _Pending}) ->
    pool_worker:apply_sync(H, Fun, Caller),
    {noreply, State#state{available = T}};
handle_cast(_Request, State) ->
    {noreply, State}.

handle_info({'DOWN', _Ref, process, PPid, _Reason}, State = #state { available = Available }) ->
    {noreply, State #state { available = ordsets:del_element(PPid, Available) }};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(Reason, State) ->
    io:format("Pool_mgr terminate :~n"
              "        state :~p~n"
              "        reason :~p~n",
              [State, Reason]),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================