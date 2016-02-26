<strong><span style="font-size:32px;">ERLANG &nbsp;generic process pool .</span></strong><br />

<p>
	<br />
	
</p>
<p>
	<span style="font-size:24px;">use erlang behaviour to build process pools quickly.</span>
</p>
<br />

<h3>
	you can use like :
</h3>
-module(server).<br />
-behaviour(pool).<br />
<br />
<br />
%% API<br />
-export([start/0]).<br />
<br />
<br />
%% pool callbacks<br />
-export([handle_cast/2, handle_call/2]).<br />
-define(SERVER, ?MODULE).<br />
-compile(export_all).<br />
<br />
<br />
start_link() -&gt;<br />
&nbsp; &nbsp; Num = erlang:system_info(schedulers),<br />
&nbsp; &nbsp; start_link(Num) .<br />
<br />
<br />
start_link(Num) -&gt;<br />
&nbsp; &nbsp; {ok, _} = pool:start_link(server, ?MODULE, Num).<br />
<br />
<br />
request() -&gt;<br />
&nbsp; &nbsp; pool:cast(?SERVER, request).<br />
<br />
<br />
request1() -&gt;<br />
&nbsp; &nbsp; pool:cast(?SERVER, request1).<br />
<br />
<br />
request2() -&gt;<br />
&nbsp; &nbsp; pool:call(?SERVER, request2).<br />
request3() -&gt;<br />
&nbsp; &nbsp; pool:call(?SERVER, request3).<br />
<br />
<br />
handle_cast(request, _From) -&gt;<br />
&nbsp; &nbsp; io:format(&quot;~p~n&quot;,[&quot;request&quot;]);<br />
handle_cast(request1, _From) -&gt;<br />
&nbsp; &nbsp; io:format(&quot;~p~n&quot;,[&quot;request1&quot;]).<br />
<br />
<br />
handle_call(request2, _From) -&gt;<br />
&nbsp; &nbsp; io:format(&quot;~p~n&quot;,[&quot;request2&quot;]);<br />
handle_call(request3, _From) -&gt;<br />
&nbsp; &nbsp; io:format(&quot;~p~n&quot;,[&quot;request3&quot;]).
