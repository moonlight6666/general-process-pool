<strong><span style="font-size:18px;">ERLANG &nbsp;generic process pool .</span></strong><br />

<p>
	<br />
	
</p>
<p>
	use erlang behaviour
</p>
<br />

<h3>
	you can use like :
</h3>
-behaviour(pool).<br />
-export([handle_cast/2, handle_call/2]).<br />
-define(SERVER, ?MODULE).<br />

<p>
	-compile(export_all).
</p>
<p>
	<br />
	
</p>
start() -&gt;<br />
&nbsp; &nbsp; Num = erlang:system_info(schedulers),<br />
&nbsp; &nbsp; {ok, _} = pool:start_link(server, ?MODULE, Num).<br />
echo() -&gt;<br />
&nbsp; &nbsp; pool:cast(?MODULE, echo).<br />
now() -&gt;<br />
&nbsp; &nbsp; pool:call(?MODULE, call).<br />
sleep() -&gt;<br />
&nbsp; &nbsp; pool:call(?MODULE, sleep).<br />
&nbsp; &nbsp;&nbsp;<br />
handle_cast(echo, _From) -&gt;<br />
&nbsp; &nbsp; io:format(&quot;~p~n&quot;,[&quot;hello!&quot;]).<br />
<br />
handle_call(now, _From) -&gt;<br />
&nbsp; &nbsp; erlang:now();<br />
handle_call(sleep, _From) -&gt;<br />
&nbsp; &nbsp; timer:sleep(10000),<br />
&nbsp; &nbsp; io:format(&quot;sleep......~n&quot;).
