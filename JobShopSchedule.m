classdef JobShopSchedule < handle
    %Job Shop Schedule class, holds job schedule
    %Based on a Activity on Arrow network schedule (e.g. PERT)
    
    properties
        master_schedule %directed graph that contains the master schedule
        start_node %the starting node number
        end_node %the ending node number
        wo_buffer %a buffer between work orders to provide ability to deliver on time
    end
    
    methods
        %Job Shop Schedule constructor method
        function obj = JobShopSchedule(wo_buffer) 
            %create an empty directed graph
            obj.master_schedule=digraph([],[]);
            obj.start_node={'Start'};
            obj.end_node={'End'};
            obj.wo_buffer=wo_buffer;
        end
        
        %add WOs to Job Shop master schedule
        function [master_schedule,revised_wo_dates,wo_ef_initial]=addWoToMasterSchedule(obj,wos_add_master)

            %check to ensure there are work orders to add
            if ~isempty(wos_add_master)
                %initialize master_schedule
                master_schedule=obj.master_schedule;
                %create revised_wo_dates structure
                revised_wo_dates=struct('id',[],'start_date',[],'end_date',[]);
                
                %organize work orders by due date
                %assumption is this is a FIFO shop prioritized by due date
                [temp index]=sort([wos_add_master.start_date]);
                if isempty(index)
                    index=1;
                end
                
                if isempty(obj.master_schedule.Nodes) %start date for first sorted WO is dependent on whether the master schedule is populated or now
                    t_start=0;
                else %find the critical path through the existing master schedule to determine t_start if the master schedule already has work in it
                    t_start=l_critcalPath(master_schedule,obj.start_node,obj.end_node);
                end
                
                %*** Serialize Work Orders *** applies FIFO scheduling based on due date
                for i=1:length(wos_add_master)
                    %the first work order starts at t_start
                    %populate a structure with revised information
                    %assuming all work order are performed serially
                    if i==1
                        %assume the first work order starts at t=0
                        %populate a structure with revised information
                        revised_wo_dates.id(i)=wos_add_master(index(i)).unique_id;
                        revised_wo_dates.start_date(i)=t_start;
                        revised_wo_dates.end_date(i)=revised_wo_dates.start_date(i)+wos_add_master(index(i)).cp_duration+obj.wo_buffer;
                    else
                        revised_wo_dates.id(i)=wos_add_master(index(i)).unique_id;
                        revised_wo_dates.start_date(i)=revised_wo_dates.end_date(i-1);
                        revised_wo_dates.end_date(i)=revised_wo_dates.start_date(i)+wos_add_master(index(i)).cp_duration+obj.wo_buffer;
                    end
                end
                %*** End Work Order Serialization***
                
                %*** Add Operations to Master Schedule***
                for i=1:length(wos_add_master)
                    %extract information to temp variable to make it
                    %easier to work with - note index is from the sort
                    %command based on due date above which enforces
                    %FIFO based on customer supplied due date

                    %wo unique id
                    u_id=wos_add_master(index(i)).unique_id;
                    %wo routing
                    tempG=wos_add_master(index(i)).routing;                    

                    %to simplify the creation of the master schedule, each routing start and end will
                    %have a start lead and an end lag, the weighting
                    %will be calculated from the revised serial dates

                    for j=1:length(tempG.Edges.EndNodes)
                        %for all routing node 1 is start and node 2 is
                        %end
                        rout_source=tempG.Edges.EndNodes(j,1);
                        rout_target=tempG.Edges.EndNodes(j,2);

                        if rout_source==1 && rout_target~=2 %edge is the first routing operation
                            %add in start lead edge
                            master_schedule=l_fun_leadEdge(obj,u_id,tempG,j,revised_wo_dates,i,master_schedule);
                            %add the first operation to the schedule
                            master_schedule=l_fun_addOperation(u_id,tempG,j,master_schedule);

                        elseif rout_source~=1 && rout_target==2 %edge is the last routing operation
                            %add the last operation to the schedule
                            master_schedule=l_fun_addOperation(u_id,tempG,j,master_schedule);
                            %add the buffer edge to the schedule
                            %!!! caution: this only works for operations in serial process !!!
                            master_schedule=l_fun_bufferEdge(u_id,tempG,j,obj,master_schedule);
                            %add the end lag edge to the schedule
                            master_schedule=l_fun_lagEdge(u_id,tempG,j,obj,master_schedule);

                        elseif rout_source==1 && rout_target==2 %single operation in the routing
                            %add in start lead edge
                            master_schedule=l_fun_leadEdge(obj,u_id,tempG,j,revised_wo_dates,i,master_schedule);
                            %add the only operation to the schedule
                            master_schedule=l_fun_addOperation(u_id,tempG,j,master_schedule);
                            %add the buffer edge to the schedule
                            %!!! caution: this only works for operations in serial process !!!
                            master_schedule=l_fun_bufferEdge(u_id,tempG,j,obj,master_schedule);
                            %add the end lag edge to the schedule
                            master_schedule=l_fun_addOperation(u_id,tempG,j,master_schedule);
                            
                        else %for all other operations in the WO
                            %add the operation to the schedule
                            master_schedule=l_fun_addOperation(u_id,tempG,j,master_schedule);
                        end

                    end
                    
                end
                %*** End Add Operations Master Schedule***
                
                %*** Perform Forward Pass - Calculate Early Start/Finish
                [master_schedule.Edges.ES,master_schedule.Edges.EF]=l_fun_fwdPass(master_schedule,obj);
                
                %*** Perform Backward Pass - Calculate Late Start/Finish
                [master_schedule.Edges.LS,master_schedule.Edges.LF]=l_fun_bwdPass(master_schedule,obj);
                
                %calculate the total slack
                master_schedule.Edges.TS=master_schedule.Edges.LS-master_schedule.Edges.ES;
                
                %setting initial early finish in order to get an
                %absolute value for updating the schedule later
                for i=1:length(wos_add_master)
                    if isnan(wos_add_master(i).initial_start_edge_EF)
                        wo_ef_initial.id(i)=wos_add_master(i).unique_id;
                        ms_st_ld_index=findedge(master_schedule,obj.start_node,{[num2str(wo_ef_initial.id(i)),'.1']});
                        wo_ef_initial.ef(i)=master_schedule.Edges.EF(ms_st_ld_index);
                    end
                end
            end
        end
        
        %update master schedule based on work performed
        function master_schedule=updateMasterSchedule(obj,wos_in_work,wos_planned)
            master_schedule=obj.master_schedule;
            
            %*** Start Update In-Work ***
            %loop thru wos_in_work and update edge weights
            for i=1:length(wos_in_work)
                wo_id=wos_in_work(i).unique_id; %WO unique ID
                wo_r_table=wos_in_work(i).routing.Edges; %WO routing table
                wo_cp=wos_in_work(i).cp_duration; %WO planned critical path duration
                
                %buffer consumed tracker
                buff_con_t=0;
                %loop through each operation in the WO
                for j=1:length(wo_r_table.Weight)
                    op_name=wo_r_table.Operation(j);
                    op_status=wo_r_table.Status(j);
                    op_s_node=wo_r_table.EndNodes(j,1);
                    op_t_node=wo_r_table.EndNodes(j,2);
                    op_planned_duration=wo_r_table.Weight(j);
                    op_hours_worked=wo_r_table.HoursWorked(j);
                    ms_s_node={[num2str(wo_id),'.',num2str(op_s_node)]};
                    ms_t_node={[num2str(wo_id),'.',num2str(op_t_node)]};
                    ms_index(j)=findedge(master_schedule,ms_s_node,ms_t_node);

                    %an operation in work with hours exceeding the plan will be written to master schedule
                    %OR completed operations actual hours will be written to the master schedule
                    if op_hours_worked > op_planned_duration || strcmp(op_status,'complete')
                        %updating the master schedule edge weight to the greater value
                        master_schedule.Edges.Weight(ms_index(j))=op_hours_worked;
                        %change the master schedule plot edge label accordingly
                        master_schedule.Edges.EdgeLabel(ms_index(j))={[num2str(wo_id),'.',char(op_name),'=',num2str(op_hours_worked)]};
                        %updating the total consumed buffer
                        buff_con_t=(op_planned_duration-op_hours_worked)+buff_con_t;
                    end
                end
                ms_buffer_index=findedge(master_schedule,{[num2str(wo_id),'.2']},{['Buffer.',num2str(wo_id)]});
                
                %adjusting the WO buffer and tracking the total consumed
                %!!! only if op_duration is exceeded or all operations are
                %complete !!!
                act_wo_cp=l_critcalPath(master_schedule,{[num2str(wo_id),'.1']},{[num2str(wo_id),'.2']});
                %only make changes to the buffer if the new critical path exceeds the old one or all the operations are closed to set the buffer to zero
                if (wo_cp-act_wo_cp)<0 || all(strcmp(wos_in_work(i).routing.Edges.Status,'complete')) 
                    if (wo_cp-act_wo_cp)<=-master_schedule.Edges.Weight(ms_buffer_index)  %WO has consumed all or more than the buffer
                        if (wo_cp-act_wo_cp)<-master_schedule.Edges.Weight(ms_buffer_index)
                            disp(['WO ',num2str(wo_id),' has consumed MORE than its allotted buffer.']);
                        else
                            disp(['WO ',num2str(wo_id),' has consumed its entire buffer.']);
                        end
                        master_schedule.Edges.Weight(ms_buffer_index)=0;
                        master_schedule.Edges.EdgeLabel(ms_buffer_index)={['Buffer.',num2str(wo_id),'=0']}; %less time has been consumed than allocated to the buffer
                    elseif (wo_cp-act_wo_cp)>-master_schedule.Edges.Weight(ms_buffer_index) && (wo_cp-act_wo_cp)<0 && ~all(strcmp(wos_in_work(i).routing.Edges.Status,'complete'))
                        %WO has consumed some of the buffer and not all the operations are complete
                        master_schedule.Edges.Weight(ms_buffer_index)=act_wo_cp-wo_cp;
                        master_schedule.Edges.EdgeLabel(ms_buffer_index)={['Buffer.',num2str(wo_id),'=',num2str(act_wo_cp-wo_cp)]};
                        disp(['WO ',num2str(wo_id),' has consumed some of its buffer.']);
                    else
                        %this statement should only be hit if the WO is
                        %complete
                        master_schedule.Edges.Weight(ms_buffer_index)=0;
                        master_schedule.Edges.EdgeLabel(ms_buffer_index)={['Buffer.',num2str(wo_id),'=0']};
                        disp(['WO ',num2str(wo_id),'s buffer has been set to zero.']);
                    end
                end
                master_schedule.Edges.BufTrack(ms_buffer_index)=buff_con_t;
                
                %used for extracting a sub-graph to get critical path
                    %to update Lead starts later
                    ms_index_start(i)=findedge(master_schedule,obj.start_node,{[num2str(wo_id),'.1']});
                    ms_index_buffer(i)=findedge(master_schedule,{[num2str(wo_id),'.2']},{['Buffer.',num2str(wo_id)]});
                    ms_index_end(i)=findedge(master_schedule,{['Buffer.',num2str(wo_id)]},obj.end_node);
            end
            
            %calculate critical path for only the updated master schedule
            %extract subgraph
            %find nodes based on ms_index
            sub_s=[master_schedule.Edges.EndNodes(ms_index,1);master_schedule.Edges.EndNodes(ms_index_start,1);...
                master_schedule.Edges.EndNodes(ms_index_buffer,1);master_schedule.Edges.EndNodes(ms_index_end,1)];
            sub_t=[master_schedule.Edges.EndNodes(ms_index,2);master_schedule.Edges.EndNodes(ms_index_start,2);...
                master_schedule.Edges.EndNodes(ms_index_buffer,2);master_schedule.Edges.EndNodes(ms_index_end,2)];
            sub_nodes=unique([sub_s;sub_t]);
            %extract the sub-graph of updated schedule
            subG=subgraph(master_schedule,sub_nodes);
            %calculate the critical path of the sub-graph
            ms_cp_updated=l_critcalPath(subG,obj.start_node,obj.end_node);
            %*** End Update In-Work ***
            
            %*** Update Planned ***
            %loop thru wos_planned and store early finishes and corresponding
            %master schedule row indicies
            for i=1:length(wos_planned)
                wo_id(i)=wos_planned(i).unique_id; %WO unique ID
                wo_r_table=wos_planned(i).routing.Edges; %WO routing table
                wo_cp=wos_planned(i).cp_duration; %WO planned critical path duration
                ms_row_index(i)=find(contains(master_schedule.Edges.EdgeLabel,{['Start.Lead.',num2str(wo_id(i))]})); %master schedule row index of the Start.Lead.WO graph edge
                ms_buf_row_index(i)=find(contains(master_schedule.Edges.EdgeLabel,{['Buffer.',num2str(wo_id(i))]})); %master schedule row index of the Start.Lead.WO graph edge
                wo_ef(i)=master_schedule.Edges.EF(ms_row_index(i)); %WO early finish in master schedule
            end
            
            %sort the early finish vector to find the next planned work order to occur
            [temp sort_index]=sort(wo_ef);
            
            %calculate the difference between critical path of the updated
            %portion of the master schedule and the earliest latest finish
            %this is the offset required to apply the Start Lead for the
            %planned WOs as well as the amount of buffer consumed by the
            %complete/in-work WOs
            lead_delta=ms_cp_updated-wo_ef(sort_index(1));
            total_buffer_consumed=ms_cp_updated-wo_ef(sort_index(1));

            if lead_delta>0
                master_schedule=l_fun_buf_consumed(lead_delta, sort_index, master_schedule, ms_row_index, total_buffer_consumed,ms_buf_row_index, obj, wo_id, wos_planned);
            end
            
            if lead_delta<0
                lead_delta=abs(lead_delta);
                master_schedule=l_fun_early_completion(lead_delta, sort_index, master_schedule, ms_row_index, ms_buf_row_index,wos_planned);
            end
            %*** End Update Planned ***

            %*** Perform Forward Pass - Calculate Early Start/Finish
            [master_schedule.Edges.ES,master_schedule.Edges.EF]=l_fun_fwdPass(master_schedule,obj);
            %*** Perform Backward Pass - Calculate Late Start/Finish
            [master_schedule.Edges.LS,master_schedule.Edges.LF]=l_fun_bwdPass(master_schedule,obj);
            %calculate the total slack
            master_schedule.Edges.TS=master_schedule.Edges.LS-master_schedule.Edges.ES;
        end
        
        %display what WO and Operation should be worked in the current clock cycle
        function planningMessage(obj,current_time,fun_grp_vec)
            ms_e_table=obj.master_schedule.Edges;
            
            r_index=[];
            for i=1:length(fun_grp_vec)
                r_index=[r_index; find(strcmp(ms_e_table.OperationWO,fun_grp_vec(i)))];
            end
            
            ES_time_index=find(ms_e_table.ES(r_index)<=current_time);
            LF_time_index=find(ms_e_table.LF(r_index(ES_time_index))>=current_time);
            
            if length(LF_time_index)>1
                for i=1:length(LF_time_index)
                    disp(['Planning Message: At time ', num2str(current_time),' WO ', num2str(ms_e_table.EdgeWO(r_index(ES_time_index(LF_time_index(i))))),...
                        ' Operation ',char(ms_e_table.OperationWO(r_index(ES_time_index(LF_time_index(i))))),' should be worked with an Early Start of ',...
                        num2str(ms_e_table.ES(r_index(ES_time_index(LF_time_index(i))))),'.']);
                end
            else
                disp(['Planning Message: At time ', num2str(current_time),' WO ', num2str(ms_e_table.EdgeWO(r_index(ES_time_index(LF_time_index)))),...
                        ' Operation ',char(ms_e_table.OperationWO(r_index(ES_time_index(LF_time_index)))),' should be worked with an Early Start of ',...
                        num2str(ms_e_table.ES(r_index(ES_time_index(LF_time_index)))),'.']);
            end
            
            ms_e_table(sort(r_index),{'EdgeWO','OperationWO','ES','EF','LS','LF'})
        end
    end
end

function critical_path=l_critcalPath(G,cp_source,cp_target)
    G.Edges.Weight=-G.Edges.Weight;
    [cp_nodes neg_cp_length cp_edge_indicies]=shortestpath(G,cp_source,cp_target);
    critical_path=abs(neg_cp_length);
end

function master_schedule=l_fun_leadEdge(obj,u_id,tempG,j,revised_wo_dates,i,master_schedule)
    %add in start lead edge
    source=obj.start_node;
    target={[num2str(u_id),'.',num2str(tempG.Edges.EndNodes(j,1))]};
    weight=revised_wo_dates.start_date(i);
    master_schedule=addedge(master_schedule,source,target,weight);
    %find new edge index
    edge_index=findedge(master_schedule,source,target);
    %adding edge labels to the master schedule Edges table
    master_schedule.Edges.EdgeLabel{edge_index}=['Start.Lead.',num2str(u_id),'=',num2str(weight)];
    %adding additional routing information to the Edges table
    master_schedule.Edges.EdgeWO(edge_index)=u_id;
    master_schedule.Edges.OperationWO{edge_index}=['StartLead'];
    master_schedule.Edges.RoutingEndNodes(edge_index,:)=[NaN tempG.Edges.EndNodes(j,1)];
    %add BufferTracking column set to NaN to the master schedule Edges
    master_schedule.Edges.BufTrack(edge_index)=NaN;
end

function master_schedule=l_fun_addOperation(u_id,tempG,j,master_schedule)
    source={[num2str(u_id),'.',num2str(tempG.Edges.EndNodes(j,1))]};
    target={[num2str(u_id),'.',num2str(tempG.Edges.EndNodes(j,2))]};
    weight=tempG.Edges.Weight(j);
    master_schedule=addedge(master_schedule,source,target,weight);
    %find new edge index
    edge_index=findedge(master_schedule,source,target);
    %adding edge labels to the master schedule Edges table
    master_schedule.Edges.EdgeLabel{edge_index}=[num2str(u_id),'.',char(tempG.Edges.Operation(j)),'=',num2str(weight)];
    %adding additional routing information to the Edges table
    master_schedule.Edges.EdgeWO(edge_index)=u_id;
    master_schedule.Edges.OperationWO{edge_index}=char(tempG.Edges.Operation(j));
    master_schedule.Edges.RoutingEndNodes(edge_index,:)=[tempG.Edges.EndNodes(j,1) tempG.Edges.EndNodes(j,2)];
    %add BufferTracking column set to NaN to the master schedule Edges
    master_schedule.Edges.BufTrack(edge_index)=NaN;
end

function master_schedule=l_fun_bufferEdge(u_id,tempG,j,obj,master_schedule)
    source={[num2str(u_id),'.',num2str(tempG.Edges.EndNodes(j,2))]};
    target={['Buffer.',num2str(u_id)]};
    weight=obj.wo_buffer;
    master_schedule=addedge(master_schedule,source,target,weight);
    %find new edge index
    edge_index=findedge(master_schedule,source,target);
    %adding edge labels to the master schedule Edges table
    master_schedule.Edges.EdgeLabel{edge_index}=['Buffer.',num2str(u_id),'=',num2str(weight)];
    %adding additional routing information to the Edges table
    master_schedule.Edges.EdgeWO(edge_index)=u_id;
    master_schedule.Edges.OperationWO{edge_index}='Buffer';
    master_schedule.Edges.RoutingEndNodes(edge_index,:)=[tempG.Edges.EndNodes(j,2) NaN];
    %add BufferTracking column set to NaN to the master schedule Edges
    master_schedule.Edges.BufTrack(edge_index)=obj.wo_buffer;
end

function master_schedule=l_fun_lagEdge(u_id,tempG,j,obj,master_schedule)
    source={['Buffer.',num2str(u_id)]};
    target=obj.end_node;
    weight=0;
    master_schedule=addedge(master_schedule,source,target,weight);
    %find new edge index
    edge_index=findedge(master_schedule,source,target);
    %adding edge labels to the master schedule Edges table
    master_schedule.Edges.EdgeLabel{edge_index}=['End.Lag.',num2str(u_id)];
    %adding additional routing information to the Edges table
    master_schedule.Edges.EdgeWO(edge_index)=u_id;
    master_schedule.Edges.OperationWO{edge_index}='EndLag';
    master_schedule.Edges.RoutingEndNodes(edge_index,:)=[NaN NaN];
    %add BufferTracking column set to NaN to the master schedule Edges
    master_schedule.Edges.BufTrack(edge_index)=NaN;
end

function master_schedule=l_fun_buf_consumed(lead_delta, sort_index, master_schedule, ms_row_index, total_buffer_consumed,ms_buf_row_index, obj, wo_id, wos_planned)
    
    %as buffer is removed from upstream WOs it reduces the amount of
    %lead_delta that is required to try to maintain the completion date -
    %this variable corrects for that (for i=1 this will be zero)
    lead_delta_offset=0;

    for i=1:length(sort_index)
        %update the weight of the start lead edge
        master_schedule.Edges.Weight(ms_row_index(sort_index(i)))=wos_planned(sort_index(i)).initial_start_edge_EF+lead_delta-lead_delta_offset;
        %update the EdgeLabel
        master_schedule.Edges.EdgeLabel(ms_row_index(sort_index(i)))={['Start.Lead.',...
            num2str(master_schedule.Edges.EdgeWO(ms_row_index(sort_index(i)))),'=',...
            num2str(wos_planned(sort_index(i)).initial_start_edge_EF+lead_delta-lead_delta_offset)]};

        %update the buffer of the WO
        if total_buffer_consumed>0
            %determine the amount to reduce the buffer of the current WO
            if total_buffer_consumed>=master_schedule.Edges.Weight(ms_buf_row_index(sort_index(i)))
                lead_delta_offset=master_schedule.Edges.Weight(ms_buf_row_index(sort_index(i)))+lead_delta_offset;
                %reduce the total buffer consumed by the amount deducted
                %from the WO being re-scheduled
                total_buffer_consumed=total_buffer_consumed-master_schedule.Edges.Weight(ms_buf_row_index(sort_index(i)));
                %adjust the buffer accordingly
                master_schedule.Edges.Weight(ms_buf_row_index(sort_index(i)))=0;
                %adjust the buffer label
                master_schedule.Edges.EdgeLabel(ms_buf_row_index(sort_index(i)))={['Buffer.',num2str(master_schedule.Edges.EdgeWO(ms_buf_row_index(sort_index(i)))),'=',num2str(0)]};

            else
                lead_delta_offset=master_schedule.Edges.Weight(ms_buf_row_index(sort_index(i)))-total_buffer_consumed+lead_delta_offset;
                %adjust the buffer label
                master_schedule.Edges.EdgeLabel(ms_buf_row_index(sort_index(i)))=...
                    {['Buffer.',num2str(master_schedule.Edges.EdgeWO(ms_buf_row_index(sort_index(i)))),'=',...
                    num2str(master_schedule.Edges.Weight(ms_buf_row_index(sort_index(i)))-total_buffer_consumed)]};
                master_schedule.Edges.Weight(ms_buf_row_index(sort_index(i)))=master_schedule.Edges.Weight(ms_buf_row_index(sort_index(i)))-total_buffer_consumed;
                %reduce the total buffer consumed by the amount deducted
                %from the WO being re-scheduled
                total_buffer_consumed=0;
            end
        end
    end
end

function master_schedule=l_fun_early_completion(lead_delta, sort_index, master_schedule, ms_row_index, ms_buf_row_index, wos_planned)
    ct=1; %initialize the counter

    while lead_delta>0 || ct<length(sort_index)
        if lead_delta<=wos_planned(sort_index(ct)).initial_start_edge_EF
            %update the EdgeLabel
            master_schedule.Edges.EdgeLabel(ms_row_index(sort_index(ct)))=...
                {['Start.Lead.',num2str(master_schedule.Edges.EdgeWO(ms_row_index(sort_index(ct)))),...
                '=',num2str(wos_planned(sort_index(ct)).initial_start_edge_EF-lead_delta)]};

            %update the weight of the start lead edge
            master_schedule.Edges.Weight(ms_row_index(sort_index(ct)))=...
                wos_planned(sort_index(ct)).initial_start_edge_EF-lead_delta;

            %adjust the buffer label
            master_schedule.Edges.EdgeLabel(ms_buf_row_index(sort_index(ct)))=...
                {['Buffer.',num2str(master_schedule.Edges.EdgeWO(ms_buf_row_index(sort_index(ct)))),...
                '=',num2str(master_schedule.Edges.Weight(ms_buf_row_index(sort_index(ct)))+lead_delta)]};
            %update the buffer of the WO - just add the extra buffer to the
            %next WO to be worked, don't distribute it over all of the WOs
            master_schedule.Edges.Weight(ms_buf_row_index(sort_index(ct)))=...
                master_schedule.Edges.Weight(ms_buf_row_index(sort_index(ct)))+lead_delta;
            
            lead_delta=0;
        else %early complete was so great that it needs to be spread over multiple WOs
            warning('The operation or work order completed so soon that WO ',num2str(master_schedule.Edges.EdgeWO(ms_buf_row_index(sort_index(ct)))),...
                ' will exhaust is full Start Lead Edge duration to compensate.');
            
            temp_lead_edge=master_schedule.Edges.Weight(ms_row_index(sort_index(ct)));
            
                %update the EdgeLabel
                master_schedule.Edges.EdgeLabel(ms_row_index(sort_index(ct)))=...
                    {['Start.Lead.',num2str(master_schedule.Edges.EdgeWO(ms_row_index(sort_index(ct)))),...
                    '=0']};
                
                %update the weight of the start lead edge
                master_schedule.Edges.Weight(ms_row_index(sort_index(ct)))=0;
                
                %adjust the buffer label
                master_schedule.Edges.EdgeLabel(ms_buf_row_index(sort_index(ct)))=...
                    {['Buffer.',num2str(master_schedule.Edges.EdgeWO(ms_buf_row_index(sort_index(ct)))),...
                    '=',num2str(master_schedule.Edges.Weight(ms_buf_row_index(sort_index(ct)))+temp_lead_edge)]};
                
                %update the buffer of the WO
                master_schedule.Edges.Weight(ms_buf_row_index(sort_index(ct)))=...
                    master_schedule.Edges.Weight(ms_buf_row_index(sort_index(ct)))+temp_lead_edge;
                
                lead_delta=lead_delta-temp_lead_edge;
        end
        ct=ct+1;
    end
    
    if lead_delta>0
        error('An early completing operation or work order could not be fully adjusted, the master schedule is inaccurate.');
    end
    
end

function [ES,EF]=l_fun_fwdPass(master_schedule,obj)
    %fill the graph edges table with NaN values for ES & LS
    master_schedule.Edges.ES=NaN([length(master_schedule.Edges.Weight) 1]);
    master_schedule.Edges.EF=NaN([length(master_schedule.Edges.Weight) 1]);
    
    %*** Perform Forward Pass - Calculate Early Start/Finish
        s=successors(master_schedule,obj.start_node);
        for i=1:length(s)
            for j=1:length(master_schedule.Edges.Weight)
                if strcmp(master_schedule.Edges.EndNodes(j,1),obj.start_node) && strcmp(master_schedule.Edges.EndNodes(j,2),s(i))
                    master_schedule.Edges.ES(j)=0;
                    master_schedule.Edges.EF(j)=master_schedule.Edges.Weight(j);
                end
            end
        end

        %brute force loop through remaining edges to calculate ES and EF
        ct=1;
        while any(isnan(master_schedule.Edges.ES)) || any(isnan(master_schedule.Edges.EF))
            if isnan(master_schedule.Edges.ES(ct)) || isnan(master_schedule.Edges.EF(ct))
                %check preceeding edges have EF calculated
                node=master_schedule.Edges.EndNodes(ct,1);
                p=predecessors(master_schedule,node);
                for i=1:length(p)
                    for j=1:length(master_schedule.Edges.Weight)
                        if strcmp(master_schedule.Edges.EndNodes(j,1),p(i)) && strcmp(master_schedule.Edges.EndNodes(j,2),node)
                            EF(i)=master_schedule.Edges.EF(j);
                        end
                    end
                end

                %check to ensure that ES and EF can be calculated then calculate
                if ~any(isnan(EF))
                    master_schedule.Edges.ES(ct)=max(EF);
                    master_schedule.Edges.EF(ct)=max(EF)+master_schedule.Edges.Weight(ct);
                end
            end

            %increment counter or reset counter
            if ct>=length(master_schedule.Edges.ES)
                ct=1;
            else
                ct=ct+1;
            end

            %clear EF variable
            clear EF;
        end
        %*** End Forward Pass ***
        ES=master_schedule.Edges.ES;
        EF=master_schedule.Edges.EF;
end

function [LS,LF]=l_fun_bwdPass(master_schedule,obj)
    %fill the graph edges table with NaN values for LS & LF
    master_schedule.Edges.LS=NaN([length(master_schedule.Edges.Weight) 1]);
    master_schedule.Edges.LF=NaN([length(master_schedule.Edges.Weight) 1]);    

    %*** Perform Backward Pass - Calculate Late Start/Finish
    p=predecessors(master_schedule,obj.end_node);
    for i=1:length(p)
        for j=1:length(master_schedule.Edges.Weight)
            if strcmp(master_schedule.Edges.EndNodes(j,1),p(i)) && strcmp(master_schedule.Edges.EndNodes(j,2),obj.end_node)
                %typically late finish would be calc as follows
                %master_schedule.Edges.LF(j)=max(master_schedule.Edges.EF);
                %however all End Lag edges are set to zero
                %therefore the EF for the particular edge is used instead of the maximum function
                %the if statement ensures that the first task can't start the sch_res late and alread eat up all of the management reserve
                if master_schedule.Edges.EF(j)==0
                    master_schedule.Edges.LF(j)=master_schedule.Edges.EF(j);
                else
                    master_schedule.Edges.LF(j)=master_schedule.Edges.EF(j);
                end
                master_schedule.Edges.LS(j)=master_schedule.Edges.LF(j)-master_schedule.Edges.Weight(j);
            end
        end
    end

    %brute force loop through remaining edges to calculate LS and LF
    ct=1;
    while any(isnan(master_schedule.Edges.LS)) || any(isnan(master_schedule.Edges.LF))
        if isnan(master_schedule.Edges.LS(ct)) || isnan(master_schedule.Edges.LF(ct))
            %check preceeding edges have EF calculated
            node=master_schedule.Edges.EndNodes(ct,2);
            s=successors(master_schedule,node);
            for i=1:length(s)
                for j=1:length(master_schedule.Edges.Weight)
                    if strcmp(master_schedule.Edges.EndNodes(j,1),node) && strcmp(master_schedule.Edges.EndNodes(j,2),s(i))
                        LS(i)=master_schedule.Edges.LS(j);    
                    end
                end
%                             LS(i)=master_schedule.Edges.LS(find(ismember(G.Edges.EndNodes,[node s(i)],'rows')));
            end

            %check to ensure that ES and EF can be calculated then calculate
            if ~any(isnan(LS))
                master_schedule.Edges.LF(ct)=min(LS);
                master_schedule.Edges.LS(ct)=min(LS)-master_schedule.Edges.Weight(ct);
            end

            %clear LS variable
            clear LS;
        end

        %increment counter or reset it
        if ct>=length(master_schedule.Edges.ES)
            ct=1;
        else
            ct=ct+1;
        end
    end
    %*** End Backward Pass ***
    LS=master_schedule.Edges.LS;
    LF=master_schedule.Edges.LF;
end