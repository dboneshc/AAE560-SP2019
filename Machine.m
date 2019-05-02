classdef Machine < handle
   
    properties
        functional_group %property that assigns the machine to a specific class and therefore a supervisor
        machine_number %unique idenifer for each machine object instantiated
        full_name %functional_group.machine_number
        status %machine status is either 'idle' or 'running'
        machine_hours=0 %total hours worked on the work order
        max_machine_hours %maximum hours alowed by the supervisor
        op_status %lets the supervisor know the mode of the operation: 'set-up', 'run', 'complete'
        op_actual_duration=NaN %deterministic: op_actual_duration=op_plan_duration stochastich: op_actual_duration PDF determined
        op_setup_tracker=0
        set_actual=1 %tells the machine whether or not to calculate the actual duration
        
        %these are properties from the WO that the machine is currently working on
        wo_id
        op_plan_duration %duration from the routing within the WO object
        vendor_part %flag to determine if a vendor part is required
        
    end
    
    methods
        
        %Constructor Method
        function obj=Machine(functional_group,f_grp_vec,machine_number,full_name_vec,max_machine_hours) %('A',{m_grp_A.functional_group},1,[m_grp_A.machine_number],8)
            if ~isempty(f_grp_vec) && ~any(strcmp(f_grp_vec,functional_group))
                error(['No supervisor exists for functional group ',functional_group,'.']);
            end
            
            if any(strcmp(full_name_vec,{char([functional_group,'.',num2str(machine_number)])}))
                error(['Machine number ',num2str(machine_number),' already exits in functional group ',functional_group,'.']);
            end
            
            obj.functional_group=functional_group;
            obj.machine_number=machine_number;
            obj.max_machine_hours=max_machine_hours;
            obj.status='idle';
            obj.full_name={char([functional_group,'.',num2str(machine_number)])};
        end
        
        function [obj js_wos]=performWork(obj,js_wos)
                for i=1:length(obj)
                    
                %deterministic: op_actual_duration=op_plan_duration stochastich: op_actual_duration PDF determined
                obj(i).op_actual_duration=obj(i).op_plan_duration;

                %*** Stochastic Machining Process ***
%                 if obj(i).set_actual==1
%                     %this is the call for the stochastic process - this is the worst case 
%                     obj(i).op_actual_duration=poissrnd(obj(i).op_plan_duration);
%                     %set flag to 0, re-initialze to 1 once work is complete
%                     obj(i).set_actual=0;
%                 end
                
                %pull in the routing table for the specific WO
                r_table=js_wos(obj(i).wo_id).routing.Edges;
                %find the row index for the operation in the routing table
                row_index=find(strcmp(r_table.Operation,obj(i).functional_group));
                
                if strcmp(r_table.VendorPart(row_index),'required') || strcmp(r_table.VendorPart(row_index),'ordered')
                    %writing to the command line that the machine has the WO but not manufacturing
                    disp(['Machine Class performWork(): WO ',num2str(obj(i).wo_id),' Operation ',...
                        char(obj(i).functional_group),' part is ',char(r_table.VendorPart(row_index)),'.']);
                    
                    obj(i).op_status='set-up';
                    %adding a time unit based on timer wrapper iteration to machine_hours which is the time spent on the operation
                    obj(i).op_setup_tracker=obj(i).op_setup_tracker+1;
                    
                    %update work order information
                    js_wos(obj(i).wo_id).routing.Edges.Status{row_index}='set-up';
                    js_wos(obj(i).wo_id).routing.Edges.HoursWorked(row_index)=obj(i).op_setup_tracker;
                    js_wos(obj(i).wo_id).status='in-work';
                
                elseif obj(i).machine_hours<obj(i).op_actual_duration
                    obj(i).op_status='run';
                    obj(i).machine_hours=obj(i).machine_hours+1;
                    
                    %update work order information
                    js_wos(obj(i).wo_id).routing.Edges.Status{row_index}='run';
                    js_wos(obj(i).wo_id).routing.Edges.HoursWorked(row_index)=obj(i).machine_hours+obj(i).op_setup_tracker;
                    js_wos(obj(i).wo_id).status='in-work';
                    
                    %write to command line that the machine is working
                    disp(['Machine Class performWork(): Machine ',char(obj(i).full_name), ' is working on WO ',...
                        num2str(obj(i).wo_id),' Operation ',char(obj(i).functional_group),' with an actual duration of ',...
                        num2str(obj(i).op_actual_duration),'.']);
                end
                
                if obj(i).machine_hours>=obj(i).op_actual_duration %operation is assumed to be complete
                    
                    %write to command line that the machine has completed work
                    disp(['Machine Class performWork(): Machine ',char(obj(i).full_name), ' completed WO ',...
                        num2str(obj(i).wo_id),' Operation ',char(obj(i).functional_group),' with a duration of ',...
                        num2str(obj(i).machine_hours),'.']);
                    
                    %update work order information
                    js_wos(obj(i).wo_id).routing.Edges.Status{row_index}='complete';
                    js_wos(obj(i).wo_id).routing.Edges.HoursWorked(row_index)=obj(i).machine_hours+obj(i).op_setup_tracker;
                    js_wos(obj(i).wo_id).status='in-work';
                    
                    %re-initialize the object
                    obj(i).op_status='complete';
                    obj(i).status='idle';
                    obj(i).op_actual_duration=NaN; %resets actual work duration, in preparation for a new job
                    obj(i).op_setup_tracker=0;
                    obj(i).machine_hours=0;
                    obj(i).set_actual=1;
                end
            end
        end
    

    end
end