-module(pool_test).
-behaviour(gen_pool).

%% API
-export([
    start/0,
    start/1,
    sayhello/0,
    sleep/1,
    md5/1,
    call/0,
    call1/0
]).

-compile(export_all).
%% pool_master callbacks
-export([
    handle_cast/1,
    handle_call/2
]).

-define(SERVER, ?MODULE).

loop_run(_, 0) ->
    ok;
loop_run(Fun, N) ->
    Fun(),
    loop_run(Fun, N - 1).
t1() ->
    loop_run(
        fun() ->
            spawn(
                fun() ->
                    pool_test:call()
                end
            )
        end,
        16).
t3() ->
    loop_run(
        fun() ->
            spawn(
                fun() ->
                    pool_test:call(),
                    pool_test:call(),
                    pool_test:call(),
                    pool_test:call(),
                    pool_test:call2(1),
                    pool_test:call(),
                    pool_test:call(),
                    pool_test:call()
                end
            )
        end,
        10000).
t2() ->
    spawn(fun() ->pool_test:sleep(5) end),
    spawn(fun() ->pool_test:call() end),
    spawn(fun() ->pool_test:sleep(5) end),
    spawn(fun() ->pool_test:call() end),
    spawn(fun() ->pool_test:sleep(5) end),
    spawn(fun() ->pool_test:call() end),
    spawn(fun() ->pool_test:sleep(6) end),
    spawn(fun() ->pool_test:call() end),
    spawn(fun() ->pool_test:sleep(7) end),
    spawn(fun() ->pool_test:call() end),
    spawn(fun() ->pool_test:sleep(1) end),
    spawn(fun() ->pool_test:call() end),
    spawn(fun() ->pool_test:sleep(1) end),
    spawn(fun() ->pool_test:call() end),
    spawn(fun() ->pool_test:sleep(1) end),
    spawn(fun() ->pool_test:call() end),
    spawn(fun() ->pool_test:sleep(1) end),
    spawn(fun() ->pool_test:call() end),
    spawn(fun() ->pool_test:sleep(1) end),
    spawn(fun() ->pool_test:call() end),
    spawn(fun() ->pool_test:sleep(1) end),
    spawn(fun() ->pool_test:call() end).
t() ->
    loop_run(
        fun() ->
            spawn(
                fun() ->
                    pool_test:call(),
                    pool_test:call(),
                    pool_test:md5(10),
                    pool_test:md5(100),
                    pool_test:sleep(1),
                    pool_test:call(),
                    pool_test:md5(50000),
                    pool_test:call(),
                    pool_test:call()
                end
            )
        end,
        100),
    loop_run(
        fun() ->
            spawn(
                fun() ->
                    pool_test:md5(100),

                    pool_test:call(),
                    pool_test:md5(10000)
                end
            )
        end,
        100),
    loop_run(
        fun() ->
            spawn(
                fun() ->
                    pool_test:md5(10),
                    pool_test:call(),
                    pool_test:md5(100)
                end
            )
        end,
        100).
start(Num) ->
    {ok, _} = gen_pool:start_link(?SERVER, ?MODULE, Num).
start() ->
    Num = erlang:system_info(schedulers),
    start(Num).

sayhello() ->
    gen_pool:cast(?SERVER, sayhello).
sleep(N) ->
    gen_pool:cast(?SERVER, {sleep, N}).
md5(N) ->
    [gen_pool:cast(?SERVER, md5) || _D <- lists:seq(1, N)].
call() ->
    gen_pool:call(?SERVER, call).
call2(N) ->
    spawn( fun() -> gen_pool:call(?SERVER, {call2, N}) end  ).
call1() ->
    gen_pool:call(?SERVER, call1).

handle_cast(sayhello) ->
    io:format("Hello!~n");
handle_cast({sleep, N}) ->
    timer:sleep(1000 * N);
handle_cast(md5) ->
    erlang:md5("dfwefefwefefeddddvsvdsdvfcds你好ddddddddd").
handle_call(call, _From) ->
    dfdsfsdf;
handle_call({call2, N}, _From) ->
    timer:sleep(1000 * N);

handle_call(call1, _From) ->
    11111111.