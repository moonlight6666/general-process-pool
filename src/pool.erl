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

%% Generic worker pool manager.
-module(pool).
-behaviour(gen_server).
%% API
-export([
    start_link/3,
    get_state/1,
    get_info/1,
    cast/2,
    call/2,
    add_pool_worker/2,
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
-callback handle_cast(Request :: term(), From :: pid()) -> term().
-callback handle_call(Request :: term(), From :: pid()) -> term().

-record(state, {callback, workers,  available, pending}).
-define(default_timeout, 6000).

-spec(start_link(PoolName, Callback, Num) -> Ret when
    PoolName :: atom(),
    Callback :: module(),
    Num :: integer(),
    Ret :: {ok, pid()}).
start_link(PoolName, Callback, Num) ->
    {ok, _} = gen_server:start_link({local, PoolName}, ?MODULE, [Callback, Num], []).

-spec(get_state(PoolName :: atom()) ->
    State :: #state{}).
get_state(PoolName) ->
    gen_server:call(PoolName, get_state).

-spec(get_info(PoolName :: atom()) ->
    {WorkerNum :: integer(), AvailableNum :: integer(), PendingNum :: integer()}).
get_info(PoolName) ->
    gen_server:call(PoolName, get_info).

-spec(add_pool_worker(PoolName :: atom(), Num :: integer()) -> ok).
add_pool_worker(PoolName, Num) ->
    gen_server:cast(PoolName, {add_pool_worker, Num}).

-spec(cast(PoolName :: atom(), Request :: term()) -> ok).
cast(PoolName, Request) ->
    gen_server:cast(PoolName, {'$cast', Request, self()}).

-spec(call(PoolName, Request) -> Ret when
    PoolName :: atom(),
    Request :: term(),
    Ret :: {reply, Reply :: term()} | {error, Reason :: term()}).
call(PoolName, Request) ->
    call(PoolName, Request, ?default_timeout).
call(PoolName, Request, Timeout) ->
    Ref = erlang:make_ref(),
    gen_server:cast(PoolName, {'$call', Request, {self(), Ref}}),
    Ret = receive
        {'$do', {Worker, Ref}} ->
            erlang:send(Worker, {'$do_it', Ref}),
            receive
                {'$reply', Reply, Ref} ->
                    {reply, Reply};
                {'$error', Reason, Ref} ->
                    {error, Reason}
            after Timeout ->
                {error, timeout}
            end
    after Timeout ->
        {error, timeout}
    end,
    clear_message_queue(),
    Ret.

-spec(stop(PoolName :: atom()) -> ok).
stop(PoolName) ->
    gen_server:call(PoolName, stop).
%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Callback, Num]) ->
    add_pool_worker(self(), Num),
    {ok, #state{workers = ordsets:new(),  available = ordsets:new(), pending = queue:new(), callback = Callback}}.

handle_call(get_state, _From, State) ->
    {reply, State, State};
handle_call(get_info, _From, State = #state{workers = Workers, available = Available, pending = Pending}) ->
    {reply, {ordsets:size(Workers), ordsets:size(Available), queue:len(Pending)}, State};
handle_call(stop, _From, State) ->
    {stop, stop, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({ready, Worker}, State = #state{workers = Workers, available = _Available, pending = _Pending}) ->
    erlang:monitor(process, Worker),
    handle_cast({idle, Worker},  State#state{workers = ordsets:add_element(Worker, Workers)});
handle_cast({idle, Worker}, State = #state{available = Available, pending = Pending}) ->
    {
        noreply,
        case queue:out(Pending) of
            {empty, Pending} ->
                State#state{available = ordsets:add_element(Worker, Available)};
            {{value, {'$cast', Msg, From}}, Pending1} ->
                pool_worker:cast(Worker, Msg, From),
                State#state{pending = Pending1};
            {{value, {'$call', Msg, From}}, Pending1} ->
                pool_worker:call(Worker, Msg, From),
                State#state{pending = Pending1}
        end
    };
handle_cast({'$call', Msg, From}, State = #state{available = [], pending = Pending}) ->
    {noreply, State#state{pending = queue:in({'$call', Msg, From}, Pending)}};
handle_cast({'$call', Msg, From}, State = #state{available = [H | T], pending = _Pending}) ->
    pool_worker:call(H, Msg, From),
    {noreply, State#state{available = T}};
handle_cast({'$cast', Msg, From}, State = #state{available = [], pending = Pending}) ->
    {noreply, State#state{pending = queue:in({'$cast', Msg, From}, Pending)}};
handle_cast({'$cast', Msg, From}, State = #state{available = [H | T], pending = _Pending}) ->
    pool_worker:cast(H, Msg, From),
    {noreply, State#state{available = T}};
handle_cast({add_pool_worker, Num}, State = #state{callback = Callback}) ->
    Fun = fun(_N) ->
        pool_worker:start_link(self(), Callback)
    end,
    lists:foreach(Fun, lists:seq(1, Num)),
    {noreply, State};
handle_cast(_Request, State) ->
    {noreply, State}.

handle_info({'DOWN', _Ref, process, Worker, _Reason}, State = #state {workers = Workers, available = Available }) ->
    {noreply, State #state {  workers = ordsets:del_element(Worker, Workers), available = ordsets:del_element(Worker, Available) }};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(Reason, State) ->
    io:format("Pool terminate :~n"
              "        state :~p~n"
              "        reason :~p~n",
              [State, Reason]),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @doc Init the pool worker
-spec(ready(PoolName :: term(), Worker :: pid()) -> term()).
ready(PoolName, Worker) ->
    gen_server:cast(PoolName, {ready, Worker}).

%% @doc Tell the mgr the pool worker is idle
-spec(idle(PoolName :: term(), Worker :: pid()) -> term()).
idle(PoolName, Worker) ->
    gen_server:cast(PoolName, {idle, Worker}).

clear_message_queue() ->
    receive
        {'$do', _, _} ->
            noop;
        {'$reply', _, _} ->
            noop;
        {'$error', _, _} ->
            noop
    after 0 ->
        noop
    end.