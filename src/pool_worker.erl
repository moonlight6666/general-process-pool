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

%% Generic worker pool worker.
-module(pool_worker).
-export([
    start_link/2,
    cast/3,
    call/3
]).
-export([
    init/2
]).

-record(state, {mgr, callback}).
-define(default_timeout, 6000).

start_link(Mgr, Callback) ->
    {ok, _} = proc_lib:start_link(?MODULE, init, [Mgr, Callback]).

cast(Pid, Msg, From) ->
    Pid ! {'$cast', Msg, From}.

call(Pid, Msg, From) ->
    Pid ! {'$call', Msg, From}.

init(Mgr, Callback) ->
    process_flag(trap_exit, true),
	pool:ready(Mgr, self()),
    proc_lib:init_ack({ok, self()}),
	loop(#state{mgr = Mgr, callback = Callback}).

loop(State = #state{mgr = Mgr, callback = Callback}) ->
    pool:idle(Mgr, self()),
    receive
        {'$cast', Request, From} ->
            do({Callback, handle_cast, [Request, From]}, []),
            loop(State);
        {'$call', Request, {CPid, Ref}} ->
            erlang:send(CPid, {'$do', {self(), Ref}}),
            receive
                {'$do_it', Ref} ->
                    Ret = do({Callback, handle_call, [Request, CPid]}, Ref),
                    erlang:send(CPid, Ret);
                _Other ->
                    io:format("worker : ~p~n",[_Other]),
                    noop
            after
                ?default_timeout ->
                    timeout
            end,
            loop(State);
        {'EXIT', Mgr, _Reason} ->
            io:format("pool_worker receive stop.~n"),
            stop;
        Other ->
            io:format("pool_worker receive unexpet msg : ~p.~n", [Other]),
            loop(State)
    end.

apply(Fun) when is_function(Fun) ->
    Fun();
apply({M, F, A}) ->
    erlang:apply(M, F, A).

do(Fun, Ref) ->
    try apply(Fun) of
        Result ->
            {'$reply', Result, Ref}
    catch
        _ : Reason ->
            {'$error', Reason, Ref}
    end.