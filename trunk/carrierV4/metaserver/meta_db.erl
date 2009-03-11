%% Author: zyb
%% Created: 2008-12-22
%% Description: TODO: Add description to metaDB

-module(meta_db).
-import(lists, [foreach/2]).
-import(util,[for/3]).
%%
%% Include files
%%
-include("../include/header.hrl").
-include_lib("stdlib/include/qlc.hrl").
%%
%% Exported Functions
%%
%-export([]).
-compile(export_all).

%%
%% API Functions
%%


create_a_table()->
    mnesia:create_schema([node()]),
    mnesia:start(),
    mnesia:create_table(hostinfo, [{attributes, record_info(fields,hostinfo)},
                                      {disc_copies,[node()]}
                                     ]),
    mnesia:stop().

do_this_once() ->
    mnesia:start(),
     
    mnesia:create_table(filemeta, 	%table name 
                        [			
                         {attributes, record_info(fields, filemeta)},%table content
                         {disc_copies,[node()]}                         
                        ]
                       ),
    mnesia:create_table(chunkmapping, [{attributes, record_info(fields, chunkmapping)},
                                       {disc_copies,[node()]}
                                      ]),
    mnesia:create_table(hostinfo, [{attributes, record_info(fields,hostinfo)},
                                      {disc_copies,[node()]}
                                     ]),
    
    mnesia:create_table(metalog, [{attributes, record_info(fields,metalog)},
                                      {disc_copies,[node()]}
                                     ]),
    mnesia:create_table(orphanchunk, [{type,bag},{attributes, record_info(fields,orphanchunk)},
                                      {disc_copies,[node()]}
                                     ]),
    
    
    reset_example_tables(),

    LOG = #metalog{logtime = calendar:local_time(),logfunc="start_mnesia",logarg=[]},
    mnesia:wait_for_tables([filemeta,chunkmapping,hostinfo,metalog,orphanchunk], 14000),
    logF(LOG).


start_mnesia()->
    
    case mnesia:create_schema([node()]) of
        ok ->
            do_this_once();
        _ ->
            LOG = #metalog{logtime = calendar:local_time(),logfunc="start_mnesia",logarg=[]},
            mnesia:start(),
            mnesia:wait_for_tables([filemeta,chunkmapping,hostinfo,metalog,orphanchunk], 14000),
            logF(LOG)
    end,
    
    start_mnesia_ok.

%% Local Functions
%%


do(Q) ->
    F = fun() -> qlc:e(Q) end,
    {atomic, Val} = mnesia:transaction(F),
    Val.

example_tables() ->
    [
     %%{hostinfo,{data_server,lt@lt},{192,168,0,111},1000000,2000000,{0,100}},
     {filemeta,lib_uuid:gen(),"/",0,[],erlang:localtime(),erlang:localtime(),dir,[]}
    ].

clear_tables()->
    LOG = #metalog{logtime = calendar:local_time(),logfunc="cleart_tables/0",logarg=[]},
    logF(LOG),

    mnesia:clear_table(filemeta),    
    mnesia:clear_table(hostinfo),
    mnesia:clear_table(chunkmapping).

reset_example_tables()->
    mnesia:create_table(hostinfo, [{attributes, record_info(fields,hostinfo)},
                                      {disc_copies,[node()]}
                                     ]),
    F = fun() ->
		foreach(fun mnesia:write/1, example_tables())
		end,
    mnesia:transaction(F).

reset_tables() ->
    LOG = #metalog{logtime = calendar:local_time(),logfunc="reset_tables/0",logarg=[]},
    logF(LOG),
    mnesia:clear_table(dirmeta),
    mnesia:clear_table(filemeta),
    mnesia:clear_table(chunkmapping),    
    mnesia:clear_table(hostinfo),

    F = fun() ->
		foreach(fun mnesia:write/1, example_tables())
		end,
    mnesia:transaction(F).

%filemeta    {fileid	client}
%add item
add_filemeta_item(Fileid, FileName) ->
    LOG = #metalog{logtime = calendar:local_time(),logfunc="add_filemeta_item/2",logarg=[Fileid,FileName]},
    logF(LOG),
    Row = #filemeta{fileid=Fileid, filename=FileName, filesize=0, chunklist=[], 
                         createT=term_to_binary(erlang:localtime()), modifyT=term_to_binary(erlang:localtime())},
    F = fun() ->
		mnesia:write(Row)
	end,
    mnesia:transaction(F).



%add_orphan_item
add_orphan_item(Chunkid,Chunklocation)->
    I = #orphanchunk{chunkid=Chunkid,chunklocation=Chunklocation},
    F = fun() ->
		mnesia:write(I)
	end,
 	mnesia:transaction(F).


%% write a record 
%% 
write_to_db(X)->
    LOG = #metalog{logtime = calendar:local_time(),logfunc="write_to_db/1",logarg=[X]},
    logF(LOG),
    
    %io:format("inside write to db"),
    F = fun() ->
		mnesia:write(X)
	end,
    {atomic,Val}=mnesia:transaction(F),
    Val.

%% delete a record 
%%
delete_object_from_db(X)->
	LOG = #metalog{logtime = calendar:local_time(),logfunc="delete_object_from_db/1",logarg=[X]},
    logF(LOG),
    %io:format("inside delete from db"),
    F = fun() ->
                mnesia:delete_object(X)
        end,
    mnesia:transaction(F).


delete_from_db(X)->
    LOG = #metalog{logtime = calendar:local_time(),logfunc="delete_from_db/1",logarg=[X]},
    logF(LOG),
    %io:format("inside delete from db"),
    F = fun() ->
                mnesia:delete(X)
        end,
    mnesia:transaction(F).
  
delete_from_db(listrecord,[X|T])->
    delete_from_db(X),
    delete_from_db(listrecord,T);
delete_from_db(listrecord,[])->
	done.

delete_object_from_db(listrecord,[X|T])->
    delete_object_from_db(X),
    delete_object_from_db(listrecord,T);
delete_object_from_db(listrecord,[])->
	done.


delete_hostinfo_item(HostName) ->
	Oid = {hostinfo, HostName},
	F = fun() ->
		mnesia:delete(Oid)
	end,
	{atomic, Val} = mnesia:transaction(F),
	Val.

%%------------------------------------------------------------------------------------------
%% select function
%% all kinds 
%%------------------------------------------------------------------------------------------ 
select_all_from_Table(T)->    
    do(qlc:q([
              X||X<-mnesia:table(T)
              ])).  %result [L]
%%[ {},{},{},{}  ]



select_all_from_filemeta_byID(FileID) ->    %result [L]
    do(qlc:q([
              X||X<-mnesia:table(filemeta),X#filemeta.fileid =:= FileID
              ])).

select_all_from_filemeta_byName(FileName) ->
  do(qlc:q([
              X||X<-mnesia:table(filemeta),X#filemeta.filename =:= FileName
              ])).

select_from_hostinfo(Hostname)->
    do(qlc:q([
              X||X<-mnesia:table(hostinfo),X#hostinfo.hostname =:= Hostname
              ])).


select_chunkid_from_orphanchunk(Host) ->
    do(qlc:q([
              X#orphanchunk.chunkid||X<-mnesia:table(orphanchunk),X#orphanchunk.chunklocation =:= Host
              ])).


select_all_from_orphanchunk(Host) ->
    do(qlc:q([
              X||X<-mnesia:table(orphanchunk),X#orphanchunk.chunklocation =:= Host
              ])).


select_all_from_filemeta_ofDir(Dir)->
     do(qlc:q([
              X||X<-mnesia:table(filemeta),
                 string:str(X#filemeta.filename, Dir)>0
              ])).

%FileName - > fileid
% @spec select_fileid_from_filemeta(FileName) ->  fileid
% fileid -> binary().

select_hosts_from_chunkmapping_id(ChunkID) ->    
    do(qlc:q([X#chunkmapping.chunklocations||X<-mnesia:table(chunkmapping),X#chunkmapping.chunkid =:= ChunkID])).

select_filesize_from_filemeta(FileId) ->
	LOG = #metalog{logtime = calendar:local_time(),logfunc="select_filesize_from_filemeta/1",logarg=[FileId]},
    logF(LOG),    
    do(qlc:q([X#filemeta.filesize || X <- mnesia:table(filemeta),
                                   X#filemeta.fileid =:= FileId                                   
                                   ])).   %result [L]

select_chunklist_from_filemeta(FileId) ->
    LOG = #metalog{logtime = calendar:local_time(),logfunc="select_chunklist_from_filemeta/1",logarg=[FileId]},
    logF(LOG),    
    do(qlc:q([X#filemeta.chunklist || X <- mnesia:table(filemeta),
                                   X#filemeta.fileid =:= FileId                                   
                                   ])).   %result [L]

select_fileid_from_filemeta(FileName) ->
    LOG = #metalog{logtime = calendar:local_time(),logfunc="select_fileid_from_filemeta/1",logarg=[FileName]},
    logF(LOG),
    
    do(qlc:q([X#filemeta.fileid || X <- mnesia:table(filemeta),
                                   X#filemeta.filename =:= FileName                                   
                                   ])).   %result [L]

%% select_fileid_from_filemeta_s(FileName) ->
%%     LOG = #metalog{logtime = calendar:local_time(),logfunc="select_fileid_from_filemeta_s/1",logarg=[FileName]},
%%     logF(LOG),
%%     do(qlc:q([X#filemeta_s.fileid || X <- mnesia:table(filemeta_s),
%%                                    X#filemeta_s.filename =:= FileName                                   
%%                                    ])).   %result [L]

select_nodeip_from_chunkmapping(ChunkID) ->
    LOG = #metalog{logtime = calendar:local_time(),logfunc="select_nodeip_from_chunkmapping",logarg=[ChunkID]},
    logF(LOG),
    do(qlc:q([X#chunkmapping.chunklocations || X <- mnesia:table(chunkmapping),
                                   X#chunkmapping.chunkid =:= ChunkID
             ])).   %result [L]


select_item_from_chunkmapping_id(ChunkID) ->    
    do(qlc:q([X||X<-mnesia:table(chunkmapping),X#chunkmapping.chunkid =:= ChunkID])).





%clear chunks from filemeta
reset_file_from_filemeta(Fileid) ->
    LOG = #metalog{logtime = calendar:local_time(),logfunc="reset_file_from_filemeta",logarg=[Fileid]},
    logF(LOG),
    [{filemeta, FileID, FileName, _, _, TimeCreated, _, ACL }] =
    do(qlc:q([X || X <- mnesia:table(filemeta),
                                   X#filemeta.fileid =:= Fileid                                   
                                   ])),

	Row = {filemeta, FileID, FileName, 0, [], TimeCreated, term_to_binary(erlang:localtime()), ACL },
    F = fun() ->
		mnesia:write(Row)
	end,
    mnesia:transaction(F).

% detach_from_chunk_mapping
% arg, Host name
detach_from_chunk_mapping(Host) ->
    DelHost =
        fun(ChunkMapping, Acc) ->
                ChunkLoc = ChunkMapping#chunkmapping.chunklocations,
                Guard = lists:member(Host,ChunkLoc),
                if Guard =:= true ->
                       ChunkLocList = ChunkLoc -- [Host],
                       ok = mnesia:write(ChunkMapping#chunkmapping{chunklocations = ChunkLocList}),
                       if 
                           ChunkLocList =:= [] ->
                               Acc ++ [ChunkMapping#chunkmapping.chunkid];
                           true ->
                               Acc
                       end; 
                   true ->
                    	Acc   
                end
        end,
    DoDel = fun() -> mnesia:foldl(DelHost, [], chunkmapping, write) end,
    mnesia:transaction(DoDel).



%% powerfull log function
logF(X)->
    F = fun() ->
		mnesia:write(X)
	end,
mnesia:transaction(F).

%% --------------------------------------------------------------------
%% Function: 
%% Description: 
%% Returns: 
%% --------------------------------------------------------------------


%% --------------------------------------------------------------------
%% Function: reset_file_from_filemeta/1
%% Description: 
%% Argument: Fileid  @type <<binary:64>>
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%% --------------------------------------------------------------------


%%		TODO:  log of all function. 

todomodifyHostLocation() ->
    ModifyLoc =
        fun(ChunkMapping, Acc) when is_atom(ChunkMapping#chunkmapping.chunklocations)->
                ChunkLoc = ChunkMapping#chunkmapping.chunklocations,
                mnesia:write(ChunkMapping#chunkmapping{chunklocations = [ChunkLoc]}),
                Acc;
           (_, Acc) ->
                Acc
        end,
    ModifyFun = fun() -> mnesia:foldl(ModifyLoc, [], chunkmapping, write) end,
    mnesia:transaction(ModifyFun).



    
%% add this node'chunklocation to chunk mapping table. 
%% if chunkID in this node don't exist in table chunk mapping,  this chunkid is not added. (why?) 
%% 
do_register_dataserver(HostName,ChunkList)->
   AddHost =
        fun(ChunkMapping, Acc) ->
                ChunkID = ChunkMapping#chunkmapping.chunkid,                
                Guard = lists:member(ChunkID,Acc),                
                if Guard =:= true ->
%%                        Acc = ChunkList--[ChunkID],
                       ChunkLocations = 
                           lists:usort(ChunkMapping#chunkmapping.chunklocations++[HostName]),
                       
                       ok = mnesia:write(
                              ChunkMapping#chunkmapping{chunklocations = ChunkLocations}),
                       Acc--[ChunkID];
                   true ->
                    	Acc
                end
        end,
    DoAdd = fun() -> mnesia:foldl(AddHost, ChunkList, chunkmapping, write) end,
    case mnesia:transaction(DoAdd) of
        {atomic, UnusedChunkList} ->
            {ok, UnusedChunkList};
        {aborted, _} ->
            {error, "Mnesia Transaction Abort!"}
   end.



do_delete_filemeta_byID(FileID)->
    LOG = #metalog{logtime = calendar:local_time(),logfunc="do_delete_filemeta/1",logarg=[FileID]},
    logF(LOG),
    delete_from_db({filemeta,FileID}),				%return {atomic,ok} . always
    {ok,"File deleted"}.
    

% find orphanchunk every day.
do_find_orphanchunk()->
    % Get all chunks of chunkmapping table
    GetAllChunkIdList = 
        fun(ChunkMapping,Acm)->
                [ChunkMapping#chunkmapping.chunkid | Acm]
        end,
    DogetAllChunkIdList = fun() -> mnesia:foldl(GetAllChunkIdList, [], chunkmapping) end,
    {atomic, AllChunkIdList} = mnesia:transaction(DogetAllChunkIdList),
    
    % filter out used chunks according to filemeta table
	GetUsedChunkIdListInFilemeta =
        fun(FileMeta, Acc) ->                
                Acc--FileMeta#filemeta.chunklist                
        end,        
    DogetUsedChunkIdListInFilemeta = fun() -> mnesia:foldl(GetUsedChunkIdListInFilemeta, AllChunkIdList, filemeta) end,
    {atomic, ChunkNotInFilemeta} = mnesia:transaction(DogetUsedChunkIdListInFilemeta),
    
    
    % filter out used chunks according to filemeta_s table
%% 	GetUsedChunkIdListInFilemetaS =
%%         fun(FileMetaS, AcS) ->                
%%                 AcS--FileMetaS#filemeta_s.chunklist                
%%         end,        
%%     DogetUsedChunkIdListInFilemetaS = fun() -> mnesia:foldl(GetUsedChunkIdListInFilemetaS, ChunkNotInFilemeta, filemeta_s) end,
%%     {atomic, OrphanChunk} = mnesia:transaction(DogetUsedChunkIdListInFilemetaS),
    
    GetOrphanPair = 
        fun(X) ->
                NodeIpList = select_nodeip_from_chunkmapping(X),
                [write_to_db({orphanchunk,X,Y}) || Y<-NodeIpList],
                delete_from_db({chunkmapping,X})
        end,
    [GetOrphanPair(X)||X<-ChunkNotInFilemeta].

% delete orphanchunk record in orphanchunk table by host
do_delete_orphanchunk_byhost(HostProcName)->
	X = select_all_from_orphanchunk(HostProcName),
	io:format("~p ~n", [list_to_tuple(X)]),
	delete_object_from_db(listrecord,X).

% find orphanchunk in orphanchunk table by host
do_get_orphanchunk_byhost(HostProcName) ->
    select_all_from_orphanchunk(HostProcName).


%%====================================================================
%% add item into table

%% add file info to table: filemeta & chunkmapping
%%====================================================================
add_a_file_record(FileRecord, ChunkMappingRecords) ->
    error_logger:info_msg("~~~~ in add_a_file_record~~~~n"),
    CurrentT = erlang:localtime(),
    %%TODO: create time & modify time . . mode append,. 
    Row = FileRecord#filemeta{	createT=CurrentT, 
			                    modifyT=CurrentT,
                                tag = file,
                                parent = get_id(filename:dirname(FileRecord#filemeta.filename))
                             },
	F = fun() ->
		mnesia:write(Row),
		lists:foreach(fun mnesia:write/1, ChunkMappingRecords)   
	end,
    {atomic, Val} = mnesia:transaction(F),
    error_logger:info_msg("write into db success"),
	Val.




add_hostinfo_item(HostName, FreeSpace, TotalSpace, Status,From) ->
    io:format("in side add_hostiofo_item.~n"),
	Row = #hostinfo{hostname=HostName, freespace=FreeSpace, totalspace=TotalSpace, status=Status,life=?HOST_INIT_LIFE},
	io:format("From : ~p~n",[From]),
    
	case select_from_hostinfo(HostName) of
		[] -> 
            io:format("first time register of this host: ~p~n",[HostName]),    
			write_to_db(Row);
		[_Any] ->
            io:format("host with same name was deleted first,~p~n",[HostName]),
            delete_from_db({hostinfo,HostName}),            
            io:format("delete ok , begin to write,~n"),
            write_to_db(Row)
	end.



select_random_one_from_hostinfo()->
    Hosts = do(qlc:q([X#hostinfo.hostname||X<-mnesia:table(hostinfo)])),
	case length(Hosts) of
	    0 ->
			[];
		Number ->
			{A1,A2,A3}=now(),
			random:seed(A1,A2,A3), 
    		Position = random:uniform(Number),	
			[lists:nth(Position,Hosts)]
	end.



%%%%%%%%%%%%%from hiatus
get_tag(FileName) ->
    io:format("aaa??,~p~n",[FileName]),
    L = length(FileName),    
%%     io:format("~p~n",[L]),
    case (string:equal(string:right(FileName,1),"/"))andalso L>1 of
       true->           
           io:format("true,~p~n",[FileName]),
           get_tag(string:substr(FileName,1,L-1));
       false->
           io:format(",~p~n",[FileName]),
           Result = do(qlc:q([X#filemeta.tag||X<-mnesia:table(filemeta), X#filemeta.filename=:=FileName])),
           case Result of
               [] ->
                   null;
               [Tag] ->
                   Tag
           end;
        Any->
            io:format("wtf!,~p~n",[Any])
            
    end.


get_tag_by_id(ID) ->
    Result = do(qlc:q([X#filemeta.tag||X<-mnesia:table(filemeta), X#filemeta.fileid=:=ID])),
    case Result of
        [] ->
            null;
        [Tag] ->
            Tag
    end
.
get_name(ID) ->
    Result = do(qlc:q([X#filemeta.filename||X<-mnesia:table(filemeta), X#filemeta.fileid=:=ID])),
    case Result of
        [] ->
            null;
        [Name|_T] ->
            Name
    end
.

get_id(FileName) ->
    Result = do(qlc:q([X#filemeta.fileid||X<-mnesia:table(filemeta), X#filemeta.filename=:=FileName])),
    case Result of
        [] ->
            null;
        [ID|_T] ->
            ID
    end
.
get_time(ID) ->
    Result = do(qlc:q([{X#filemeta.createT,X#filemeta.modifyT}||X<-mnesia:table(filemeta), X#filemeta.fileid=:=ID])),
    case Result of
        [] ->
            null;
        [{CT,MT}|_T] ->
            {CT,MT}
    end
.
delete_rows([]) ->
    ok;
delete_rows(IDList) ->
    [Head|Left] = IDList,
    delete_one_row(Head),
    delete_rows(Left)
.
delete_one_row(ID) ->
    Row = {filemeta, ID},
    F = fun() ->
                mnesia:delete(Row)
        end,
    mnesia:transaction(F)
.


%% checked it's a dir before function called. 
get_all_dir_sub_files(FileName)->
    L = length(FileName),
    Result = do(qlc:q([
                               {X#filemeta.tag,X#filemeta.fileid,X#filemeta.filename}
                      		||X<-mnesia:table(filemeta), 
                              string:equal(string:left(X#filemeta.filename,L),FileName),
                              X#filemeta.filename =/= FileName
                      ])),
    Result.				%%[{}{}{}{}{}{}{}{}{}{}]
    

%% easier one , useing powerful qlc.
get_all_sub_files(FileID) ->
    case get_tag_by_id(FileID) of
        file ->
            [{file,FileID,get_name(FileID)}];		%% [{tag,id,name}]
        dir ->
            FileName = get_name(FileID),
            L = length(FileName),
            Result = do(qlc:q([
                               {X#filemeta.tag,X#filemeta.fileid,X#filemeta.filename}
                      		||X<-mnesia:table(filemeta), 
                              string:equal(string:left(X#filemeta.filename,L),FileName),
                              X#filemeta.filename =/= FileName
                      ])),
            Result;				%%[{}{}{}{}{}{}{}{}{}{}]
        null->
            [{wtf,wtf,wtf}]
    end.

%% hiatus version. 
%% get_all_sub_files(FileID) ->
%%     case meta_db:get_tag_by_id(FileID) of
%%         file ->
%%             [[FileID],[]];
%%         dir ->
%%             [DirectSubFile,DirectSubDir] = get_direct_sub_files(FileID),
%%             [DirectSubDir_File, DirectSubDir_Dir] = get_all_sub_files(list, DirectSubDir),
%%             [lists:append(DirectSubFile, DirectSubDir_File),lists:append(DirectSubDir, DirectSubDir_Dir)]
%%     end
%% .
%% 
%% get_all_sub_files(list, []) ->
%%     [[],[]];
%% get_all_sub_files(list, FileIDList) ->
%%     [Head|Left] = FileIDList,
%%     [HeadSubFile,HeadSubDir] = get_all_sub_files(Head),
%%     [LeftSubFile,LeftSubDir] = get_all_sub_files(list, Left),
%%     [lists:append(HeadSubFile, LeftSubFile),lists:append(HeadSubDir, LeftSubDir)]
%% .
%% seperate_file_dir([]) ->
%%     [[],[],[],[]];
%% seperate_file_dir(FileList) ->
%%     [{Tag, ID,Name}|Left] = FileList,
%%     [LeftFiles,LeftDirs,LeftFileNames,LeftDirNames] = seperate_file_dir(Left),
%%     case Tag of
%%         file ->
%%             [lists:append([ID],LeftFiles),LeftDirs,lists:append([Name],LeftFileNames),LeftDirNames];
%%         dir ->
%%             [LeftFiles,lists:append([ID],LeftDirs),LeftFileNames,lists:append([Name],LeftDirNames)]
%%     end
%% .
%% 


get_order_direct_sub_files(FileID) ->
    Q1 = qlc:q([
                {X#filemeta.tag,X#filemeta.fileid,X#filemeta.filename}
                      		||X<-mnesia:table(filemeta), X#filemeta.parent=:=FileID
                      ]),
    Q2 = qlc:keysort(1,Q1,{order,descending}), %% 1: filemeta.tag  descending:f>d, file(f) first,then dirs(d)    

    do(Q2).

get_direct_sub_files(FileID) ->
    Result = do(
               qlc:q([{X#filemeta.tag,X#filemeta.fileid,X#filemeta.filename}
                      		||X<-mnesia:table(filemeta), X#filemeta.parent=:=FileID
                      ])
               ),
	Result.



%% there's no "/" after DirName, 
add_new_dir(ID,DirName,ParentID) ->
    Row = #filemeta{fileid=ID,filename=DirName,filesize = -1 ,createT = calendar:local_time(),modifyT = calendar:local_time(),tag=dir,parent=ParentID,chunklist=[]},
    F = fun() ->
                mnesia:write(Row)
        end,
    mnesia:transaction(F)
.


%% spec add_heartbeat_info(HostName,State) -> {ok,_} |{error,_}
update_heartbeat(HostName,State) ->
    case select_from_hostinfo(HostName) of
        [Host]-> %%update            
            Row = Host#hostinfo{status = State,life = ?HOST_INIT_LIFE},
            write_to_db(Row),
            ok;
        []->
            error_logger:error_msg("no info of this host, neeeedreport,"),
            needreport
    
    end.





%% 
%% do_fix()->    
%%     [R] = select_all_from_filemeta_byName("/"),    
%%     New = R#filemeta{parent = []},
%%     write_to_db(New).

%% old_dofix()->
%%     X = select_all_from_Table(filemeta),%%[{},{},{}]
%%     dofix(X).
%% dofix(X) when X =:= [] ->
%%     ture;
%% dofix(X) ->
%%     [H|T] = X,
%%     New = H#filemeta{parent = get_id(filename:dirname(H#filemeta.filename))},
%%     write_to_db(New),
%%     dofix(T).
     
    
    
            