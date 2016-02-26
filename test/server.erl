-module(server).
-behaviour(pool).

%% API
-export([start/0]).

%% pool callbacks
-export([handle_cast/2, handle_call/2]).
-define(SERVER, ?MODULE).
-compile(export_all).

start_link() ->
    Num = erlang:system_info(schedulers),
    start_link(Num) .

start_link(Num) ->
    {ok, _} = pool:start_link(server, ?MODULE, Num).

request() ->
    pool:cast(?SERVER, request).

request1() ->
    pool:cast(?SERVER, request1).

request2() ->
    pool:call(?SERVER, request2).
request3() ->
    pool:call(?SERVER, request3).

handle_cast(request, _From) ->
    io:format("~p~n",["request"]);
handle_cast(request1, _From) ->
    io:format("~p~n",["request1"]).

handle_call(request2, _From) ->
    io:format("~p~n",["request2"]);
handle_call(request3, _From) ->
    io:format("~p~n",["request3"]).