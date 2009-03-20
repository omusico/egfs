%% Author: zyb@fit
%% Created: 2009-1-4
%% Description: TODO: Add description to hostMonitor
-module(meta_monitor).

%%
%% Include files
%%
-include("../include/header.hrl").
-import(lists, [foreach/2]).
-import(meta_db,[select_all_from_Table/1,
                 delete_object_from_db/1,
                 detach_from_chunk_mapping/1,               
                 select_from_hostinfo/1,                
                 write_to_db/1]).
%%
%% Exported Functions
%%
%% -export([hello/0,test/0]).
%% -export([checkNodes/0,broadcast/0]).

-compile(export_all).

%%
%% API Functions
%%

%apply_after(Time,Module,Function,Arguments)


%%
%% Local Functions
%%
test() ->
    {ok,_Tref} = timer:apply_interval(1000,hostMonitor,hello,[]).


hello() ->
%%     timeCheck(10),
%%     timeCheck(4),
	io:format("hello,,~p~n",[now()]).

%%%%%%%%%%%%%==================================================================================================
%% heartbeat

decrease() ->
%%     io:format("in decrease function .~n"),
    Life_minus =
        fun(Hostinfo,Acc)->					%%Acc must return, to be the args of next function
%%                 io:format("in life minus fuction.~n"),                
                Newlife = Hostinfo#hostinfo.life-1,
%%                 io:format("Newlife: ,~p~n",[Newlife]),
                if Newlife =:= 0 ->
                       delete_object_from_db(Hostinfo),
                       detach_from_chunk_mapping(Hostinfo#hostinfo.hostname),
                       Acc;                   
                   true->
                       mnesia:write(Hostinfo#hostinfo{life = Newlife }),
                       Acc
                end
		end,
    OldAcc =[],
    Minus_All = fun() -> mnesia:foldl(Life_minus,OldAcc,hostinfo, write) end,
    mnesia:transaction(Minus_All).
    
%%     case meta_db:select_all_from_Table(hostinfo) of
%%         []->
%%             {no_host_yet};
%%         [_Any]->
%%             io:format("case have hostinfo"),
%%             case mnesia:transaction(Minus_All) of
%%                 {atomic, NewAcc} ->
%%                     {ok,NewAcc};
%%                 {aborted, _} ->
%%                     {error, "Mnesia Transaction Abort!"}
%%    			end
%% 	end.



%%%%%%%%%%%%%==================================================================================================
%%  replica.


%% check replica and notify dataserver to make replica,if need 
%% @spec check_replica(N)-> {ok,"MSG"} || {error,"MSG"}
%% N-> number of replica needed ,(include himself)

%% 1 check chunkmapping table , find  
check_replica(N)->
    error_logger:info_msg("in func check_replica,_replica num:~p~n",[N]),
    case meta_db:select_all_from_Table(hostinfo) of
        []->
            {error,"NO Dataserver connected to metaserver"};
        Hosts-> %%[{},{}]
            if length(Hosts)<N ->
                   {error,"not enough dataserver to make these replications possible"};
               true->
                   HostnameList = get_hostname_list(Hosts),                   
                   
                   FunCheckEveryChunkID = 
                       fun(ChunkMappingItem,Acc) ->                               
                               %%TODO: HOsts too many,                               
                               select_host(ChunkMappingItem,HostnameList,N),%% select_host, and call dataserver to do replica
                               Acc %%return value of Acc,                                                              
                       end,
                   
                   Fun = fun()->
                                 mnesia:foldl(FunCheckEveryChunkID,[],chunkmapping,write)
                         end,
                   mnesia:transaction(Fun)
            end
    end.

get_hostname_list([])->
    [];
get_hostname_list(Hosts)->
    [H|T] = Hosts,
    [H#hostinfo.hostname]++get_hostname_list(T).


%% -record(hostinfo,{hostname,nodename, freespace, totalspace, status,life}).
%% -record(chunkmapping, {chunkid, chunklocations(hostname)}).
select_host(ChunkMappingItem,HostnameList,N) ->
    Chunklocations = ChunkMappingItem#chunkmapping.chunklocations, %%[H1,H2]    
%%     DieHosts = Chunklocations--HostnameList,    meaningless, we can do it in another loop, like orphan check,    
    
    OptionHosts =HostnameList--Chunklocations,
    %%TODO: selection needed, discussible.
%%     Need = N-length(Chunklocations)+length(DieHosts),   
    Need = N-length(Chunklocations),
%%todo: source selecting policy,
    Src = lists:nth(crypto:rand_uniform(1,length(Chunklocations)+1),Chunklocations),
    SrcNode = meta_db:select_nodename_from_hostinfo(Src),
    case SrcNode of 
        []->
            {error,"src not exist"};
        _->
            if length(chunklocations) =:= 0 ->                   
                   {error,"no source,"};
               true->
                   notify_dataserver(OptionHosts,Need,ChunkMappingItem#chunkmapping.chunkid,SrcNode)
            end                                    
    end.
    

notify_dataserver(OptionHosts,Need,ID,SrcNode)->
    case Need of
        0 ->
            ok;
        Rest->
            %%TODO, select policy, random; first N; location            
            [H|T] = OptionHosts,
            gen_server:cast({data_server,SrcNode},{replica,H#hostinfo.hostname,ID}),
            notify_dataserver(T,Need-1,ID,SrcNode)    
    end.


%%%%%%%%%%%%%==================================================================================================
%% broadcast filemeta table 
%%
%%
%% broad cast bloomfilter of filemeta info , for data servers to delete their abandon chunkids.
broadcast() ->
    Mappings = select_all_from_Table(chunkmapping),
    MappingsNum = length(Mappings),
    if         
        (MappingsNum =< 0) ->
            {erroe, "no chunkid in chunkmapping table"};
        true ->
            _ChunkIdList = get_chunkid_from_chunkmapping(Mappings),
            ChunkMapping = lists:nth(1,Mappings),
            _FirstHost =lists:nth(1,ChunkMapping#chunkmapping.chunklocations), 
            %% use lib_chan & lib_bloom
            
            todo
            %%code:add_patha("d:/EclipseWorkS/edu.tsinghua.carrier/carrierV4/lib"),            
            %%{ok, DataWorkPid} = lib_chan:connect(FirstHost, ?DATA_PORT, dataworker,?PASSWORD,  {garbageCollect})
            %%TODO:
            
    end.
            
            
%% function for broadcast,
%% @spect get_chunckid_from_chunkmapping( Node#chunkmapping ) -> ChunkIDList :[chunk1,chunk2]
get_chunkid_from_chunkmapping(Nodes) ->
    [H|T] = Nodes,
    [H#chunkmapping.chunkid]++get_chunkid_from_chunkmapping(T).


%%=========================================================================================================

% find orphanchunk every day.  
%%  1 , hostdown, chunkmapping table record like {<<ID>>,[]} , delete from chunkmapping & filemeta.
%%  2 , deleted filemeta record, chunkid still @chunkmapping    , delete from chunkmapping
%%  3 ,  
%% 
do_find_orphanchunk()->
    % Get all chunks of chunkmapping table
    GetAllChunkIdList = 
        fun(ChunkMapping,Acm)->
                case ChunkMapping#chunkmapping.chunklocations of
                    []->
                        mnesia:delete_object(ChunkMapping),
                        %%TODO, delete filemeta record , or make a flag.
                        Acm;
                    _ ->
                        [ChunkMapping#chunkmapping.chunkid | Acm]
                end
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
                NodeIpList = meta_db:select_nodeip_from_chunkmapping(X),
                [meta_db:write_to_db({orphanchunk,X,Y}) || Y<-NodeIpList], %%TODO, delete orphan table after debug
                meta_db:delete_from_db({chunkmapping,X})
        end,
    [GetOrphanPair(X)||X<-ChunkNotInFilemeta].

