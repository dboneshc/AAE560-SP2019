clear all;
clear classes;
close all;
clc;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%-------------------------------------------------------------------------%
%                                MAIN.m                                   %
%-------------------------------------------------------------------------%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%                                                                         %
%   This script acts as the integrating wrapper for the SoS simulation...   
%                                                                         %
%                                                                         %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%-------------------------------------------------------------------------%
%                       1. CREATE SoS ARCHITECTURE                        %
%-------------------------------------------------------------------------%
%                                                                         %
%   This simulation will include a Job Shop (consisting of director(s),   %
%   supervisor(s), machine(s), and receiving), a defined number of        %
%   customers, and a defined number of vendors. This section instantiates % 
%   these systems, then developes the network that these systems use to   %
%   communicate (externally and internally)                               %
%                                                                         %
%   RESTRICTIONS:                                                         %
%   1. Number of machines must be divisible by number of supervisors      %
%                                                                         %
%-------------------------------------------------------------------------%
%   1.A Create Systems                                                    %
%-------------------------------------------------------------------------%

%   Create Job Shop (Director(s), Supervisor(s), Machine(s), & Receiving):
[dir, sup, mach, rec] = createJobShop(1,3,3,1);
%   In this case, a Job Shop was created with 1 Director, 2 Supervisors, 4
%   Machines, and 1 Receiving focal.

%   Create Vendor Base:
[ven] = createVendor(1,2,5,'n');
%   In this case, one Vendor is used.  This Vendor is an abstract
%   representation of a larger Vendor base, and has an early delivery
%   requirement of 2.

%   Create Customer Base:
[cust] = createCustomer(1);
%   In this case, one Customer is being used.  This Customer is an abstract
%   representation of a larger Customer base.
%
%
%-------------------------------------------------------------------------%
%   1.B Create Communication Network                                      %
%-------------------------------------------------------------------------%

%   Map the network via the CommunicationNetwork function:
comm_net = CommunicationNetwork(dir, cust, sup, mach, rec, ven);

%   Plot the network:
NetworkMeasures(comm_net);
%
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%-------------------------------------------------------------------------%
%                       2. GENERATE WORK ORDER(S)                         %
%-------------------------------------------------------------------------%
%                                                                         %
%   This simulation ...                                                   %
%                                                                         %
%   RESTRICTIONS:                                                         %
%   1.                                                                    %
%                                                                         %
%-------------------------------------------------------------------------%
%   2.A Create Work Order(s)                                              %
%-------------------------------------------------------------------------%

%Instantiate an empty work order object js_wos
js_wos=WorkOrder.empty;

%Now populate work order with desired number and due dates
% createWO(number of WO,...
[ js_wos, cust ] = createWO(2, 10, cust, js_wos);
%[ js_wos, cust ] = createWO(5, 20, cust, js_wos);


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%-------------------------------------------------------------------------%
%                       3. ROUTING WORK ORDER(S)                          %
%-------------------------------------------------------------------------%
%                                                                         %
%   This simulation ...                                                   %
%                                                                         %
%   RESTRICTIONS:                                                         %
%   1.                                                                    %
%                                                                         %
%-------------------------------------------------------------------------%
%   3.A Route through Director                                            %
%-------------------------------------------------------------------------%
%Director sets up routing
[js_wos] = routing( js_wos, dir );

%instantiate Job Shop Schedule object
%the value passed into the function is the buffer time the director would
%set between work orders
js_sch=JobShopSchedule(2);

%add WOs to master schedule
[js_sch.master_schedule,revised_wo_dates,wo_ef_initial]=addWoToMasterSchedule(js_sch,js_wos(masterSchedule(dir, js_wos)));
for i=1:length(wo_ef_initial.id)
    js_wos(wo_ef_initial.id(i)).initial_start_edge_EF=wo_ef_initial.ef(i);
end
clear wo_ef_initial
%update start and end dates and master_schedule flag
js_wos=updateDates(js_wos,revised_wo_dates);

%display the master_schedule before any operations are run Edges table
js_sch.master_schedule.Edges;

plot_master=1;

%plotting the graph of the network schedule - flag to plot is at top of code
if plot_master==1
    figure;
    h=plot(js_sch.master_schedule,'EdgeLabel',js_sch.master_schedule.Edges.EdgeLabel);
    %try to layout the graph a little more like a Gantt Chart
    layout(h,'layered','Direction','right','Sources',1);
    %layout(h,'force','WeightEffect','direct'); - won't work with 0 edge weights
    % % [HideNodeNames{1:numnodes(js_sch.master_schedule)}]=deal('');
    % %needs some work... labelnode(h,unique([source target]),HideNodeNames);
end

%-------------------------------------------------------------------------%
%   3.B Route Vendor and Job Shop                                         %
%-------------------------------------------------------------------------%

hours = 0;
max_hours = 12;
    
 while hours <= max_hours
     
     for i=1:length(js_wos)
        if sum(strcmp(js_wos(i).routing.Edges.Status,'complete')) < ...
            length(js_wos(i).routing.Edges.Operation)
                  
            while sum(strcmp(js_wos(i).routing.Edges.Status,'complete')) < ...
               length(js_wos(i).routing.Edges.Operation)
           
               if hours <= max_hours
                                      
               [ t, ven, js_wos, js_sch, sup, mach ] = ...
                   routeWOs(js_wos, js_sch, ven, sup, mach, hours);
               start(t);
               
               hours = hours +1;
               
               else
                   break                
               end

            end
           
        end
                
     end
       
        
    end

if plot_master==1
    figure;
    h1=plot(js_sch.master_schedule,'EdgeLabel',js_sch.master_schedule.Edges.EdgeLabel);
    %try to layout the graph a little more like a Gantt Chart
    layout(h1,'layered','Direction','right','Sources',1);
    %layout(h,'force','WeightEffect','direct'); - won't work with 0 edge weights
    % % [HideNodeNames{1:numnodes(js_sch.master_schedule)}]=deal('');
    % %needs some work... labelnode(h,unique([source target]),HideNodeNames);
end
