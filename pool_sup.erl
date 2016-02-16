%%%-------------------------------------------------------------------
%%% @author Sir
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 19. 十二月 2015 21:07
%%%-------------------------------------------------------------------
-module(pool_sup).

-behaviour(supervisor).

-export([start_link/1, start_link/2]).

-export([init/1]).

start_link(Name) ->
	start_link(Name, erlang:system_info(schedulers)).
start_link(Name, PCount) ->
    {ok, _} = supervisor:start_link({local, get_supversior_name(Name)}, ?MODULE, [Name, PCount]).

init([PoolName, PCount]) ->
	SupFlags = {one_for_one, 10, 10},
	Childs =
		[
			{PoolName, {pool_mgr, start_link, [PoolName]}, transient,
				16#ffffffff, worker, [pool_mgr]
			} |
			[
				{N, {pool_worker, start_link, [PoolName]}, transient, 16#ffffffff,
					worker, [pool_worker]}
				|| N <- lists:seq(1, PCount)
			]
		],
	{ok, {SupFlags, Childs}}.

get_supversior_name(Name) when is_atom(Name) ->
    list_to_atom(atom_to_list(Name) ++ "_sup").

