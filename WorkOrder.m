classdef WorkOrder < handle
    %UNTITLED Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        unique_id %this unique id she be monotomically increasing with WO creation
        due_date %initially provided by the customer, modified by the director as needed to avoid double booking of machines
        routing
        start_date %this is the start date calculated from the due 
        cp_duration %critical path duration based on deterministic routing
        end_date %this is the actual date that manufacturing completed, it determines if the JS has an on time delviery to the customer
        total_SV=0; %total schedule variance
        total_CV=0; %total cost variance
        status %this lets one know what the status of the WO is, possibilities are (new, planned, in work, closed, canceled)
        master_schedule %boolean property to know if a particular WO object has been added to the master schedule
        initial_start_edge_EF %an absolute starting value is needed to correctly update the master schedule
    end
    
    methods
        function obj = WorkOrder(due_date,vec_u_id)
            %UNTITLED Construct an instance of this class
            %   Detailed explanation goes here
            if nargin == 2
                if isnumeric(due_date) && due_date>0
                    obj.due_date=due_date;
                    obj.status='new';
                    obj.master_schedule=0;
                    obj.initial_start_edge_EF=NaN;
                    %assign unique id
                    if isempty(vec_u_id)
                        obj.unique_id=1;
                    else
                        obj.unique_id=max(vec_u_id)+1;
                    end
                else
                    error('Value must be numeric or inputs must equal 2.');
                end
            end
        end
        
        %a method to for the customer class to instantiate a new work
        %order- I think that Matt may have a way to do this from the
        %customer class???
        function obj=genWO(obj,new_wo,new_wo_due_date,vec_u_id)
            if new_wo==1
                wo=WorkOrder(new_wo_due_date,vec_u_id);
                obj=[obj; wo];
            end
        end
        
        %method to find critcal path through routing and populate start
        %date
        %a single WO object is passed in at a time
        function [start_date cp_duration]=calculateStartDate(obj)
            %use a temporary digraph to perform calculaitons
            temp_G=obj.routing;
            %convert weights to negative to fake Dijkstra's thm into
            %calculating the longest path
            temp_G.Edges.Weight=-temp_G.Edges.Weight;
            [cp_nodes cp_distance cp_edge_indicies]=shortestpath(temp_G,1,2);
            start_date=obj.due_date+cp_distance;
            cp_duration=abs(cp_distance);
        end
        
        function obj=updateDates(obj,revised_wo_dates)
            for i=1:length(revised_wo_dates.id)
                obj(revised_wo_dates.id(i)).start_date=revised_wo_dates.start_date(i);
                obj(revised_wo_dates.id(i)).end_date=revised_wo_dates.end_date(i);
                obj(revised_wo_dates.id(i)).master_schedule=1;
            end
        end
        
        function obj=closeWO(obj)
            for i=1:length(obj)
                %pull in the operation statuses
                wo_status_vec=obj(i).routing.Edges.Status;
                %check to see if all operations are complete
                if all(strcmp(wo_status_vec,'complete'))
                    %close the WO if all operations are complete
                    obj(i).status='closed';
                end
            end
        end
        
        %method to calculate SV and CV
        
        %create a function that calculates SV and total SV
        function obj = calcSV(obj)
            for i = 1:length(obj)
                planned = obj(i).routing.Edges.Weight;
                actual = obj(i).routing.Edges.HoursWorked;
                obj(i).routing.Edges.SV = planned - actual;
                obj(i).total_SV = sum(planned - actual);
            end
        end
        %baseline will have supervisor push working hours after job is
        %complete - qualitiative approach that is typical in most shops
        %good feedback will have it calculated for each loop thru the timer
    end
end