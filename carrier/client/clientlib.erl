%%%-------------------------------------------------------------------
%%% File    : clientlib.erl
%%% Author  : 
%%% Description : the client template:offer open/write/read/del function
%%%
%%% Created :  
%%%-------------------------------------------------------------------
-module(clientlib).
-include_lib("kernel/include/file.hrl").
-include("../include/egfs.hrl").
-include("filedevice.hrl").
-export([do_open/2, do_pread/3, do_pwrite/3, do_delete/1,
	 do_close/1, do_read_file/1, do_read_file_info/1,
	 get_file_name/1, get_file_size/1,
	 get_file_handle/2, delete_file/1]).
-compile(export_all).
-define(STRIP_SIZE, 8192).   % 8*1024
%-define(DATA_SERVER, {global, data_server}).

do_open(FileName, Mode) ->
    case gen_server:call(?META_SERVER, {open, FileName, Mode}) of
        {ok, FileID} ->
            FileDevice = #filedevice{filename = FileName, fileid = FileID},
	    {ok, FileDevice};
        {error, Why} ->
	    ?DEBUG("[Client, ~p]:Open file error:~p~n",[?LINE, Why]),
	    {error, Why}
    end.

do_pread(FileDevice, Start, Length) ->
    Start_addr = Start,
    {ok, FileSize} = get_file_length(FileDevice),
    End_will = Start + Length,
    if
	End_will < FileSize ->
	    End_addr = End_will;
	true ->
	    End_addr = FileSize
    end,

    ?DEBUG("[Client, ~p]:read Start is: ~p, readlength is: ~p~n",[?LINE, Start_addr, End_addr]),
    case read_them(FileDevice, {Start_addr, End_addr}) of
	{ok, FileID} ->
	    {ok, Hdl} = get_file_handle(read, FileID),
	    {ok, Binary} = file:pread(Hdl, 0, Length),
	    file:close(Hdl),
	    {ok, Binary};
	{error, Why} ->
	    {error, Why}
    end.

do_pwrite(FileDevice, Start, Bytes) ->
    ChunkIndex = Start div ?CHUNKSIZE,
    Size = size(Bytes),
    loop_write_chunks(FileDevice, ChunkIndex, Start, Size, Bytes).

do_read_file(FileName) ->
    ?DEBUG("[client, ~p]:test read begin at ~p~n~n", [?LINE, erlang:time()]),
    {ok, FileDevice} = do_open(FileName, r),
    {ok, FileInfo} = do_read_file_info(FileName),
    {Length, _, _, _, _} = FileInfo,
    do_pread(FileDevice, 0, Length),
    do_close(FileDevice),
    ?DEBUG("~n[client, ~p]:test read end at ~p~n", [?LINE, erlang:time()]),
    FileID = FileDevice#filedevice.fileid,
    {ok, FileLength} = get_file_size(FileID),
    {ok, Hdl} = get_file_handle(read, FileID),
    case file:pread(Hdl, 0, FileLength) of
	{ok, Binary} ->
	    delete_file(FileID),
	    ?DEBUG("[Client, ~p]:read file ok and return binary~n",[?LINE]),
	    {ok, Binary};
	{error, Reason} ->
	    ?DEBUG("[Client, ~p]:read file error ~p~n",[?LINE, Reason]),
	    {error, Reason}
    end.

do_read_file_info(FileName) ->
    case gen_server:call(?META_SERVER, {getfileattr, FileName}) of
        {ok, FileInfo} -> 
	    ?DEBUG("[Client, ~p]:get fileinfo ok~n",[?LINE]),
	    {ok, FileInfo};
        {error, Why} -> 
	    ?DEBUG("[Client, ~p]:get fileinfo error~p~n",[?LINE, Why]),
	    {error, Why}
    end.

do_delete(FileName) -> 
    case gen_server:call(?META_SERVER, {delete, FileName}) of
        {ok, _} -> 
	    ?DEBUG("[Client, ~p]:Delete file ok~n",[?LINE]),
	    ok;
        {error, Why} -> 
	    ?DEBUG("[Client, ~p]:Delete file error~p~n",[?LINE, Why]),
	    {error, Why};
	Any ->
	    ?DEBUG("[Client, ~p]:any info in Delete~p~n",[?LINE, Any]),
	    {error, Any}
    end.

do_close(FileDevice) ->
    FileID = FileDevice#filedevice.fileid,
    case gen_server:call(?META_SERVER, {close, FileID}) of
        {ok,_} ->
	    ?DEBUG("[Client, ~p]:Close file ok~n",[?LINE]), 
	    ok;
        {error, Why} -> 
	    ?DEBUG("[Client, ~p]:Close file error~p~n",[?LINE, Why]),
	    {error,Why}
    end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%          tools for read and write
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
get_file_name(FileID) ->
    <<Int1:64>> = FileID,
    lists:append(["/tmp/", integer_to_list(Int1)]). 

delete_file(FileID) ->
    FileName = get_file_name(FileID), 
    file:delete(FileName).

get_file_handle(Mode, FileID) ->
    FileName = get_file_name(FileID), 
    case Mode of
	write ->
	    case file:open(FileName, [raw, append, binary]) of
		{ok, Hdl} ->	
		    {ok, Hdl};
		{error, Why} ->
		    ?DEBUG("[Client, ~p]:Open file error:~p", [?LINE, Why]),
		    {error, Why}
    	    end;
	read ->
	    case file:open(FileName, [raw, read, binary]) of
		{ok, Hdl} ->	
		    {ok, Hdl};
		{error, Why} ->
		    ?DEBUG("[Client, ~p]:Open file error:~p", [?LINE, Why]),
		    {error, Why}
    	    end
    end.

get_file_size(FileID) ->
    FileName = get_file_name(FileID), 
    case file:read_file_info(FileName) of
	{ok, Facts} ->
	    {ok, Facts#file_info.size};
	_ ->
	    error
    end.

get_file_length(FileDevice) ->
    FileName  = FileDevice#filedevice.filename,
    {ok, FileInfo} = do_read_file_info(FileName),
    {FileSize, _, _, _, _} = FileInfo,
    {ok, FileSize}.

%get_chunk_info(FileID, ChunkIndex) -> 
%    gen_server:call(?META_SERVER, {locatechunk, FileID, ChunkIndex}).
	      
get_new_chunk(FileID, _ChunkIndex) ->
    gen_server:call(?META_SERVER, {allocatechunk, FileID}).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%          read
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
read_them(FileDevice, {Start, End}) ->
    ChunkIndex = Start div ?CHUNKSIZE,
    FileID = FileDevice#filedevice.fileid,
    delete_file(FileID),
    loop_read_chunks(FileID, ChunkIndex, Start, End).

loop_read_chunks(FileID, ChunkIndex, Start, End) when Start < End ->
    ?DEBUG("[Client, ~p]:Start is : ~p, ChunkIndex is: ~p~n",[?LINE, Start, ChunkIndex]),
    %{ok, ChunkID, Nodelist} = get_chunk_info(FileID, ChunkIndex),
    case gen_server:call(?META_SERVER, {locatechunk, FileID, ChunkIndex}) of
        {ok, ChunkID, Nodelist} ->	    
	    ?DEBUG("[Client, ~p]:Nodelist : ~p, ~n",[?LINE, Nodelist]),
	    [Node|_T] = Nodelist,
	    Begin = Start rem ?CHUNKSIZE,
	    Size1 = ?CHUNKSIZE - Begin,

	    if 
		Size1 + Start =< End ->
		    Size = Size1;
		true ->
		    Size = End - Start
	    end,
	    case read_a_chunk(FileID, ChunkIndex, ChunkID, Node, Begin, Size) of
		{ok, _FileID1} ->
		    ?DEBUG("[Client, ~p]: ~n",[?LINE]),
		    ChunkIndex2 = ChunkIndex + 1,
		    Start2 = Start + Size,
		    loop_read_chunks(FileID, ChunkIndex2, Start2, End);
		{error, Why} ->
		    {error, Why}
	    end;
	{error, _} ->
	    {error, callnotreturn}
    end;
loop_read_chunks(FileID, _, _, _) ->
    ?DEBUG("[Client, ~p]all chunks read finished!~n", [?LINE]),
    {ok, FileID}.

read_a_chunk(FileID, _ChunkInedx, ChunkID, Node, Begin, Size) when Size =< ?CHUNKSIZE ->
    ?DEBUG("[Client, ~p]:~p~n",[?LINE, ChunkID]),
    {ok, Host, Port} = gen_server:call(Node, {readchunk, ChunkID, Begin, Size}),
    {ok, Socket} = gen_tcp:connect(Host, Port, [binary, {packet, 2}, {active, true}]),
    Parent = self(),
    receive
        {tcp, Socket, Binary} ->
            {ok, Data_Port} = binary_to_term(Binary),
	    process_flag(trap_exit, true),
	    Child = spawn_link(fun() -> receive_it(Parent, Host, Data_Port, FileID) end),
	    loop_receive_ctrl(Socket, Child);
	{tcp_close, Socket} ->
            ?DEBUG("[Client, ~p]:read file closed~n",[?LINE]),
	    {error, net_error}
    end;    
read_a_chunk(FileID, _, _, _, _, _) ->
    {ok, FileID}.

loop_receive_ctrl(Socket, Child) ->
    receive
	{finish, Child, Len} ->	
	    ?DEBUG("[Client, ~p]:---->read a chunk, size is ~p.~n",[?LINE, Len]),
	    {ok, Len};
        {tcp, Socket, Binary} -> 
            Term = binary_to_term(Binary),
	    case Term of
		{stop, Why} ->	    	    
		    ?DEBUG("[Client, ~p]:stop ctrl message from dataserver~n",[?LINE]),
		    Child ! {stop, self(), Why},
		    {error, stop};
		{finish, _, Len} ->
		    ?DEBUG("[Client, ~p]:have write ~p bytes~n",[?LINE, Len]),
		    {ok, Len};
		Any ->
		    ?DEBUG("[Client, ~p]:message from data_server!~p~n",[?LINE, Any]),
		    loop_receive_ctrl(Socket, Child)
	    end;
	{error, Child, Why} ->
	    ?DEBUG("[Client, ~p]:data receive socket error!~p~n",[?LINE, Why]),
	    {error, Why};
	{'EXIT', _, normal} ->
	    ?DEBUG("[Client, ~p]:exit~n",[?LINE]),
	    loop_receive_ctrl(Socket, Child);
	{tcp_closed, _} ->	    
	    ?DEBUG("[Client, ~p]:tcp_closed~n",[?LINE]),
	    loop_receive_ctrl(Socket, Child);	    
	Any ->
	    ?DEBUG("[Client, ~p]:unknow messege!:~p~n",[?LINE, Any]),
	    loop_receive_ctrl(Socket, Child)
    end.

receive_it(Parent, Host, Data_Port, FileID) ->
    {ok, DataSocket} = gen_tcp:connect(Host, Data_Port, [binary, {packet, 2}, {active, true}]),
    {ok, Hdl} = get_file_handle(write, FileID),
    loop_recv_packet(Parent, DataSocket, Hdl, 0),
    file:close(Hdl).
    
loop_recv_packet(Parent, DataSocket, Hdl, Len) ->
    receive
	{tcp, DataSocket, Data} ->
	    write_data(Data, Hdl),
	    Len2 = Len + size(Data),
	    loop_recv_packet(Parent, DataSocket, Hdl, Len2);
	{tcp_closed, DataSocket} ->
	    Parent ! {finish, self(), Len};
	{stop, Parent, _Why} ->
	    ?DEBUG("[Client, ~p]:client close the datasocket~n",[?LINE]),
	    gen_tcp:close(DataSocket),
	    ?DEBUG("[Client, ~p]:client close",[?LINE]);
	_Any ->	    
	    ?DEBUG("[Client, ~p]:receive 'any' message in receive packet!~n",[?LINE])
    end.

write_data(Data, Hdl) ->
    file:write(Hdl, Data).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%          write 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
loop_write_chunks(FileDevice, ChunkIndex, Start, Len, Bytes) when Len > 0 ->
    Begin = Start rem ?CHUNKSIZE,
    Size1 = ?CHUNKSIZE - Begin,

    if
	Size1 > Len ->
	    Size = Len;
	true ->
	    Size = Size1
    end,

    {Part, Left} = split_binary(Bytes, Size),
    case write_a_chunk(FileDevice, ChunkIndex, Begin, Size, Part) of
	{ok, FileDevice1} ->
	    Start2 = Start + Size,
	    Len2 = Len - Size,
	    loop_write_chunks(FileDevice1, ChunkIndex, Start2, Len2, Left);
	{error, Why} ->
	    {error, Why}
    end;
loop_write_chunks(FileDevice, _, _, _, _) ->
    %?DEBUG("[Client, ~p]:the Binary has been written~n~n", [?LINE]).
    {ok, FileDevice}.

write_a_chunk(FileDevice, ChunkIndex, Begin, Size, Content) when Begin + Size =< ?CHUNKSIZE ->
    FileID = FileDevice#filedevice.fileid,

    case Begin of
	0 ->
	    ?DEBUG("[Client, ~p]:------------>you allocate a new chunk~n", [?LINE]),
	    {ok, ChunkID, Nodelist} = get_new_chunk(FileID, ChunkIndex),
	    FileDevice1 = FileDevice#filedevice{cursornodes = Nodelist, chunkid = ChunkID};
	    %?DEBUG("[Client, ~p]:record is:~p~n", [?LINE, FileDevice1]);
	_Any ->
	    FileDevice1 = FileDevice,
	    ChunkID = FileDevice1#filedevice.chunkid,
	    Nodelist = FileDevice1#filedevice.cursornodes
	    %?DEBUG("[Client, ~p]:record is:~p~n", [?LINE, FileDevice1])
	    %{ok, ChunkID, Nodelist} = get_chunk_info(FileID, ChunkIndex)
    end,

    [Node|T] = Nodelist,
    ?DEBUG("[Client, ~p]:begin: ~p, size: ~p in chunk!~n", [?LINE, Begin, Size]),
    ?DEBUG("[Client, ~p]:begin: ~p~n", [?LINE, Node]),
    {ok, Host, Port} = gen_server:call(Node, {writechunk, FileID, ChunkIndex, ChunkID, T}),
    {ok, Socket} = gen_tcp:connect(Host, Port, [binary, {packet, 2}, {active, true}]),
    Parent = self(),
    receive
        {tcp, Socket, Binary} ->
            {ok, Data_Port} = binary_to_term(Binary),
	    process_flag(trap_exit, true),
	    Child = spawn_link(fun() -> send_it(Parent, Host, Data_Port, Content) end),
	    Result = loop_send_ctrl(Socket, Child),
	    writechunk_returnvalue(Result, FileDevice1);
	{tcp_close, Socket} ->
            ?DEBUG("[Client, ~p]:write file closed~n",[?LINE]),
	    {ok, FileDevice1}
    end;    
write_a_chunk(_, _, Begin, Size, _) ->
    Write_Size = Begin + Size,
    ?DEBUG("[Client, ~p] write boundary(~p) bigger than Chunk_Size~n", [?LINE, Write_Size]),
    {error, "surpass the ChunkSize"}.

loop_send_ctrl(Socket, Child) ->
    receive
	{tcp_closed, Socket} ->	    
	    ?DEBUG("[Client, ~p]: write control socket is closed~n",[?LINE]),
	    {error, control_broken};
        {tcp, Socket, Binary} -> 
            Term = binary_to_term(Binary),
	    case Term of
		{stop, Why} ->	    	    
		    ?DEBUG("[Client, ~p]:stop ctrl message from dataserver~n",[?LINE]),
		    Child ! {stop, self(), Why},
		    {ok, stop};
		Any ->
		    ?DEBUG("[Client, ~p]:message from data_server!~p~n",[?LINE, Any]),
		    loop_send_ctrl(Socket, Child)
	    end;
	{finish, Child} ->	
	    ?DEBUG("[Client, ~p]:write a binary finished.~n",[?LINE]),
	    wait_for_report(Socket),
	    {ok, finish};
	    %% gen_tcp:send(Socket, term_to_binary({finish, "info"}));
	{error, Child, Why} ->
	    ?DEBUG("[Client, ~p]: child report that 'data receive error!'~p~n",[?LINE, Why]),
	    {error, "child error"};
	{'EXIT', _, normal} ->
	    %?DEBUG("[Client, ~p]: child exit normal~n",[?LINE]),
	    loop_send_ctrl(Socket, Child);
	_Any ->
	    %?DEBUG("[Client, ~p]:unknow messege!:~p~n",[?LINE, Any]),
	    loop_send_ctrl(Socket, Child)
    end.

wait_for_report(Socket) ->
    ?DEBUG("[Client, ~p]:waite for report~n",[?LINE]),
    receive 
	{tcp, Socket, Binary} ->
	    Term = binary_to_term(Binary),
	    case Term of
		{ok, report} ->
		    Term;
		{error, report} ->
		    Term;
		_Any ->
		    wait_for_report(Socket)
	    end;
	_Any ->
	    wait_for_report(Socket)
    end.

send_it(Parent, Host, Data_Port, Content) ->
    {ok, DataSocket} = gen_tcp:connect(Host, Data_Port, [binary, {packet, 2}, {active, true}]),
    loop_send_packet(Parent, DataSocket, Content).
    
loop_send_packet(Parent, DataSocket, Bytes) when size(Bytes) > ?STRIP_SIZE   ->
    {X, Y} = split_binary(Bytes, ?STRIP_SIZE),
    gen_tcp:send(DataSocket, X),
    loop_send_packet(Parent, DataSocket, Y);	
loop_send_packet(Parent, DataSocket, Bytes) when size(Bytes) > 0->
    gen_tcp:send(DataSocket, Bytes),
    gen_tcp:close(DataSocket),
    Parent ! {finish, self()};
loop_send_packet(Parent, DataSocket, _Bytes) ->
    gen_tcp:close(DataSocket),
    Parent ! {finish, self()}.

writechunk_returnvalue(Result, FileDevice) ->
    case Result of
	{ok, _FileDevice1} ->
	    {ok, FileDevice};
	{error, Why} ->
	    {error, Why};
	Any ->
	?DEBUG("[Client, ~p]:~p~n",[?LINE, Any])
	    
    end.
