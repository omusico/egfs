%% This library is free software; you can redistribute it and/or modify
%% it under the terms of the GNU Lesser General Public License as
%% published by the Free Software Foundation; either version 2 of the
%% License, or (at your option) any later version.
%%
%% This library is distributed in the hope that it will be useful, but
%% WITHOUT ANY WARRANTY; without even the implied warranty of
%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
%% Lesser General Public License for more details.
%%
%% You should have received a copy of the GNU Lesser General Public
%% License along with this library; if not, write to the Free Software
%% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
%% USA
%%
%% $Id: eunit_proc.erl 273 2008-11-06 09:17:08Z rcarlsson $ 
%%
%% @author Richard Carlsson <richardc@it.uu.se>
%% @copyright 2006 Richard Carlsson
%% @private
%% @see eunit
%% @doc Test runner process tree functions

-module(eunit_proc).

-include("eunit.hrl").
-include("eunit_internal.hrl").

-export([start/4]).


-record(procstate, {ref, id, super, insulator, parent, order}).


%% Spawns test process and returns the process Pid; sends {done,
%% Reference, Pid} to caller when finished. See the function
%% wait_for_task/2 for details about the need for the reference.
%%
%% The `Super' process receives a stream of status messages; see
%% status_message/3 for details.

start(Tests, Order, Super, Reference)
  when is_pid(Super), is_reference(Reference) ->
    St = #procstate{ref = Reference,
		    id = [],
		    super = Super,
		    order = Order},
    spawn_group(local, #group{tests = Tests}, St).


%% Status messages sent to the supervisor process. (A supervisor does
%% not have to act on these messages - it can e.g. just log them, or
%% even discard them.) Each status message has the following form:
%%
%%   {status, Id, Info}
%%
%% where Id identifies the item that the message pertains to, and the
%% Info part can be one of:
%%
%%   {progress, 'begin', test | group}
%%       indicates that the item has been entered, and what type it is
%%
%%   {progress, 'end', {Status, Time::integer(), Output::io_list()}}
%%       Status = 'ok' | {error, Exception} | {skipped, Cause}
%%
%%       where Time is measured in milliseconds and Output is the data
%%       written to the standard output stream during the test; if
%%       Status is {skipped, Cause}, then Cause is a term thrown from
%%       eunit_test:run_testfun/1
%%
%%   {cancel, Descriptor}
%%       where Descriptor can be:
%%           timeout            a timeout occurred
%%           {blame, Id}        forced to terminate because of item `Id'
%%           {abort, Cause}     the test failed to execute
%%           {exit, Reason}     the test process terminated unexpectedly
%%           {startup, Reason}  failed to start a remote test process
%%
%%       where Cause is a term thrown from eunit_data:enter_context/4 or
%%       from eunit_data:iter_next/2, and Reason is an exit term from a
%%       crashed process
%%
%% Note that due to concurrent (and possibly distributed) execution,
%% there are *no* strict ordering guarantees on the status messages,
%% with one exception: a 'begin' message will always arrive before its
%% corresponding 'end' message.

status_message(Id, Info, St) ->
    St#procstate.super ! {status, Id, Info}.


%% @TODO implement synchronized mode for insulator/child execution

%% Ideas for synchronized mode:
%%
%% * At each "program point", i.e., before entering a test, entering a
%% group, or leaving a group, the child will synchronize with the
%% insulator to make sure it is ok to proceed.
%%
%% * The insulator can receive controlling messages from higher up in
%% the hierarchy, telling it to pause, resume, single-step, repeat, etc.
%%
%% * Synchronization on entering/leaving groups is necessary in order to
%% get control over things such as subprocess creation/termination and
%% setup/cleanup, making it possible to, e.g., repeat all the tests
%% within a particular subprocess without terminating and restarting it,
%% or repeating tests without repeating the setup/cleanup.
%%
%% * Some tests that depend on state will not be possible to repeat, but
%% require a fresh context setup. There is nothing that can be done
%% about this, and the many tests that are repeatable should not be
%% punished because of it. The user must decide which level to restart.
%%
%% * Question: How propagate control messages down the hierarchy
%% (preferably only to the correct insulator process)? An insulator does
%% not currenctly know whether its child process has spawned subtasks.
%% (The "supervisor" process does not know the Pids of the controlling
%% insulator processes in the tree, and it probably should not be
%% responsible for this anyway.)


%% ---------------------------------------------------------------------
%% Process tree primitives

%% A "task" consists of an insulator process and a child process which
%% handles the actual work. When the child terminates, the insulator
%% process sends {done, Reference, self()} to the process which started
%% the task (the "parent"). The child process is given a State record
%% which contains the process id:s of the parent, the insulator, and the
%% supervisor.

%% @spec (Type, (#procstate{}) -> () -> term(), #procstate{}) -> pid()
%%   Type = local | {remote, Node::atom()}

start_task(Type, Fun, St0) ->
    St = St0#procstate{parent = self()},
    %% (note: the link here is mainly to propagate signals *downwards*,
    %% so that the insulator can detect if the process that started the
    %% task dies before the task is done)
    F = fun () -> insulator_process(Type, Fun, St) end,
    case Type of
	local ->
	    %% we assume (at least for now) that local spawns can never
	    %% fail in such a way that the process does not start, so a
	    %% new local insulator does not need to synchronize here
	    spawn_link(F);
	{remote, Node} ->
	    Pid = spawn_link(Node, F),
	    %% See below for the need for the {ok, Reference, Pid}
	    %% message.
	    Reference = St#procstate.ref,
	    Monitor = erlang:monitor(process, Pid),
	    %% (the DOWN message is guaranteed to arrive after any
	    %% messages sent by the process itself)
	    receive
		{ok, Reference, Pid} ->
		    Pid;
		{'DOWN', Monitor, process, Pid, Reason} ->
		    %% send messages as if the insulator process was
		    %% started, but terminated on its own accord
		    Msg = {startup, Reason},
		    status_message(St#procstate.id, {cancel, Msg}, St),
		    self() ! {done, Reference, Pid}
	    end,
	    erlang:demonitor(Monitor, [flush]),
	    Pid
    end.

%% Relatively simple, and hopefully failure-proof insulator process
%% (This is cleaner than temporarily setting up the caller to trap
%% signals, and does not affect the caller's mailbox or other state.)
%%
%% We assume that nobody does a 'kill' on an insulator process - if that
%% should happen, the test framework will hang since the insulator will
%% never send a reply; see below for more.
%%
%% Note that even if the insulator process itself never fails, it is
%% still possible that it does not start properly, if it is spawned
%% remotely (e.g., if the remote node is down). Therefore, remote
%% insulators must always immediately send an {ok, Reference, self()}
%% message to the parent as soon as it is spawned.

%% @spec (Type, Fun::() -> term(), St::#procstate{}) -> ok
%%  Type = local | {remote, Node::atom()}

insulator_process(Type, Fun, St0) ->
    process_flag(trap_exit, true),
    Parent = St0#procstate.parent,
    if Type =:= local -> ok;
       true -> Parent ! {ok, St0#procstate.ref, self()}
    end,
    St = St0#procstate{insulator = self()},
    Child = spawn_link(fun () -> child_process(Fun(St), St) end),
    insulator_wait(Child, Parent, [], St).

%% Normally, child processes exit with the reason 'normal' even if the
%% executed tests failed (by throwing exceptions), since the tests are
%% executed within a try-block. Child processes can terminate abnormally
%% by the following reasons:
%%   1) an error in the processing of the test descriptors (a malformed
%%      descriptor, failure in a setup, cleanup or initialization, a
%%      missing module or function, or a failing generator function);
%%   2) an internal error in the test running framework itself;
%%   3) receiving a non-trapped error signal as a consequence of running
%%      test code.
%% Those under point 1 are "expected errors", handled specially in the
%% protocol, while the other two are unexpected errors. (Since alt. 3
%% implies that the test neither reported success nor failure, it can
%% never be considered "proper" behaviour of a test.) Abnormal
%% termination is reported to the supervisor process but otherwise does
%% not affect the insulator compared to normal termination. Child
%% processes can also be killed abruptly by their insulators, in case of
%% a timeout or if a parent process dies.
%%
%% The insulator is the group leader for the child process, and gets all
%% of its standard I/O. The output is buffered and associated with the
%% currently active test or group, and is sent along with the 'end'
%% progress message when the test or group has finished.

insulator_wait(Child, Parent, Buf, St) ->
    receive
	{io_request, From, ReplyAs, Req} when is_pid(From) ->
	    Buf1 = io_request(From, ReplyAs, Req, hd(Buf)),
	    insulator_wait(Child, Parent, [Buf1 | tl(Buf)], St);
	{progress, Child, Id, 'begin', Class} ->
	    status_message(Id, {progress, 'begin', Class}, St),
	    insulator_wait(Child, Parent, [[] | Buf], St);
	{progress, Child, Id, 'end', {Status, Time}} ->
	    Msg = {Status, Time, lists:reverse(hd(Buf))},
	    status_message(Id, {progress, 'end', Msg}, St),
	    insulator_wait(Child, Parent, tl(Buf), St);
	{cancel, Child, Id, Reason} ->
	    status_message(Id, {cancel, Reason}, St),
	    insulator_wait(Child, Parent, Buf, St);
	{abort, Child, Id, Cause} ->
	    exit_messages(Id, {abort, Cause}, St),
	    %% no need to wait for the {'EXIT',Child,_} message
	    terminate_insulator(St);
	{timeout, Child, Id} ->
	    exit_messages(Id, timeout, St),
	    kill_task(Child, St);
	{'EXIT', Child, normal} ->
	    terminate_insulator(St);
	{'EXIT', Child, Reason} ->
	    exit_messages(St#procstate.id, {exit, Reason}, St),
	    terminate_insulator(St);
	{'EXIT', Parent, _} ->
	    %% make sure child processes are cleaned up recursively
	    kill_task(Child, St)
    end.

kill_task(Child, St) ->
    exit(Child, kill),
    terminate_insulator(St).

%% Unlinking before exit avoids polluting the parent process with exit
%% signals from the insulator. The child process is already dead here.

terminate_insulator(St) ->
    %% messaging/unlinking is ok even if the parent is already dead
    Parent = St#procstate.parent,
    Parent ! {done, St#procstate.ref, self()},
    unlink(Parent),
    exit(normal).

%% send cancel messages for the Id of the "causing" item, and also for
%% the Id of the insulator itself, if they are different
exit_messages(Id, Cause, St) ->
    %% the message for the most specific Id is always sent first
    status_message(Id, {cancel, Cause}, St),
    case St#procstate.id of
	Id -> ok;
	Id1 -> status_message(Id1, {cancel, {blame, Id}}, St)
    end.

%% Child processes send all messages via the insulator to ensure proper
%% sequencing with timeouts and exit signals.

abort_message(Cause, St) ->
    St#procstate.insulator ! {abort, self(), St#procstate.id, Cause}.

cancel_message(Msg, St) ->
    St#procstate.insulator ! {cancel, self(), St#procstate.id, Msg}.

progress_message(Type, Data, St) ->
    St#procstate.insulator ! {progress, self(), St#procstate.id,
			      Type, Data}.

%% Timeout handling

set_timeout(Time, St) ->
    erlang:send_after(Time, St#procstate.insulator,
		      {timeout, self(), St#procstate.id}).

clear_timeout(Ref) ->
    erlang:cancel_timer(Ref).

with_timeout(undefined, Default, F, St) ->
    with_timeout(Default, F, St);
with_timeout(Time, _Default, F, St) ->
    with_timeout(Time, F, St).

with_timeout(infinity, F, _St) ->
    %% don't start timers unnecessarily
    {T0, _} = statistics(wall_clock),
    Value = F(),
    {T1, _} = statistics(wall_clock),
    {Value, T1 - T0};
with_timeout(Time, F, St) when is_integer(Time), Time > 16#FFFFffff ->
    with_timeout(16#FFFFffff, F, St);
with_timeout(Time, F, St) when is_integer(Time), Time < 0 ->
    with_timeout(0, F, St);
with_timeout(Time, F, St) when is_integer(Time) ->
    Ref = set_timeout(Time, St),
    {T0, _} = statistics(wall_clock),
    try F() of
	Value ->
	    %% we could also read the timer, but this is simpler
	    {T1, _} = statistics(wall_clock),
	    {Value, T1 - T0}
    after
	clear_timeout(Ref)
    end.

%% The normal behaviour of a child process is to trap exit signals. This
%% makes it easier to write tests that spawn off separate (linked)
%% processes and test whether they terminate as expected. The testing
%% framework is not dependent on this, however, so the test code is
%% allowed to disable signal trapping as it pleases.
%% Note that I/O is redirected to the insulator process.

%% @spec (() -> term(), #procstate{}) -> ok

child_process(Fun, St) ->
    process_flag(trap_exit, true),
    group_leader(St#procstate.insulator, self()),
    try Fun() of
	_ -> ok
    catch
	%% the only "normal" way for a child process to bail out is to
	%% throw an {eunit_abort, Reason} exception; any other exception
	%% will be reported as an unexpected termination of the test
	{eunit_abort, Cause} ->
	    abort_message(Cause, St),
	    exit(aborted)
    end.

%% @throws abortException()
%% @type abortException() = {abort, Cause::term()}

abort_task(Cause) ->
    throw({eunit_abort, Cause}).

%% Typically, the process that executes this code is trapping signals,
%% but it might not be - it is outside of our control, since test code
%% could turn off trapping. That is why the insulator process of a task
%% must be guaranteed to always send a reply before it terminates.
%%
%% The unique reference guarantees that we don't extract any message
%% from the mailbox unless it belongs to the test framework (and not to
%% the running tests) - it is not possible to use selective receive to
%% match only messages tagged with some pid in a dynamically varying set
%% of pids. When the wait-loop terminates, no such message should remain
%% in the mailbox.

wait_for_task(Pid, St) ->
    wait_for_tasks(sets:from_list([Pid]), St).

wait_for_tasks(PidSet, St) ->
    case sets:size(PidSet) of
	0 ->
	    ok;
	_ ->
	    %% (note that when we receive this message for some task, we
	    %% are guaranteed that the insulator process of the task has
	    %% already informed the supervisor about any anomalies)
	    Reference = St#procstate.ref,
	    receive
		{done, Reference, Pid} ->
		    %% (if Pid is not in the set, del_element has no
		    %% effect, so this is always safe)
		    Rest = sets:del_element(Pid, PidSet),
		    wait_for_tasks(Rest, St)
	    end
    end.


%% ---------------------------------------------------------------------
%% Separate testing process

tests(T, St) ->
    I = eunit_data:iter_init(T, St#procstate.id),
    case St#procstate.order of
	inorder -> tests_inorder(I, St);
	inparallel -> tests_inparallel(I, 0, St);
	{inparallel, N} when is_integer(N), N >= 0 ->
	    tests_inparallel(I, N, St)
    end.

set_id(I, St) ->
    St#procstate{id = eunit_data:iter_id(I)}.

tests_inorder(I, St) ->
    tests_inorder(I, 0, St).

tests_inorder(I, N, St) ->
    case get_next_item(I) of
	{T, I1} ->
	    handle_item(T, set_id(I1, St)),
	    tests_inorder(I1, N+1, St);
	none ->
	    N
    end.

tests_inparallel(I, K0, St) ->
    tests_inparallel(I, 0, St, K0, K0, sets:new()).

tests_inparallel(I, N, St, K, K0, Children) when K =< 0, K0 > 0 ->
    wait_for_tasks(Children, St),
    tests_inparallel(I, N, St, K0, K0, sets:new());
tests_inparallel(I, N, St, K, K0, Children) ->
    case get_next_item(I) of
	{T, I1} ->
	    Child = spawn_item(T, set_id(I1, St)),
	    tests_inparallel(I1, N+1, St, K - 1, K0,
			     sets:add_element(Child, Children));
	none ->
	    wait_for_tasks(Children, St),
	    N
    end.

spawn_item(T, St0) ->
    Fun = fun (St) ->
		  fun () -> handle_item(T, St) end
	  end,
    %% inparallel-items are always spawned locally
    start_task(local, Fun, St0).

get_next_item(I) ->
    eunit_data:iter_next(I, fun abort_task/1).

handle_item(T, St) ->
    case T of
	#test{} -> handle_test(T, St);
	#group{} -> handle_group(T, St)
    end.

handle_test(T, St) ->
    progress_message('begin', test, St),
    {Status, Time} = with_timeout(T#test.timeout, ?DEFAULT_TEST_TIMEOUT,
				  fun () -> run_test(T) end, St),
    progress_message('end', {Status, Time}, St),
    ok.

%% @spec (#test{}) -> ok | {error, eunit_lib:exception()}
%%                  | {skipped, eunit_test:wrapperError()}

run_test(#test{f = F}) ->
    try eunit_test:run_testfun(F) of
	{ok, _Value} ->
	    %% just throw away the return value
	    ok;
	{error, Exception} ->
	    {error, Exception}
    catch
	throw:WrapperError -> {skipped, WrapperError}
    end.

set_group_order(#group{order = undefined}, St) ->
    St;
set_group_order(#group{order = Order}, St) ->
    St#procstate{order = Order}.

handle_group(T, St0) ->
    St = set_group_order(T, St0),
    case T#group.spawn of
	undefined ->
	    run_group(T, St);
	Type ->
	    Child = spawn_group(Type, T, St),
	    wait_for_task(Child, St)
    end.

spawn_group(Type, T, St0) ->
    Fun = fun (St) ->
		  fun () -> run_group(T, St) end
	  end,
    start_task(Type, Fun, St0).

run_group(T, St) ->
    %% note that the setup/cleanup is outside the group timeout; if the
    %% setup fails, we do not start any timers
    Timeout = T#group.timeout,
    progress_message('begin', group, St),
    F = fun (T) -> enter_group(T, Timeout, St) end,
    try with_context(T, F) of
	{Status, Time} ->
	    progress_message('end', {Status, Time}, St)
    catch
	throw:Cause ->
	    cancel_message({abort, Cause}, St)
    end,
    ok.

enter_group(T, Timeout, St) ->
    with_timeout(Timeout, ?DEFAULT_GROUP_TIMEOUT,
		 fun () -> tests(T, St) end, St).

with_context(#group{context = undefined, tests = T}, F) ->
    F(T);
with_context(#group{context = #context{} = C, tests = I}, F) ->
    eunit_data:enter_context(C, I, F).

%% Implementation of buffering I/O for the insulator process. (Note that
%% each batch of characters is just pushed on the buffer, so it needs to
%% be reversed when it is flushed.)

io_request(From, ReplyAs, Req, Buf) ->
    {Reply, Buf1} = io_request(Req, Buf),
    io_reply(From, ReplyAs, Reply),
    Buf1.

io_reply(From, ReplyAs, Reply) ->
    From ! {io_reply, ReplyAs, Reply}.

io_request({put_chars, Chars}, Buf) ->
    {ok, [Chars | Buf]};
io_request({put_chars, M, F, As}, Buf) ->
    try apply(M, F, As) of
	Chars -> {ok, [Chars | Buf]}
    catch
	C:T -> {{error, {C,T,erlang:get_stacktrace()}}, Buf}
    end;
io_request({get_chars, _Prompt, _N}, Buf) ->
    {eof, Buf};
io_request({get_chars, _Prompt, _M, _F, _Xs}, Buf) ->
    {eof, Buf};
io_request({get_line, _Prompt}, Buf) ->
    {eof, Buf};
io_request({get_until, _Prompt, _M, _F, _As}, Buf) ->
    {eof, Buf};
io_request({setopts, _Opts}, Buf) ->
    {ok, Buf};
io_request({requests, Reqs}, Buf) ->
    io_requests(Reqs, {ok, Buf});
io_request(_, Buf) ->
    {{error, request}, Buf}.

io_requests([R | Rs], {ok, Buf}) ->
    io_requests(Rs, io_request(R, Buf));
io_requests(_, Result) ->
    Result.
