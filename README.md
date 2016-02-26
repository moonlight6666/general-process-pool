ERLANG  generic process pool .

use erlang behaviour

you can use like :
-behaviour(pool).
-export([handle_cast/2, handle_call/2]).
-define(SERVER, ?MODULE).
-compile(export_all).

start() ->
    Num = erlang:system_info(schedulers),
    {ok, _} = pool:start_link(server, ?MODULE, Num).
echo() ->
    pool:cast(?MODULE, echo).
now() ->
    pool:call(?MODULE, call).
sleep() ->
    pool:call(?MODULE, sleep).
    
handle_cast(echo, _From) ->
    io:format("~p~n",["hello!"]).

handle_call(now, _From) ->
    erlang:now();
handle_call(sleep, _From) ->
    timer:sleep(10000),
    io:format("sleep......~n").
 
