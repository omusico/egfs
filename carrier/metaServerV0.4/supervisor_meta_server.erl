-module(supervisor_meta_server).
-behaviour(supervisor).
-include("../include/egfs.hrl").
-export([start/0, 
	 start_link/1,
	 start_in_shell/0,
	 init/1]).

-define(NAME, {local, ?MODULE}).

start() ->
    spawn(fun() ->
		supervisor:start_link(?NAME, ?MODULE, _Arg = [])
	    end).

start_in_shell() ->
    {ok, Pid} = supervisor:start_link(?NAME, ?MODULE, _Arg = []),
    unlink(Pid).

start_link(Args) ->
    supervisor:start_link(?NAME, ?MODULE, Args).

init([]) ->
    ?DEBUG("starting meta server supervisor~n", []),
    {ok, {{one_for_one, 3, 10},
	   [{meta_server, 
	       {metagenserver, start, []},
	       permanent,
	       10000,
	       worker,
	       [metagenserver]}
	   ]}}.

