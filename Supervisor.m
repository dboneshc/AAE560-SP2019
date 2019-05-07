classdef Supervisor < handle
    %Creates the Supervisor class
    %   Releases work to Machine Center, reports Work Complete to Work
    %   Order
    
    properties
       job_queue %structure that contains operations specific to the functional group supervised
       functional_group %this is the letter of the group of machine functions that the supervisor oversees, it also corresponds to the Routing/operation an individual machine performs
    end
    
    methods
        function obj = Supervisor(functional_group,fun_grp_vec) %Creates supervisor object
            %check to make sure that a supervisor is not already assigned to the functional group
            if ~any(strcmp(fun_grp_vec,functional_group))
                obj.functional_group=functional_group;
            else
                error(['A supervisor is already assigned to group ',functional_group,'.']);
            end
            obj.job_queue=struct('wo_id',[],'es',[],'ls',[],'ef',[],'lf',[],'duration',[]);
        end
        
        function obj=getWork(obj,ms_e_table)
            for i=1:length(obj)
                %clear out the job_queue object - concerned that a short table will "corrupt data"
                obj(i).job_queue=struct('wo_id',[],'es',[],'ls',[],'ef',[],'lf',[],'duration',[]);
                disp(['Supervisor Class getWork(): Supervisor ',char(obj(i).functional_group),' job queue:']);
                obj(i).job_queue=l_fun_getWork(ms_e_table,obj(i).functional_group,obj(i).job_queue);
                disp('Work Order:');
                obj(i).job_queue.wo_id
                disp('Early Start:');
                obj(i).job_queue.es
            end
        end
        
        function [f_grp_idle_machines obj js_wos]=assignWork(obj,f_grp_idle_machines,js_wos,i,current_time)
            %check to see if an idle machine just completed work - gather info
            
            %check the number of idle machines
            n_idle_machines=length(f_grp_idle_machines);
            %determine the number of available wo operations to be worked
            n_open_ops=0;
            for j=1:length(js_wos)
                %find the jth WO that contains the ith supervisor functional group
                index=find(strcmp(js_wos(j).routing.Edges.Operation,obj(i).functional_group));
                %sum the number of planned operations
                n_open_ops=sum(strcmp(js_wos(j).routing.Edges.Status(index),'planned'))+n_open_ops;
            end
            
            %assign work to the machines limited by either the # of machines or open operations
            for k=1:min([n_idle_machines, n_open_ops])
                
                ct=1; %assigned WO counter
                ct2=1; %job_queue counter
                while ct<=1 && ct2<=length(obj(i).job_queue.wo_id)  %counter inequality set to 1 b/c only a single operation will be allocated, the "k" loop is sequencing through idle machines - the while loop attempts to match an idle machine to a WO operation to be matched
                    %find the row index in work order routing edges table that corresponds to the current functional group of obj(i)
                    wo_op_r_index=find(strcmp(js_wos(obj(i).job_queue.wo_id(ct2)).routing.Edges.Operation,obj(i).functional_group));
                    
                    %first condition is that WO status is planned
                    %second condition is that the current time falls between the operation's early start and late start times determined by the master schedule
                    if strcmp(js_wos(obj(i).job_queue.wo_id(ct2)).routing.Edges.Status(wo_op_r_index),'planned') &&...
                        all([obj(i).job_queue.es(ct2)<=current_time, current_time<=obj(i).job_queue.ls(ct2)])
                    
                    %*** A 3rd condition is needed to check to ensure the
                    %previous operation is 'complete' ***
                    
                    %obj(i).job_queue.es(ct2)<=current_time %this only works for serial WOs and Operations       


                        %set the machine status to running
                        f_grp_idle_machines(k).status='running';
                        %populate machine with WO information require to perform job
                        f_grp_idle_machines(k).wo_id=obj(i).job_queue.wo_id(ct2);
                        f_grp_idle_machines(k).op_plan_duration=obj(i).job_queue.duration(ct2);
                        %determine the row that the WO operation lives in the WO routing table
                        row_index=find(strcmp(js_wos(obj(i).job_queue.wo_id(ct2)).routing.Edges.Operation,obj(i).functional_group));
                        f_grp_idle_machines(k).vendor_part=js_wos(obj(i).job_queue.wo_id(ct2)).routing.Edges.VendorPart(row_index);
                        
                        %display which machine, WO, op and time a machine was told to run
                        disp(['Supervisor Class assignWork(): Machine ',char(f_grp_idle_machines(k).full_name),' was set to run WO ',...
                            num2str(obj(i).job_queue.wo_id(ct2)),' Operation ',...
                            char(js_wos(obj(i).job_queue.wo_id(ct2)).routing.Edges.Operation(row_index)),' at time ',...
                            num2str(current_time),'.']);
                        
                        %initialize hours worked to zero in the machine when a new operations is assigned to it
                        f_grp_idle_machines(k).machine_hours=0;
                        
                        %update WO operation status to show 'released'
                        js_wos(obj(i).job_queue.wo_id(ct2)).routing.Edges.Status{row_index}='released';
                        
                        %update job queue to show which WO opertions have been released to machines
                        obj(i).job_queue.status{ct2}='released';
                         
                        ct=ct+1;
                    end
                    ct2=ct2+1;
                    
                    %this could use some thinking/debuging but a nice to have
%                     if ct2==length(obj(i).job_queue.wo_id) && k~=k(end)
%                         warning(['Supervisor ',obj.(i).functional_group,' may not have been able to assign work to idle machine ',num2str(f_grp_idle_machines(k).machine_number)]);
%                     end     
                end 
            end 
        end
    end  
end
function job_queue=l_fun_getWork(ms_e_table,fun_grp,job_queue)
    %search for row indicies from master schedule Edge table that
    %correspond to the supervisor's functional group
    row_index=find(strcmp(ms_e_table.OperationWO,fun_grp));
    
    %sort early start, save indicies to ensure operations are ordered correctly
    [temp s_index]=sort(ms_e_table.ES(row_index));
    
    job_queue.wo_id=ms_e_table.EdgeWO(row_index(s_index)); %work order id
    job_queue.es=ms_e_table.ES(row_index(s_index)); %early start
    job_queue.ls=ms_e_table.LS(row_index(s_index)); %late start
    job_queue.ef=ms_e_table.EF(row_index(s_index)); %early finish
    job_queue.lf=ms_e_table.LF(row_index(s_index)); %late finish
    job_queue.duration=ms_e_table.Weight(row_index(s_index)); %duration
    job_queue.duration=ms_e_table.Weight(row_index(s_index));%actual duration
    %add a blank status into the job_queue
    for i=1:length(job_queue.wo_id)
        job_queue.status{i}='';
    end
end