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
%% API
-export([
	start_link/2,
	stop/1,
	cast/2,
	call/3,
	call/4
]).

-export([
	init/2
]).

-record(state, {master, callback}).
-define(CALL_TIMEOUT, 6000).

-spec start_link(Master, Callback) -> Ret when
	Master :: pid(),
	Callback :: module(),
	Ret :: {ok, Pid :: pid()} | {error, Reason :: term()}.
start_link(Master, Callback) ->
	{ok, _} = proc_lib:start_link(?MODULE, init, [Master, Callback]).

-spec cast(Worker, Request) -> Ret when
	Worker :: pid(),
	Request :: term(),
	Ret :: ok.
cast(Worker, Request) ->
	Worker ! {'$cast', Request}.

-spec call(Worker, Request, From, Ref) -> Ret when
	Worker :: pid(),
	Request :: term(),
	From :: pid(),
	Ref :: reference(),
	Ret :: {reply, Reply :: term()} | {error, Reason :: term()}.
call(Worker, Request, Ref) ->
	call(Worker, Request, Ref, ?CALL_TIMEOUT).
call(Worker, Request, Ref, Timeout) ->
	Worker ! {'$call', Request, self(), Ref},
	receive
		{reply, Reply, Ref} ->
            {reply, Reply, Ref};
		{error, Reason, Ref} ->
            {error, Reason, Ref}
	after Timeout ->
		{error, timeout, Ref}
	end.

stop(Worker) ->
	erlang:send(Worker, '$stop').

init(Master, Callback) ->
	erlang:monitor(process, Master),
	gen_pool:ready(Master, self()),
	proc_lib:init_ack({ok, self()}),
	loop(#state{master = Master, callback = Callback}).

loop(State = #state{master = Master, callback = Callback}) ->
	receive
		{'$cast', Request} ->
			do({Callback, handle_cast, [Request]}, null),
            gen_pool:idle(Master, self()),
			loop(State);
		{'$call', Request, From, Ref} ->
			Ret = do({Callback, handle_call, [Request, From]}, Ref),
			erlang:send(From, Ret),
			loop(State);
		{'DOWN', _Ref, process, Master, Reason} ->
			io:format("Master shutdown: [~p]~n", [Reason]),
            stop;
		'$stop' ->
            stop;
		Other ->
			io:format("Receive unexpected msg: ~p~n", [Other]),
            loop(State)
	end.

apply(Fun) when is_function(Fun) ->
	Fun();
apply({M, F, A}) ->
	erlang:apply(M, F, A).

do(FunArgs, Ref) ->
	try apply(FunArgs) of
		Result ->
			{reply, Result, Ref}
	catch
		_ : Reason ->
			{error, Reason, Ref}
	end.