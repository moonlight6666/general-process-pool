%% The MIT License (MIT)
%%
%% Copyright (c) 2016 chnzrb
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in all
%% copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
%% SOFTWARE.

%% Generic worker pool master.
-module(gen_pool).
-behaviour(gen_server).
%% API
-export([
    start_link/3,
    start_link/2,
    get_state/1,
    get_info/1,
    cast/2,
    call/2,
    call/4,
    add_worker/2,
    del_worker/2,
    stop/1
]).

%% Internal interface
-export([
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

%% pool behaviour callbacks
-callback handle_cast(Request :: term()) -> term().
-callback handle_call(Request :: term(), From :: pid()) -> term().

-define(RUN_TIMEOUT, 10000).
-define(CHECKOUT_TIMEOUT, 10000).

-record(state, {
    callback,
    workers = ordsets:new(),
    available = ordsets:new(),
    waiting = queue:new(),
    locked = orddict:new(),
    decrease = 0
}).

-spec(start_link(Pool, Callback, Num) -> Ret when
    Pool :: atom(),
    Callback :: module(),
    Num :: integer(),
    Ret :: {ok, pid()}).
start_link(Pool, Callback) ->
    Num = erlang:system_info(schedulers),
    start_link(Pool, Callback, Num).
start_link(Pool, Callback, Num) when Num > 0 ->
    {ok, _} = gen_server:start_link({local, Pool}, ?MODULE, [Callback, Num], []).

-spec(get_state(Pool :: atom()) ->
    State :: #state{}).
get_state(Pool) ->
    gen_server:call(Pool, get_state).

-spec(get_info(Pool :: atom()) ->
    {WorkerNum :: integer(), AvailableNum :: integer(), WaitingNum :: integer()}).
get_info(Pool) ->
    gen_server:call(Pool, get_info).

-spec(add_worker(Pool :: atom(), Num :: integer()) -> ok).
add_worker(Pool, Num) when Num > 0 ->
    gen_server:cast(Pool, {add_worker, Num}).

-spec(del_worker(Pool :: atom(), Num :: integer()) -> ok).
del_worker(Pool, Num) when Num > 0 ->
    gen_server:cast(Pool, {del_worker, Num}).

-spec(cast(Pool :: atom(), Request :: term()) -> ok).
cast(Pool, Request) ->
    gen_server:cast(Pool, {cast, Request}).

-spec(call(Pool, Request) -> Ret when
    Pool :: atom(),
    Request :: term(),
    Ret :: {reply, Reply :: term()} | {error, Reason :: term()}).

call(Pool, Request) ->
    call(Pool, Request, ?CHECKOUT_TIMEOUT, ?RUN_TIMEOUT).

call(Pool, Request, CheckOutTimeout, RunTimeout) ->
    Ref = erlang:make_ref(),
    try gen_server:call(Pool, {check_out, Ref}, CheckOutTimeout) of
        {Worker, Ref} ->
            Ret = pool_worker:call(Worker, Request, Ref, RunTimeout),
            check_in(Pool, Worker),
            case Ret of
                {reply, Reply, Ref} ->
                    Reply;
                {error, Reason, Ref} ->
                    error(Reason)
            end
    catch
        Class:Reason ->
            cancel_waiting(Pool),
            receive
                {_, Ref} ->
                    noop
            after 0 ->
                noop
            end,
            erlang:raise(Class, Reason, erlang:get_stacktrace())
    end.

check_in(Pool, Worker) ->
    gen_server:cast(Pool, {check_in, Worker, self()}).

cancel_waiting(Pool) ->
    gen_server:call(Pool, cancel_waiting, infinity).

-spec(stop(Pool :: atom()) -> ok).
stop(Pool) ->
    gen_server:call(Pool, stop).
%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Callback, Num]) ->
    add_worker(self(), Num),
    {ok, #state{callback = Callback}}.

handle_call(get_state, _From, State) ->
    {reply, State, State};
handle_call(get_info, _From, State = #state{workers = Workers, available = Available, waiting = Waiting, locked = Locked}) ->
    {
        reply,
        {
            {worker, ordsets:size(Workers)},
            {available, ordsets:size(Available)},
            {waiting, queue:len(Waiting)},
            {locked, orddict:size(Locked)}
        },
        State
    };
handle_call({check_out, Ref}, {From, CallRef}, State = #state{available = Available, waiting = Waiting, locked = Locked}) ->
    MRef = erlang:monitor(process, From),
    case Available of
        [] ->
            {noreply, State#state{waiting = queue:in({check_out, Ref, MRef, CallRef, From}, Waiting)}};
        [Worker | Left] ->
            {reply, {Worker, Ref}, State#state{available = Left, locked = orddict:store(From, {Worker, MRef}, Locked)}}
    end;
handle_call(cancel_waiting, {From, _}, State = #state{waiting = Waiting}) ->
    erase(cancel_waiting_flag),
    NewWaiting = queue:filter(
        fun(E) ->
            case E of
                {check_out, _Ref, MRef, _CallRef, From} ->
                    erlang:demonitor(MRef, [flush]),
                    put(cancel_waiting_flag, true),
                    false;
                _ ->
                    true
            end
        end,
        Waiting),
    case get(cancel_waiting_flag) of
        true ->
            {reply, ok, State#state{waiting = NewWaiting}};
        _ ->
            {true, NewState} = handle_check_in(From, State#state{waiting = NewWaiting}),
            {reply, ok, NewState}
    end;
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_check_in(From, State = #state{locked = Locked}) ->
    case orddict:find(From, Locked) of
        error ->
            {false, State};
        {ok, {Worker, MRef}} ->
            erlang:demonitor(MRef, [flush]),
            {true, handle_idle(Worker, State#state{locked = orddict:erase(From, Locked)})}
    end.
handle_cast({ready, Worker}, State = #state{workers = Workers, available = _Available, waiting = _Waiting}) ->
    erlang:monitor(process, Worker),
    handle_cast({idle, Worker}, State#state{workers = ordsets:add_element(Worker, Workers)});
handle_cast({idle, Worker}, State) ->
    {noreply, handle_idle(Worker, State)};
handle_cast({cast, Request}, State = #state{available = [], waiting = Waiting}) ->
    {noreply, State#state{waiting = queue:in({cast, Request}, Waiting)}};
handle_cast({cast, Request}, State = #state{available = [Pid | Left]}) ->
    pool_worker:cast(Pid, Request),
    {noreply, State#state{available = Left}};
handle_cast({check_in, _Worker, From}, State) ->
    {true, NewState} = handle_check_in(From, State),
    {noreply, NewState};

handle_cast({add_worker, Num}, State = #state{callback = Callback}) ->
    handle_add_worker(Callback, Num),
    {noreply, State};
handle_cast({del_worker, Num}, State) ->
    {noreply, handle_del_worker(State, Num)};
handle_cast(_Request, State) ->
    {noreply, State}.

handle_info({'DOWN', Ref, process, Pid, _Reason}, State = #state{workers = Workers, available = Available}) ->
    case handle_check_in(Pid, State) of
        {true, NewState} ->
            {noreply, NewState};
        {false, State} ->
            erlang:demonitor(Ref, [flush]),
            {noreply, State#state{workers = ordsets:del_element(Pid, Workers), available = ordsets:del_element(Pid, Available)}}
    end;
handle_info(_Info, State) ->
    {noreply, State}.

terminate(Reason, State) ->
    io:format(
        "Gen_pool terminate :~n"
        "        state  :~p~n"
        "        reason :~p~n",
        [State, Reason]
    ),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @doc Init the pool worker
-spec(ready(Pool :: term(), Worker :: pid()) -> term()).
ready(Pool, Worker) ->
    gen_server:cast(Pool, {ready, Worker}).

%% @doc Tell the mgr the pool worker is idle
-spec(idle(Pool :: term(), Worker :: pid()) -> term()).
idle(Pool, Worker) ->
    gen_server:cast(Pool, {idle, Worker}).

handle_add_worker(Callback, Num) ->
    Fun = fun(_N) ->
        pool_worker:start_link(self(), Callback)
    end,
    lists:foreach(Fun, lists:seq(1, Num)).

handle_del_worker(State = #state{workers = Workers, available = Available, decrease = Decrease1}, Decrease2) ->
    Decrease = Decrease2 + Decrease1,
    AvailableNum = ordsets:size(Available),
    {{DelAvailable, NewAvailable}, Left} =
    if AvailableNum >= Decrease ->
        {lists:split(Decrease, Available), 0};
        true ->
            {{Available, []}, Decrease - AvailableNum}
    end,
    [pool_worker:stop(DelWorker) || DelWorker <- DelAvailable],
    NewWorkers = ordsets:subtract(Workers, DelAvailable),
    State#state{workers = NewWorkers, available = NewAvailable, decrease = Left}.


handle_idle(Worker, State = #state{available = Available, waiting = Waiting, locked = Locked, decrease = Decrease}) when Decrease == 0 ->
    case queue:out(Waiting) of
        {empty, Waiting} ->
            State#state{available = ordsets:add_element(Worker, Available)};
        {{value, {cast, Request}}, Waiting1} ->
            pool_worker:cast(Worker, Request),
            State#state{waiting = Waiting1};
        {{value, {check_out, Ref, MRef, CallRef, From}}, Waiting1} ->
            gen:reply({From, CallRef} , {Worker, Ref}),
            State#state{waiting = Waiting1, locked = orddict:store(From, {Worker, MRef}, Locked)}
    end;
handle_idle(Worker, State = #state{workers = Workers, decrease = Decrease}) when Decrease > 0 ->
    pool_worker:stop(Worker),
    State#state{workers = ordsets:del_element(Worker, Workers), decrease = Decrease - 1}.
