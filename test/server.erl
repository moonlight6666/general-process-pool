-module(server).
-behaviour(pool).

%% API
-export([start/0]).

%% pool callbacks
-export([handle_cast/2, handle_call/2]).
-define(SERVER, ?MODULE).
-compile(export_all).

start() ->
    Num = erlang:system_info(schedulers),
    {ok, _} = pool:start_link(server, ?MODULE, Num).

now() ->
    pool:call(?MODULE, call).
echo() ->
    pool:cast(?MODULE, echo).
sleep() ->
    pool:cast(?MODULE, sleep).
sleep1() ->
    pool:call(?MODULE, sleep).
md5(N) ->
    [pool:cast(?MODULE, md5) || _D<-lists:seq(1, N)].

handle_cast(echo, _From) ->
    _From ! pppppp,
    io:format("~p~n",["nihao!"]);
handle_cast(sleep, _From) ->
    _From ! pppppp,
    timer:sleep(7000),
    io:format("~p~n",["sleep!"]);
handle_cast(md5, _From) ->
    [erlang:md5("dfwefefwefefe") || _D <-lists:seq(1,100)].

handle_call(call, _From) ->
    io:format("call......~n"),
    erlang:now();
handle_call(sleep, _From) ->
    timer:sleep(10000),
    io:format("sleep......~n").