% ==============================================================================
% FILENAME: ev_routing_milp_time_dependent_v6.m
% VERSION: 6 (Dashboard updated with comfort graphs, Compute time added to summary tab, MTZ subtour (ln.281) elimination added.)
% ==============================================================================
clear; clc; close all;

% ------------------------------------------------------------------------------
% SECTION 1: DATA LOADING & PRE-PROCESSING
% ------------------------------------------------------------------------------
data_real = my_test_data_15_node_24_tslots_Ankara_Antalya();                % Real-time, dynamically changes with the start of program
data_real.name = 'Real-time Data';                                          % Naming data                      
data_fixed = my_fixed_data_with_same_nodes();                               % Fixed (historical) data, dated 15-07-2025
data_fixed.name = 'Fixed Data';                                             % Naming data
dataset_list = {data_real, data_fixed};                                     % Stores datasets in an array
results_list = cell(1, 2);                                                  % Preallocate results storage

for run_idx= 1:2                                                            % Loop dataset
    data = dataset_list{run_idx};
    
    fprintf('\n======================================================\n');
    fprintf('>>> RUNNING ANALYSIS FOR: %s <<<\n', data.name);
    fprintf('======================================================\n');

    data_forbase = data;                                                    % For duration objective (reference) data
    [N, ~, T_horizon] = size(data.E_dynamic);                               % Keeps all data parameters and just taking HVAC energy into account
    data_forbase.E_dynamic = repmat(data.E0, 1, 1, T_horizon);              % Replace dynamic energy with static energy for HVAC

    % ------------------------------------------------------------------------------
    % SECTION 2: OPTIMIZATION SOLVER CALLS
    % ------------------------------------------------------------------------------
    compute_start_time = tic;
    fprintf('Solving for Distance (Base)...\n');
    sol_distance = solve_ev_routing_milp(data_forbase, "distance");         % 1. Solve for MINIMUM DISTANCE
    sol_distance.solve_time = toc(compute_start_time);

    compute_start_time = tic;
    fprintf('Solving for Cost Objective (Economic)...\n');
    sol_cost = solve_ev_routing_milp(data, "cost");                         % 2. Solve for MINIMUM COST
    sol_cost.solve_time = toc(compute_start_time);
    
    compute_start_time = tic;
    fprintf('Solving for Time Objective (Fastest)...\n');
    sol_time = solve_ev_routing_milp(data, "time");                         % 3. Solve for MINIMUM TIME
    sol_time.solve_time = toc(compute_start_time);
    
    compute_start_time = tic;
    fprintf('Solving for Energy Objective (Greenest)...\n');
    sol_energy = solve_ev_routing_milp(data, "energy");                     % 4. Solve for MINIMUM ENERGY (Sustainability)
    sol_energy.solve_time = toc(compute_start_time);

    % ------------------------------------------------------------------------------
    % SECTION 3: ROUTE EXTRACTION
    % ------------------------------------------------------------------------------
    
    route_cost     = extract_route(sol_cost.x,     data.origin, data.dest); % Extracting route from solver
    route_time     = extract_route(sol_time.x,     data.origin, data.dest);
    route_energy   = extract_route(sol_energy.x,   data.origin, data.dest);
    route_distance = extract_route(sol_distance.x, data.origin, data.dest);
    
    % ------------------------------------------------------------------------------
    % SECTION 4: KPI CALCULATION & REPORTING
    % ------------------------------------------------------------------------------
    
    % --- Cost Route Metrics ---
    cost_charge_time = sum(sol_cost.t_ch);                                  % Cost route charging time
    cost_travel_time = sol_cost.total_time - cost_charge_time;              % Cost route travel time
    
    % --- Time Route Metrics ---
    time_charge_time = sum(sol_time.t_ch);                                  % Time route charging time
    time_travel_time = sol_time.total_time - time_charge_time;              % Time route travel time
    
    % --- Energy Route Metrics ---
    energy_charge_time = sum(sol_energy.t_ch);                              % Energy route charging time
    energy_travel_time = sol_energy.total_time - energy_charge_time;        % Energy route travel time

    % --- HVAC and Traction Separation ---
    calculate_hvac = @(sol, rt) sol.total_energy - sum(diag(data.E0(rt(1:end-1), rt(2:end))));
    hvac_cost_route   = calculate_hvac(sol_cost, route_cost);
    hvac_time_route   = calculate_hvac(sol_time, route_time);
    hvac_energy_route = calculate_hvac(sol_energy, route_energy);

    % --- Cost of Comfort by means of time and USD ---
    avg_lmp = mean(data.LMP(:));                                            % Avg. electricity price
    cost_of_comfort_usd = hvac_cost_route * avg_lmp;                        % Cost of HVAC in terms of USD
    avg_P = mean(data.P_charge_kW(data.P_charge_kW > 0));                   % Avg. charging power                    
    time_of_comfort_h = hvac_cost_route / avg_P;                            % Cost of HVAC in terms of Energy
    
    % --- Print Results to Console ---
    fprintf('\n=== DISTANCE Objective (Base Route) ===\n');
    fprintf('Objective (Distance)          : %.4f km\n', sol_distance.total_dist);
    fprintf('  Travel Time                 : %.4f h\n', sol_distance.total_time);
    fprintf('  Travel Cost                 : %.4f $\n', sol_distance.total_cost);
    
    fprintf('\n=== COST Objective (Economic Route) ===\n');
    fprintf('Objective (Total Cost)        : %.4f $\n', sol_cost.total_cost);
    fprintf('  Travel Time                 : %.4f h\n', cost_travel_time);
    fprintf('  Charging Time               : %.4f h\n', cost_charge_time);
    fprintf('  Total Energy Consumed       : %.4f kWh\n', sol_cost.total_energy);
    fprintf('  [COMFORT ANALYSIS]\n');
    fprintf('  - Comfort Energy (HVAC)     : %.4f kWh\n', hvac_cost_route);
    fprintf('  - Cost of Comfort           : %.4f $\n', cost_of_comfort_usd);
    fprintf('  - Time of Comfort           : %.4f h (Extra Charging)\n', time_of_comfort_h);
    fprintf('  --------------------------------------------\n');
    fprintf('  Total Time (Travel+Charge)  : %.4f h\n', sol_cost.total_time);
    
    fprintf('\n=== TIME Objective (Fastest Route) ===\n');
    fprintf('Objective (Total Time)        : %.4f h\n', sol_time.total_time);
    fprintf('  Travel Time                 : %.4f h\n', time_travel_time);
    fprintf('  Charging Time               : %.4f h\n', time_charge_time);
    fprintf('  Total Cost (Info)           : %.4f $\n', sol_time.total_cost);
    fprintf('  [COMFORT ANALYSIS]\n');
    fprintf('  - Comfort Energy (HVAC)     : %.4f kWh\n', hvac_time_route);
    fprintf('  Total Energy Consumed       : %.4f kWh\n', sol_time.total_energy);
    
    fprintf('\n=== ENERGY Objective (Sustainability Route) ===\n');
    fprintf('Objective (Total Energy)      : %.4f kWh\n', sol_energy.total_energy);
    fprintf('  Travel Time                 : %.4f h\n', energy_travel_time);
    fprintf('  Charging Time               : %.4f h\n', energy_charge_time);
    fprintf('  Total Time (Travel+Charge)  : %.4f h\n', sol_energy.total_time);
    fprintf('  [COMFORT ANALYSIS]\n');
    fprintf('  - Comfort Energy (HVAC)     : %.4f kWh\n', hvac_energy_route);
    fprintf('  - HVAC Share in Total Energy: %.1f%%\n', (hvac_energy_route/sol_energy.total_energy)*100);
    fprintf('  Total Cost (Info)           : %.4f $\n', sol_energy.total_cost);
    
    fprintf('\nRoutes Found:\n');
    fprintf('  Cost Route   : '); fprintf('%d ', route_cost);   fprintf('\n');
    fprintf('  Time Route   : '); fprintf('%d ', route_time);   fprintf('\n');
    fprintf('  Energy Route : '); fprintf('%d ', route_energy); fprintf('\n');
    fprintf('  Dist Route   : '); fprintf('%d ', route_distance); fprintf('\n');

    res_struct.sol_cost = sol_cost;     res_struct.route_cost = route_cost;
    res_struct.sol_time = sol_time;     res_struct.route_time = route_time;
    res_struct.sol_energy = sol_energy; res_struct.route_energy = route_energy;
    res_struct.sol_dist = sol_distance; res_struct.route_dist = route_distance;
    
    results_list{run_idx} = res_struct;
end
% ------------------------------------------------------------------------------
% SECTION 5: VISUALIZATION DASHBOARD
% ------------------------------------------------------------------------------
% Create the multi-tab interactive figure to analyze the results.
% Calculations are complete. Now opening the window to select which result to view.

% Create a small control window
f_select = uifigure('Name', 'Data Selection', 'Position', [500 500 300 130], 'Resize', 'off');
uilabel(f_select, 'Position', [25 80 250 20], 'Text', 'Select Result to View:', 'FontWeight', 'bold');

% Dropdown Menu
dd = uidropdown(f_select, 'Items', {'Real-Time Data', 'Fixed Data (15 July)'}, ...
                'Position', [25 40 250 30]);

% Function to run when selection changes
dd.ValueChangedFcn = @(src, event) update_view_handler(src.Value, results_list, dataset_list);

% Initialize by showing Real-Time Data
update_view_handler('Real-Time Data', results_list, dataset_list);

% ==============================================================================
%  HELPER FUNCTION
% ==============================================================================
function update_view_handler(selected_name, res_list, data_list)
    % 1. Determine index based on selection
    if contains(selected_name, 'Real')
        idx = 1;
    else
        idx = 2;
    end
    
    % 2. Retrieve the specific result package and data from the list
    res = res_list{idx};
    data = data_list{idx};
    
    % Safety check
    if isempty(res)
        uialert(gcf, 'No results found for this dataset!', 'Error');
        return;
    end
    
    % 3. Clear old dashboard figures (Do NOT close the selection window)
    figs = findobj('Type', 'figure');
    for k = 1:length(figs)
        if ~strcmp(figs(k).Name, 'Data Selection')
            close(figs(k));
        end
    end
    
    % 4. CALL YOUR ORIGINAL DASHBOARD FUNCTION
    % Passing the variables exactly as stored in your structure
    plot_dashboard_multi(res.sol_cost,   res.route_cost, ...
                         res.sol_time,   res.route_time, ...
                         res.sol_energy, res.route_energy, ...
                         res.sol_dist,   res.route_dist, ...
                         data);
end
%% =============================================================================
%  FUNCTION: MILP Solver (Time-Dependent VRP Formulation)
%  =============================================================================
function solution = solve_ev_routing_milp(data, mode)
    import yalmip.*
    
    % Default to cost mode if not specified
    if nargin < 2
        mode = "cost"; 
    end
    mode = lower(string(mode));
    
    % --- Unpack Data Structures for Readability ---
    N       = data.N;                                                       % Number of nodes
    A       = data.A;                                                       % Adjacency Matrix (Connectivity)
    tij     = data.tij;                                                     % Travel Time Matrix (Hours)
        
    % Battery Constraints
    Ebat    = data.Ebat;                                                    % Battery Capacity (kWh)
    SOCmin  = data.SOC_min;                                                 % Minimum SOC limit (e.g., 0.10)
    SOCmax  = data.SOC_max;                                                 % Maximum SOC limit (e.g., 0.95)
    SOCinit = data.SOC_init;                                                % SOC at Origin
    SOCdest = data.min_SOC_at_dest;                                         % Required SOC at Destination
    
    origin  = data.origin;
    dest    = data.dest;
    
    % Charging & Grid
    P_charge_vec = data.P_charge_kW;                                        % Charging power at each node
    LMP          = data.LMP;                                                % Electricity Prices [N x K]
    
    % Time Settings
    K       = data.Tslots;                                                  % Total Time Slots (e.g., 96)
    dt      = data.dt_h;                                                    % Duration of one slot (e.g., 0.25h)
    
    % Big-M Constants (Used for constraint relaxation logic)
    M_time = K * dt + 5; 
    M_soc  = 2.0; 
    
    % --------------------------------------------------------------------------
    % DECISION VARIABLES
    % --------------------------------------------------------------------------
    
    % 1. Routing Variables
    x       = binvar(N,N,'full');                                           % x(i,j) = 1 if arc i->j is used (Static view)
    visit   = binvar(N,1);                                                  % visit(i) = 1 if node i is visited
    
    % 2. Time-Dependent Routing
    y       = binvar(N,N,K,'full');                                         % y(i,j,k) = 1 if arc i->j is traversed AND arrival at node j is in time slot k
    
    % 3. Battery State Variables
    SOC_dep = sdpvar(N,1);                                                  % SOC leaving node i
    SOC_arr = sdpvar(N,1);                                                  % SOC arriving at node i
    
    % 4. Charging Physics Variables
    DeltaE      = sdpvar(N,1);                                              % Total energy charged at node i
    t_ch        = sdpvar(N,1);                                              % Charging duration (hours)
    
    % 5. Time Variables
    t_arr   = sdpvar(N,1);                                                  % Arrival time at node i (Continuous hours)
    z       = binvar(N,K,'full');                                           % z(i,k) = 1 if charging happens at node i in slot k
    Eik     = sdpvar(N,K,'full');                                           % Energy charged at node i during slot k
    
    % --------------------------------------------------------------------------
    % CONSTRAINTS
    % --------------------------------------------------------------------------
    constraints = [];
    
    % --- A. Network Flow (Standard VRP) ---
    constraints = [constraints, x(eye(N)==1) == 0];                         % No self-loops
    constraints = [constraints, x(A==0) == 0];                              % Only existing roads
    
    constraints = [constraints, sum(x(origin,:)) == 1];                     % Must leave origin
    constraints = [constraints, sum(x(:,origin)) == 0];                     % Cannot return to origin
    constraints = [constraints, sum(x(:,dest)) == 1];                       % Must enter destination
    constraints = [constraints, sum(x(dest,:)) == 0];                       % Cannot leave destination
    
    % Flow Conservation: Inflow = Outflow for intermediate nodes
    for i = 1:N                     
        if i ~= origin && i ~= dest                                         % Apply only to intermediate nodes (exclude start and end)
            constraints = [constraints, sum(x(i,:)) == sum(x(:,i))];        % Outgoing edges from i equals incoming edges to i (flow conservation)
            constraints = [constraints, sum(x(i,:)) == visit(i)];           % If node i is visited (visit=1), exactly one outgoing arc is chosen; else none 
        end
    end
    constraints = [constraints, visit(origin) == 1, visit(dest) == 1];      % Force origin and destination to be included in the route

    % --- B. SUBTOUR ELIMINATION (MTZ) FOR ORIGIN->DEST PATH WITH OPTIONAL NODES ---
    
    % u(i) represents the position/order of node i on the main route.
    % If visit(i)=0 then u(i) is forced to 0 (node not used).
    u = sdpvar(N,1);
    
    % Basic bounds
    constraints = [constraints, u >= 0, u <= N];
    
    % Fix origin order to 1
    constraints = [constraints, u(origin) == 1];
    
    for i = 1:N
        if i ~= origin && i ~= dest
            % If node is visited, order must be >= 2; otherwise it must be 0.
            constraints = [constraints, u(i) >= 2*visit(i)];
            constraints = [constraints, u(i) <= N*visit(i)];
        end
    end
    
    % Destination must be visited (usually implied by in-degree=1, but safe to keep)
    constraints = [constraints, visit(dest) == 1];
    
    % MTZ precedence constraints
    M_u = N;
    
    for i = 1:N
        for j = 1:N
            if i ~= j && A(i,j) == 1
    
                % Skip arcs entering origin or leaving destination (already forbidden)
                if j == origin || i == dest
                    continue;
                end
    
                % If arc (i->j) is selected, then u(j) >= u(i) + 1
                constraints = [constraints, u(j) >= u(i) + 1 - M_u*(1 - x(i,j))];
            end
        end
    end
    
    % --- C. Link Static Routing (x) with Dynamic Routing (y) ---
    % If we travel i->j, it must happen at EXACTLY one time slot k.         % Any used arc must be assigned to exactly one time slot
    for i = 1:N
        for j = 1:N
            if A(i,j) == 1                                                  % If an arc/road from i to j exists in the adjacency matrix
                constraints = [constraints, sum(y(i,j,:)) == x(i,j)];       % If x(i,j)=1 then exactly one y(i,j,k)=1; if x(i,j)=0 then all y=0
            else                                                            % If no arc/road exists
                constraints = [constraints, y(i,j,:) == 0];                 % Force all y(i,j,k) to zero for all time slots
            end
        end
    end
    
    % --- D. Time Synchronization for Dynamic Variable y(i,j,k) ---
    % If y(i,j,k) == 1, then the arrival time t_arr(j) must be within slot k.
    a = binvar(N,K,'full');                                                 % arrival slot indicator
    
    for j=1:N
        if j~=origin
            for k=1:K
                constraints = [constraints, a(j,k) == sum(y(:,j,k))]; % y(:,j,k) is Nx1
                % If we arrive at node j during slot k, exactly one incoming arc y(i,j,k)=1
                % Therefore, a(j,k) becomes 1 when any y(i,j,k)=1
                % y(:,j,k) is an Nx1 vector (all possible predecessors i)
            end
            constraints = [constraints, sum(a(j,:)) == visit(j)];
            % If node j is visited, it must have exactly one active arrival slot
            % If not visited, all a(j,k) must be zero
    
            for k=1:K
                constraints = [constraints, t_arr(j) >= (k-1)*dt - M_time*(1-a(j,k))];
                % If a(j,k)=1 → lower bound enforces arrival time ≥ start of slot k
                % If a(j,k)=0 → Big-M relaxes the constraint (becomes non-binding)

                constraints = [constraints, t_arr(j) <= k*dt     + M_time*(1-a(j,k))];
                % If a(j,k)=1 → upper bound enforces arrival time ≤ end of slot k
                % If a(j,k)=0 → Big-M relaxes the constraint
            end
        end
    end

    
    % --- E. Battery Dynamics (Using Dynamic Energy Matrix) ---
    for i = 1:N
        for j = 1:N
            if A(i,j) == 1
                % Calculate energy consumption based on WHICH slot we arrive in.
                % Sum( y(i,j,k) * E_dynamic(i,j,k) ) gives the precise energy.
                cons_dynamic = sum(squeeze(y(i,j,:)) .* squeeze(data.E_dynamic(i,j,:))) / Ebat;
                
                % Standard battery inventory constraints
                constraints = [constraints, ...
                    SOC_arr(j) <= SOC_dep(i) - cons_dynamic + M_soc*(1 - x(i,j))];
                constraints = [constraints, ...
                    SOC_arr(j) >= SOC_dep(i) - cons_dynamic - M_soc*(1 - x(i,j))];
            end
        end
    end
    
    % Node internal dynamics
    constraints = [constraints, SOC_dep == SOC_arr + DeltaE/Ebat];
    
    % Safety Limits
    constraints = [constraints, SOCmin <= SOC_arr <= SOCmax];
    constraints = [constraints, SOCmin <= SOC_dep <= SOCmax];
    
    % Boundary conditions
    constraints = [constraints, SOC_dep(origin) == SOCinit]; 
    constraints = [constraints, SOC_arr(dest) >= SOCdest];   
    constraints = [constraints, DeltaE(origin) == 0];        
    constraints = [constraints, DeltaE(dest) == 0];
    
    for i = 1:N
        P = P_charge_vec(i);
        if P > 0
            % STRICT CONSTRAINT: Charging Duration = Energy / Power
            % This equality constraint removes the freedom to "wait".
            % To increase time (t_ch), the solver MUST increase energy (DeltaE),
            % which is penalized in the Energy Objective. Thus, no waiting occurs.
            constraints = [constraints, t_ch(i) == DeltaE(i) / P];
            % Can only charge if visited
            constraints = [constraints, DeltaE(i) <= Ebat * visit(i)];
        else
            constraints = [constraints, DeltaE(i) == 0];
            constraints = [constraints, t_ch(i) == 0];
        end
    end
    
    % --- F. Time Continuity Constraints ---
    constraints = [constraints, t_arr(origin) == 0];
    for i = 1:N
        for j = 1:N
            if A(i,j) == 1
                % Lower Bound
                constraints = [constraints, ...
                    t_arr(j) >= t_arr(i) + t_ch(i) + tij(i,j) - M_time*(1 - x(i,j))]; 
                % Upper Bound (No Idling)
                constraints = [constraints, ...
                    t_arr(j) <= t_arr(i) + t_ch(i) + tij(i,j) + M_time*(1 - x(i,j))]; 
            end
        end
    end
    constraints = [constraints, t_arr <= K*dt]; 
    
    % --- G. Charging Slot Allocation (Strict / No Pricing Cheating) ---
    for i = 1:N
        if P_charge_vec(i) > 0
            % Total charging slots cannot exceed horizon
            constraints = [constraints, sum(z(i,:)) <= K * visit(i)]; 
            % Sum of energy in slots must equal total charged energy
            constraints = [constraints, sum(Eik(i,:)) == DeltaE(i)];
            max_energy_per_slot = P_charge_vec(i) * dt;
            constraints = [constraints, 0 <= Eik(i,:) <= max_energy_per_slot * z(i,:)];

            
            % Synchronization: Charging must occur strictly between Arrival and Departure
            for k = 1:K
                time_of_slot_start = (k-1)*dt;
                
                % Charging slot start time >= Arrival Time
                constraints = [constraints, ...
                    time_of_slot_start >= t_arr(i) - M_time*(1-z(i,k))];
                
                % Charging slot start time <= Departure Time (No Future Charging)
                constraints = [constraints, ...
                    time_of_slot_start <= t_arr(i) + t_ch(i) + M_time*(1-z(i,k))];
            end
        else
            constraints = [constraints, Eik(i,:) == 0];
            constraints = [constraints, z(i,:) == 0];
        end
    end
    
    % --------------------------------------------------------------------------
    % OBJECTIVE FUNCTION
    % --------------------------------------------------------------------------
    
    cost_term   = sum(sum(Eik .* LMP));      % Total Charging Cost ($)
    time_term   = t_arr(dest);               % Total Trip Duration (hours)
    energy_term = sum(sum(sum(y .* data.E_dynamic))); % Total Energy (kWh)
    dist_term = sum(sum(x .* data.dist));
    
    switch mode
        case "cost"
            objective = cost_term;
        case "time"
            objective = time_term;
        case "energy"
            objective = energy_term;
        case "distance"
            w_time = 0.001;
            w_dist = 1;
            objective = (w_dist * dist_term) + (w_time * time_term) ;
        otherwise
            error('Unknown optimization mode selected.');
    end
    
    % --------------------------------------------------------------------------
    % SOLVE & EXTRACT
    % --------------------------------------------------------------------------
    opts = sdpsettings('solver','intlinprog','verbose',0, 'cachesolvers', 1);
    sol  = optimize(constraints, objective, opts);
    
    if sol.problem == 0
        disp(['Solver (' char(mode) '): Optimal Solution Found.']);
    else
        warning('Solver Issue: %s', sol.info);
    end
    
    % --- Map Solver Values to Solution Struct ---
    solution.x         = value(x);
    solution.visit     = value(visit);
    solution.route     = extract_route(value(x), origin, dest);
    
    solution.SOC_dep   = value(SOC_dep);
    solution.SOC_arr   = value(SOC_arr);
    
    solution.DeltaE    = value(DeltaE);
    
    solution.t_ch      = value(t_ch);
    solution.t_arr     = value(t_arr);
    
    solution.z         = value(z);         
    solution.Eik       = value(Eik);       
    
    solution.total_cost   = value(cost_term);
    solution.total_time   = value(time_term);
    solution.total_energy = value(energy_term);
    solution.total_dist   = value(dist_term);
    
    solution.mode = mode;
end
%% =============================================================================
%  HELPER: Route Extraction from Binary Matrix
%  =============================================================================
function route = extract_route(x, origin, dest)
    N = size(x,1);
    route = [origin];
    curr = origin;
    while curr ~= dest
        [~, next] = max(x(curr,:)); 
        if x(curr, next) < 0.5, break; end 
        route = [route, next];
        curr = next;
        if length(route) > N, break; end 
    end
end
%% =============================================================================
%  FUNCTION: Data Generator
%  =============================================================================
function data = my_test_data_15_node_24_tslots_Ankara_Antalya()
    % --- 1. Basic Topology ---
    N = 15;
    data.N = N;         % number of nodes
    data.origin = 1;    % starting node
    data.dest   = 15;   % finish node

    % Time adjustment (starts now)
    t_now = datetime('now');
    data.start_hour = hour(t_now);
    
    % Virtual coordinates for Plotting
    data.coords = [
        58   92; % 1. Ankara
        45   82; % 2. Polatlı
        63   68; % 3. Kulu
        35   78; % 4. Sivrihisar
        14   58; % 5. Afyon
        32   48; % 6. Akşehir
        52   36; % 7. Konya
        80   48; % 8. Aksaray
        11   46; % 9. Sandıklı
        22   33; % 10. Eğirdir
        39   28; % 11. Beyşehir
        12   28; % 12. Burdur
        40   12; % 13. Akseki
        25   08; % 14. Serik
        18   04  % 15. Antalya
    ];
    
    % --- 2. Load Excel & Extract Real GPS ---
    filename = 'Analiz_Sonuclari_Final.xlsx';
    try
        opts = detectImportOptions(filename);
        opts.VariableNamingRule = 'preserve';
        routeData = readtable(filename, opts);
    catch
        error('Error: File "%s" not found.', filename);
    end
    dms2dec = @(s) sum(str2double(regexp(string(s), '\d+(\.\d+)?', 'match')) .* [1, 1/60, 1/3600]); % converting coordinates
    real_coords = zeros(N, 2);                                                                      % real coordinates for route calculation
    
    for k = 1:height(routeData)
        s = routeData.Start(k); e = routeData.End(k);
        if real_coords(s, 1) == 0
            real_coords(s,1)=dms2dec(routeData.StartLat(k)); 
            real_coords(s,2)=dms2dec(routeData.StartLon(k)); 
        end
        if real_coords(e, 1) == 0
            real_coords(e,1)=dms2dec(routeData.EndLat(k)); 
            real_coords(e,2)=dms2dec(routeData.EndLon(k)); 
        end
    end
    
    % --- 3. Build Static Matrices ---
    A    = zeros(N);        % Adjacency matrix                               
    E0_static = zeros(N);   % Only traction (physics), no HVAC
    tij  = zeros(N);        % Travel duration between node i and j [hours]
    dist_mat = zeros(N);
    
    base_rate = 0.16;       % Base traction energy consumption
    climb_penalty = 0.006;  % Climb traction energy consumption
    descent_bonus = 0.0035;  % Descent traction energy gain  
    
    for k = 1:height(routeData)
        i = routeData.Start(k); j = routeData.End(k);
        dist = routeData.Distance_km(k);
        gain = routeData.TotalGain(k);
        loss = routeData.TotalLoss(k);
        time_min = routeData.TravelTime_min(k);
        
        A(i,j) = 1; 
        dist_mat(i,j) = dist;
        E0_static(i,j) = (dist * base_rate) + (gain * climb_penalty) - (loss * descent_bonus);
        tij(i,j) = time_min / 60; 
    end
    
    data.A    = A;          % Adjacency matrix 
    data.tij  = tij;        % Travel duration between node i and j [hours]
    data.E0   = E0_static;  % Base traction energy [km]
    data.dist = dist_mat;
    
    % --- 4. Time Setup ---
    data.dt_min = 15;           
    data.dt_h   = data.dt_min / 60; 
    data.Tslots = 96;       % 24 Hours resolution
    
    % --- 5. DYNAMIC 3D ENERGY MATRIX GENERATION ---
    data.Tset = 22;         % Set temperature [C]
    data.T_tol = 2.0;       % Temperature tolerance 
    data.base_kW = 0.3;    % Base hvac consumption
    data.alpha_h = 0.12;    % DeltaT additional HVAC consumption when heating
    data.alpha_c = 0.08;   % DeltaT additional HVAC consumption when cooling
    data.P_max_h = 5.0;     % Max heating energy
    data.P_max_c = 3.0;     % Max cooling energy
    
    NodeTemp_24h = zeros(N, 24);
    for n = 1:N
        NodeTemp_24h(n, :) = get_weather_forecast_24h(real_coords(n,1), real_coords(n,2));
        if mod(n,5)==0, pause(0.1); end 
    end
    
    orig_h = 1:24;
    targ_slots = linspace(1, 24, data.Tslots);
    NodeTemp_HighRes = zeros(N, data.Tslots);
    
    for n = 1:N
        NodeTemp_HighRes(n, :) = interp1(orig_h, NodeTemp_24h(n, :), targ_slots, 'pchip');   
    end
    
    E_dynamic = zeros(N, N, data.Tslots);
    data.Tseg = zeros(N, N, data.Tslots); 
    
    for k = 1:data.Tslots
        for i = 1:N
            for j = 1:N
                if A(i,j) == 1
                    T_curr = NodeTemp_HighRes(j, k);
                    data.Tseg(i,j,k) = T_curr;
                    
                    if T_curr < (data.Tset - data.T_tol)
                        dT = (data.Tset - data.T_tol) - T_curr;
                        P_act = min((data.alpha_h * (dT^2)) + data.base_kW, data.P_max_h);
                    elseif T_curr > (data.Tset + data.T_tol)
                        dT = T_curr - (data.Tset + data.T_tol);
                        P_act = min((data.alpha_c * (dT^2)) + data.base_kW, data.P_max_c);
                    else
                        P_act = data.base_kW;
                    end
                    
                    E_hvac = P_act * tij(i,j);
                    E_dynamic(i,j,k) = E0_static(i,j) + E_hvac;
                end
            end
        end
    end
    data.E_dynamic = E_dynamic; 
    data.E = mean(E_dynamic, 3); 
    
    % --- 6. Battery & Grid Parameters ---
    data.Ebat     = 80;         % Total Battery Capacity [kWh]     
    data.SOC_min  = 0.10;       % Minimum SOC allowed 
    data.SOC_max  = 0.95;       % Maximum SOC allowed 
    data.SOC_init = 0.35;       % Initial SOC 
    data.min_SOC_at_dest = 0.30;% Minimum SOC at route end
    
    % Charger Distribution
    type_ultra = 180; 
    type_fast = 60; 
    type_slow = 22;  
    charging_power = zeros(N, 1);
    charging_power([2,3,6,9,11,12,14]) = type_fast; 
    charging_power([4,5,7,8]) = type_ultra; 
    charging_power(13) = type_slow;
    data.P_charge_kW = charging_power;
    
    data.ch_breakpoint = 0.80;  
    data.ch_slow_factor = 0.33; 
    
    % --------------------------------------------------------------------------
    % 7. REALISTIC LMP IMPORT (SYNCED TO CURRENT TIME)
    % --------------------------------------------------------------------------
    fprintf('Loading Real PJM LMP Data...\n');
    
    % --- STEP 1: GET CURRENT SIMULATION START TIME ---
    current_hour = hour(t_now);  % Extract hour (e.g., 14 for 2:00 PM)
    
    fprintf('Simulation Start Time: %02d:00 (Real World)\n', current_hour);
    fprintf('Aligning LMP data to start from %02d:00...\n', current_hour);

    filename_lmp = 'LMP_PJM_Data.xlsx';
    
    try
        % Read the Excel file preserving original column headers
        opts_lmp = detectImportOptions(filename_lmp);
        opts_lmp.VariableNamingRule = 'preserve'; 
        lmp_table = readtable(filename_lmp, opts_lmp);
        
        LMP_HighRes = zeros(N, data.Tslots);
        
        % Define time vectors:
        % Original: 0 to 23 hours
        % Target: 0 to 23.75 hours (96 slots)
        orig_h_price = 0:23; 
        targ_slots_price = linspace(0, 23.75, data.Tslots);
        
        for i = 1:N
            % A) Find rows corresponding to the current Node
            % We match the 'Node Karşılığı' column in Excel with node index 'i'
            node_rows = lmp_table(lmp_table.("Node Karşılığı") == i, :);
            
            % Sort by time to ensure 00:00 comes first
            if ismember('datetime_beginning_ept', node_rows.Properties.VariableNames)
                 node_rows = sortrows(node_rows, 'datetime_beginning_ept');
            end
            
            % Extract price column (assuming it is already converted to $/kWh in Excel)
            prices_24h = node_rows.("kWh format");
            
            % B) Handle missing or excess data to ensure exactly 24 points
            if length(prices_24h) < 24
                % Pad with the mean value if data is missing
                prices_24h = [prices_24h; repmat(mean(prices_24h), 24-length(prices_24h), 1)];
            elseif length(prices_24h) > 24
                % Truncate if more than 24 points
                prices_24h = prices_24h(1:24);
            end
            
            % --- CRITICAL STEP: TIME SHIFTING ---
            % The Excel data starts at 00:00.
            % However, the simulation starts NOW (at 'current_hour').
            % We shift the array so that the price at 'current_hour' becomes the first element.
            % The past hours (00:00 to current_hour-1) are moved to the end of the array (tomorrow).
            
            prices_shifted = circshift(prices_24h, -current_hour);
            
            % C) Interpolate to High Resolution (96 Slots)
            % 'pchip' ensures smooth transition between hourly price points
            % [Made previous]
            LMP_HighRes(i, :) = interp1(orig_h_price, prices_shifted, targ_slots_price, 'previous');
        end
        
        data.LMP = LMP_HighRes;
        fprintf('LMP Data aligned and loaded successfully.\n');
    catch
        warning('LMP read failed.')
    end
    
    data.w_time = 1.0; 
    data.w_ch = 3.0; 
    data.w_cost = 5.0; 
end
%% =============================================================================
%  FUNCTION: My Fixed Data for Test
%  =============================================================================
function data = my_fixed_data_with_same_nodes()
    % --- 1. Basic Topology & Global Time Setting ---
    current_hour = 10;   % Starting hour
    data.start_hour = current_hour; % For dashboard
    N = 15;
    data.N = N;         % number of nodes
    data.origin = 1;    % starting node
    data.dest   = 15;   % finish node
    
    % Virtual coordinates for Plotting
    data.coords = [
        58   92; % 1. Ankara
        45   82; % 2. Polatlı
        63   68; % 3. Kulu
        35   78; % 4. Sivrihisar
        14   58; % 5. Afyon
        32   48; % 6. Akşehir
        52   36; % 7. Konya
        80   48; % 8. Aksaray
        11   46; % 9. Sandıklı
        22   33; % 10. Eğirdir
        39   28; % 11. Beyşehir
        12   28; % 12. Burdur
        40   12; % 13. Akseki
        25   08; % 14. Serik
        18   04  % 15. Antalya
    ];
    
    % --- 2. Load Excel & Extract Real GPS ---
    filename = 'Analiz_Sonuclari_Final.xlsx';
    try
        opts = detectImportOptions(filename);
        opts.VariableNamingRule = 'preserve';
        routeData = readtable(filename, opts);
    catch
        error('Error: File "%s" not found.', filename);
    end
    dms2dec = @(s) sum(str2double(regexp(string(s), '\d+(\.\d+)?', 'match')) .* [1, 1/60, 1/3600]); % converting coordinates
    real_coords = zeros(N, 2);                                                                      % real coordinates for route calculation
    
    for k = 1:height(routeData)
        s = routeData.Start(k); e = routeData.End(k);
        if real_coords(s, 1) == 0
            real_coords(s,1)=dms2dec(routeData.StartLat(k)); 
            real_coords(s,2)=dms2dec(routeData.StartLon(k)); 
        end
        if real_coords(e, 1) == 0
            real_coords(e,1)=dms2dec(routeData.EndLat(k)); 
            real_coords(e,2)=dms2dec(routeData.EndLon(k)); 
        end
    end
    
    % --- 3. Build Static Matrices ---
    A    = zeros(N);        % Adjacency matrix                               
    E0_static = zeros(N);   % Only traction (physics), no HVAC
    tij  = zeros(N);        % Travel duration between node i and j [hours]
    dist_mat = zeros(N);
    
    base_rate = 0.16;       % Base traction energy consumption
    climb_penalty = 0.006;  % Climb traction energy consumption
    descent_bonus = 0.0035;  % Descent traction energy gain  
    
    for k = 1:height(routeData)
        i = routeData.Start(k); j = routeData.End(k);
        dist = routeData.Distance_km(k);
        gain = routeData.TotalGain(k);
        loss = routeData.TotalLoss(k);
        time_min = routeData.TravelTime_min(k);
        
        A(i,j) = 1; 
        dist_mat(i,j) = dist;
        E0_static(i,j) = (dist * base_rate) + (gain * climb_penalty) - (loss * descent_bonus);
        tij(i,j) = time_min / 60; 
    end
    
    data.A    = A;          % Adjacency matrix 
    data.tij  = tij;        % Travel duration between node i and j [hours]
    data.E0   = E0_static;  % Base traction energy [km]
    data.dist = dist_mat;
    
    % --- 4. Time Setup ---
    data.dt_min = 15;           
    data.dt_h   = data.dt_min / 60; 
    data.Tslots = 96;       % 24 Hours resolution

    % =====================================================================
    % 5. FIXED WEATHER GENERATION (READ FROM EXCEL & SYNCHED TO HOUR)
    % =====================================================================
    fprintf('Loading Fixed Weather from Excel (15 July 2025)...\n');
    
    weather_file = 'Fixed_Weather_Data_15July.xlsx';
    if ~isfile(weather_file)
        error('Weather Data File not found: %s. Please run "fetch_historical_weather_STRICT.m" first.', weather_file);
    end
    
    % Read Excel
    weather_table = readtable(weather_file, 'ReadRowNames', true);
    % Convert to matrix (15x24)
    NodeTemp_24h = table2array(weather_table);
    
    % Safety check: Matrix size & Shift
    if size(NodeTemp_24h, 2) == 24
        NodeTemp_24h = circshift(NodeTemp_24h, -current_hour, 2);
        fprintf('   -> Weather Data SHIFTED by -%d hours (Start: %02d:00)\n', current_hour, current_hour);
    else
        warning('Weather data 24 saatlik değil, shift işlemi yapılamadı.');
    end

    % --- HVAC Parameters ---
    data.Tset = 22;         % Set temperature [C]
    data.T_tol = 2.0;       % Temperature tolerance 
    data.base_kW = 0.3;    % Base hvac consumption
    data.alpha_h = 0.12;    % DeltaT additional HVAC consumption when heating
    data.alpha_c = 0.08;   % DeltaT additional HVAC consumption when cooling
    data.P_max_h = 5.0;     % Max heating energy
    data.P_max_c = 3.0;     % Max cooling energy
    
    orig_h = 1:24;
    targ_slots = linspace(1, 24, data.Tslots);
    NodeTemp_HighRes = zeros(N, data.Tslots);
    
    for n = 1:N
        NodeTemp_HighRes(n, :) = interp1(orig_h, NodeTemp_24h(n, :), targ_slots, 'pchip');   
    end
    
    E_dynamic = zeros(N, N, data.Tslots);
    data.Tseg = zeros(N, N, data.Tslots); 
    
    for k = 1:data.Tslots
        for i = 1:N
            for j = 1:N
                if A(i,j) == 1
                    T_curr = NodeTemp_HighRes(j, k);
                    data.Tseg(i,j,k) = T_curr;
                    
                    if T_curr < (data.Tset - data.T_tol)
                        dT = (data.Tset - data.T_tol) - T_curr;
                        P_act = min((data.alpha_h * (dT^2)) + data.base_kW, data.P_max_h);
                    elseif T_curr > (data.Tset + data.T_tol)
                        dT = T_curr - (data.Tset + data.T_tol);
                        P_act = min((data.alpha_c * (dT^2)) + data.base_kW, data.P_max_c);
                    else
                        P_act = data.base_kW;
                    end
                    
                    E_hvac = P_act * tij(i,j);
                    E_dynamic(i,j,k) = E0_static(i,j) + E_hvac;
                end
            end
        end
    end
    data.E_dynamic = E_dynamic; 
    data.E = mean(E_dynamic, 3); 
    
    % --- 6. Battery & Grid Parameters ---
    data.Ebat     = 80;         % Total Battery Capacity [kWh]     
    data.SOC_min  = 0.10;       % Minimum SOC allowed 
    data.SOC_max  = 0.95;       % Maximum SOC allowed 
    data.SOC_init = 0.35;       % Initial SOC 
    data.min_SOC_at_dest = 0.25;% Minimum SOC at route end
    
    % Charger Distribution
    type_ultra = 180; 
    type_fast = 60; 
    type_slow = 22;  
    charging_power = zeros(N, 1);
    charging_power([2,6,7,9,12,14]) = type_fast; 
    charging_power([3,4,5,8,13]) = type_ultra; 
    charging_power(11) = type_slow;
    data.P_charge_kW = charging_power;
    
    data.ch_breakpoint = 0.80;  
    data.ch_slow_factor = 0.33; 
    
    % --------------------------------------------------------------------------
    % 7. FIXED LMP IMPORT (STEP FUNCTION - NO SMOOTHING)
    % --------------------------------------------------------------------------
    fprintf('Loading Fixed PJM LMP Data...\n');
    
    % Simulation Start Time (Fixed)
    data.start_hour = current_hour; 
    fprintf('Simulation Start Time: %02d:00 (FIXED - Generated Data)\n', current_hour);
    
    filename_lmp = 'LMP_PJM_Data_Altered.xlsx';
    if ~isfile(filename_lmp)
         % Fallback if file missing
         warning('LMP Data file not found. Using constant price.');
         data.LMP = 0.30 * ones(N, data.Tslots);
    else
        try
            opts_lmp = detectImportOptions(filename_lmp, "Sheet", "Sheet1");
            opts_lmp.VariableNamingRule = 'preserve'; 
            lmp_table = readtable(filename_lmp, opts_lmp);
            
            LMP_HighRes = zeros(N, data.Tslots);
            orig_h_price = 0:23; 
            targ_slots_price = linspace(0, 23.75, data.Tslots);
            
            for i = 1:N
                node_rows = lmp_table(lmp_table.("Node Karşılığı") == i, :);
                if ismember('datetime_beginning_ept', node_rows.Properties.VariableNames)
                     node_rows = sortrows(node_rows, 'datetime_beginning_ept');
                end
                if ismember('datetime_beginning_ept', node_rows.Properties.VariableNames)
                     node_rows = sortrows(node_rows, 'datetime_beginning_ept');
                end
                prices_24h = node_rows.("kWh format");
                
                if length(prices_24h) < 24
                    prices_24h = [prices_24h; repmat(mean(prices_24h), 24-length(prices_24h), 1)];
                elseif length(prices_24h) > 24
                    prices_24h = prices_24h(1:24);
                end
                
                % FIXED TIME SHIFT
                prices_shifted = circshift(prices_24h, -current_hour);
                
                % 'previous' interpolation for Step Function
                LMP_HighRes(i, :) = interp1(orig_h_price, prices_shifted, targ_slots_price, 'previous', 'extrap');
            end
            
            data.LMP = LMP_HighRes;
            fprintf('Fixed LMP Data aligned (Step Function) and loaded successfully.\n');
        catch ME
            warning('LMP read failed: %s', ME.message);
            data.LMP = 0.30 * ones(N, data.Tslots);
        end
    end
    
    data.w_time = 1.0; 
    data.w_ch = 3.0; 
    data.w_cost = 5.0; 
end
%% =============================================================================
%  HELPER: Weather API (Open-Meteo)
%  =============================================================================
function temp_24h = get_weather_forecast_24h(lat, lon)
    % Fetches hourly temperature (2m) for 1 day.
    % Returns 1x24 vector. Returns fallback data if API fails.
    
    apiUrl = sprintf('https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f&hourly=temperature_2m&forecast_days=1', lat, lon);
    options = weboptions('Timeout', 15);
    
    try
        data = webread(apiUrl, options);
        if isfield(data, 'hourly') && isfield(data.hourly, 'temperature_2m')
            raw_temp = data.hourly.temperature_2m;
            if length(raw_temp) >= 24
                temp_24h = raw_temp(1:24)'; 
            else
                % Pad with last value if incomplete
                temp_24h = [raw_temp', repmat(raw_temp(end), 1, 24-length(raw_temp))];
            end
        else
            error('Invalid JSON');
        end
    catch ME
        % Fallback for safety
        error('Weather API Failed for Lat: %.4f, Lon: %.4f. Reason: %s', lat, lon, ME.message); 
    end
end
%% =============================================================================
%  FUNCTION: Multi-tab Dashboard (Visualization)
%  =============================================================================
function plot_dashboard_multi(sol_cost, route_cost, sol_time, route_time, sol_energy, route_energy, sol_distance, route_distance, data)
    fig = figure('Name','EV Routing Dashboard v3.0 (Time-Dependent)','NumberTitle','off', 'Position', [100, 100, 1400, 900]);
    tg  = uitabgroup(fig);
    tab1 = uitab(tg,'Title','Cost Objective');
    tab2 = uitab(tg,'Title','Time Objective');
    tab3 = uitab(tg,'Title','Energy Objective');
    tab4 = uitab(tg,'Title','Distance (Base)');
    tab5 = uitab(tg,'Title','Summary');
    
    plot_dashboard_single(tab1, sol_cost,   data, route_cost,   'Cost Objective');
    plot_dashboard_single(tab2, sol_time,   data, route_time,   'Time Objective');
    plot_dashboard_single(tab3, sol_energy, data, route_energy, 'Energy Objective');
    plot_dashboard_single(tab4, sol_distance,   data, route_distance,   'Distance (Base)');
    plot_summary_tab(tab5, sol_cost, sol_time, sol_energy, sol_distance);
end
function plot_dashboard_single(parentTab, solution, data, route, titlePrefix)
    % -------------------------------------------------------------------------
    % PLOT DASHBOARD SINGLE
    % Visualizes the solution details (Map, SOC, Prices, Temperature, etc.)
    % with Real-Time Axis labels based on the current execution time.
    % -------------------------------------------------------------------------

    coords = data.coords; 
    N = data.N; 
    K = data.Tslots; 
    dt = data.dt_h; 
    LMP = data.LMP; 

    comp_time_text = sprintf('Solve Time: %2.f sec', solution.solve_time);
    tl = tiledlayout(parentTab, 4, 3, 'Padding','compact', 'TileSpacing','compact');
    title(tl, [titlePrefix ' (' comp_time_text ')'], 'FontSize', 12);

    % Calculate average temperature and HVAC energy for visualization
    % Note: Actual optimization uses 3D dynamic matrices.
    if isfield(data, 'Tseg')
        Tseg_mean = mean(data.Tseg, 3);
    else
        Tseg_mean = zeros(N,N); % Fallback
    end
    
    if isfield(data, 'E') && isfield(data, 'E0')
        Eh = data.E - data.E0; 
    else
        Eh = zeros(N,N);
    end
    
    t_vec_h = (0:K-1)*dt; 
    
    % Initialize Tiled Layout
    tl = tiledlayout(parentTab, 4, 3, 'Padding','compact', 'TileSpacing','compact');

    % =========================================================================
    % DATA RECONSTRUCTION FOR CONTINUOUS TIME PLOTS
    % =========================================================================
    % We reconstruct continuous timeline vectors using your solution struct.
    
    t_log = [];      % Time axis
    soc_log = [];    % SOC axis
    p_time = [];     % Time axis for Power
    p_val = [];      % Power values (kW)
    
    for k = 1:length(route)
        u = route(k);
        
        % --- A) ARRIVAL at Node u ---
        t_in = solution.t_arr(u);
        s_in = solution.SOC_arr(u);
        
        t_log = [t_log, t_in];
        soc_log = [soc_log, s_in];
        
        % --- B) CHARGING/WAITING at Node u ---
        % Duration is stored in solution.t_ch
        dt_wait = solution.t_ch(u);
        s_out = solution.SOC_dep(u); % SOC after charging
        t_out = t_in + dt_wait;
        
        % Append state after waiting
        t_log = [t_log, t_out];
        soc_log = [soc_log, s_out];
        
        % Power during wait/charge is 0 (for consumption view)
        p_time = [p_time, t_in, t_out];
        p_val  = [p_val, 0, 0];
        
        % --- C) DRIVING to Next Node ---
        if k < length(route)
            v = route(k+1);
            
            % Next arrival time
            t_next = solution.t_arr(v);
            
            % Energy consumed on this edge (using your data.E0 definition)
            e_cons = data.E0(u,v);
            
            % Calculate Average Power = Energy / Time
            drive_dur = t_next - t_out;
            if drive_dur > 0.001
                p_inst = e_cons / drive_dur;
            else
                p_inst = 0;
            end
            
            % Append Power (Step function)
            p_time = [p_time, t_out, t_next];
            p_val  = [p_val, p_inst, p_inst];
        end
    end
    
    % =========================================================================
    % REAL-TIME AXIS CALCULATION
    % =========================================================================
    % 1. Get current system time (simulation start time)
    h_start = data.start_hour; % e.g., 14 for 2:00 PM
    
    % 2. Define X-axis tick positions (Simulation Hours: 0, 4, 8... 24)
    x_tick_vals = 0:4:24; 
    
    % 3. Generate corresponding Real-World Time labels (e.g., "14:00", "18:00")
    x_tick_labels = strings(size(x_tick_vals));
    for k = 1:length(x_tick_vals)
        % Modulo 24 ensures correct wrapping (e.g., 25 becomes 01:00)
        real_h = mod(h_start + x_tick_vals(k), 24);
        x_tick_labels(k) = sprintf('%02d:00', real_h);
    end
    % =========================================================================

    % -------------------------------------------------------------------------
    % 1. MAP VISUALIZATION
    % -------------------------------------------------------------------------
    nexttile(tl); hold on; grid on; axis equal; 
    title(sprintf('%s: Route Map', titlePrefix));
    
    % Draw all nodes
    scatter(coords(:,1), coords(:,2), 50, [0.8 0.8 0.8], 'filled'); 
    
    % Highlight route nodes
    scatter(coords(route,1), coords(route,2), 100, 'k', 'filled'); 
    text(coords(route,1)+1, coords(route,2)+1, string(route'), 'FontSize', 8, 'FontWeight', 'bold');
    
    % Draw edges used in the solution
    xsol = solution.x;
    for i=1:N
        for j=1:N
            if xsol(i,j) > 0.5
                plot([coords(i,1) coords(j,1)], [coords(i,2) coords(j,2)], 'b-', 'LineWidth', 2); 
            end
        end
    end
    
    % -------------------------------------------------------------------------
    % 2. SOC PROFILE (State of Charge)
    % -------------------------------------------------------------------------
    nexttile(tl); 
    % Bar plot showing Arrival and Departure SOC at each stop
    bar(1:length(route), [solution.SOC_arr(route), solution.SOC_dep(route)], 'grouped');
    
    % Formatting
    xticks(1:length(route)); 
    xticklabels(string(route)); 
    ylim([0 1.1]); 
    yline(data.SOC_min, 'r--', 'Min Limit'); 
    yline(data.SOC_max, 'g--', 'Max Limit');
    title('SOC Profile (Arr/Dep)'); 
    legend({'Arr','Dep'}, 'Location','sw'); 
    grid on;
    
    % -------------------------------------------------------------------------
    % 3. ENERGY BREAKDOWN (Traction vs HVAC)
    % -------------------------------------------------------------------------
    nexttile(tl); 
    traction = []; 
    hvac = []; 
    lbls = {};
    
    if length(route) > 1
        for k = 1:length(route)-1
            u = route(k); 
            v = route(k+1); 
            % Static traction energy
            traction(end+1) = data.E0(u,v); 
            % Approximate HVAC energy for visualization
            hvac(end+1) = Eh(u,v); 
            lbls{end+1} = sprintf('%d->%d', u, v);
        end
        % Stacked bar chart
        bar(1:length(lbls), [traction', hvac'], 'stacked'); 
        xticks(1:length(lbls)); 
        xticklabels(lbls); 
        xtickangle(45);
    end
    title('Energy Cons. (kWh)'); 
    legend({'Traction','HVAC'}); 
    grid on;
    
    % -------------------------------------------------------------------------
    % 4. CHARGING ENERGY
    % -------------------------------------------------------------------------
    nexttile(tl); 
    % Stacked bar for Fast (CC) and Slow (CV) energy
    bar(1:length(route), solution.DeltaE(route));
    xticks(1:length(route)); 
    xticklabels(string(route)); 
    title('Charged Energy (kWh)'); 
    grid on;
    
    % -------------------------------------------------------------------------
    % 5. REPLACEMENT: CONTINUOUS SOC PROFILE (Time-Based)
    % -------------------------------------------------------------------------
    nexttile(tl); 
    
    % Plot the continuous SOC line
    plot(t_log, soc_log, 'LineWidth', 2, 'Color', [0 0.4470 0.7410]); 
    hold on;
    
    % Add Battery Limits
    yline(data.SOC_max, '--g', 'Max', 'LabelHorizontalAlignment','left');
    yline(data.SOC_min, '--r', 'Min', 'LabelHorizontalAlignment','left');
    
    % Shade the area
    area(t_log, soc_log, 'FaceColor', [0.3010 0.7450 0.9330], 'FaceAlpha', 0.3, 'EdgeColor', 'none');
    
    % Formatting
    title('Real-Time SOC Profile'); 
    xlabel('Time (h)'); 
    ylabel('SOC');
    xlim([0, max(t_log)*1.1]);
    ylim([0, 1.1]);
    
    % Apply Real-Time Axis Labels (using your x_tick definitions)
    xticks(x_tick_vals);
    xticklabels(x_tick_labels);
    grid on;
    hold off;
    
    % -------------------------------------------------------------------------
    % 6. LMP PRICE HEATMAP (Real-Time Axis)
    % -------------------------------------------------------------------------
    nexttile(tl); 
    imagesc([0 24], [1 N], LMP); 
    colormap(gca, jet); 
    colorbar;
    title('Electricity Price ($/kWh)'); 
    xlabel('Time');
    
    % Apply Real-Time Axis Labels
    xticks(x_tick_vals);
    xticklabels(x_tick_labels);
    % -------------------------------------------------------------------------
    % 7. PRICE VS CHARGING TIMING (Real-Time Axis)
    % -------------------------------------------------------------------------
    nexttile(tl);
    
    % A) Prepare Price Data
    % Calculate average price across all nodes for each time slot
    avg_price_curve = mean(data.LMP, 1); 
    
    % Time vector for price (assuming data.LMP covers 24 hours or Tslots)
    t_price = linspace(0, 24, length(avg_price_curve));
    
    % B) Plot the Price Curve (Black Line)
    plot(t_price, avg_price_curve, 'k-', 'LineWidth', 1.5);
    hold on;
    
    % C) Highlight Charging Intervals (Green Zones)
    % This visualizes IF we are charging during expensive or cheap hours.
    y_lim_max = max(avg_price_curve) * 1.1;
    
    for k = 1:length(route)
        u = route(k);
        ch_dur = solution.t_ch(u);
        
        % If there is a charging event at this node
        if ch_dur > 0.01
            t_start = solution.t_arr(u);
            t_end = t_start + ch_dur;
            
            % Create a shaded rectangle for the charging duration
            x_patch = [t_start, t_end, t_end, t_start];
            y_patch = [0, 0, y_lim_max, y_lim_max];
            
            % Plot green patch
            patch(x_patch, y_patch, [0.4660 0.6740 0.1880], ...
                  'FaceAlpha', 0.3, 'EdgeColor', 'none');
        end
    end
    
    % D) Formatting
    title('Electricity Price vs. Charging Times');
    xlabel('Time (h)');
    ylabel('Price ($/kWh)');
    xlim([0, 24]);
    ylim([0, y_lim_max]);
    
    % Use the same Real-Time axis ticks as other plots
    xticks(x_tick_vals);
    xticklabels(x_tick_labels);
    
    % Add a simple legend manually to save space
    text(0.5, y_lim_max*0.9, 'Green Area = Charging', 'Color', [0.4660 0.6740 0.1880], 'FontSize', 8);
    
    grid on;
    hold off;
    
    % -------------------------------------------------------------------------
    % 8. ARRIVAL TIMES
    % -------------------------------------------------------------------------
    nexttile(tl); 
    bar(1:length(route), solution.t_arr(route)); 
    xticks(1:length(route)); 
    xticklabels(string(route)); 
    title('Arrival Time (h from Start)'); 
    grid on;
    
    % -------------------------------------------------------------------------
    % 9. WAIT / CHARGE DURATIONS
    % -------------------------------------------------------------------------
    nexttile(tl); 
    bar(1:length(route), solution.t_ch(route)); 
    xticks(1:length(route)); 
    xticklabels(string(route)); 
    title('Charging Duration (h)'); 
    grid on;
    
    % -------------------------------------------------------------------------
    % 10. REPLACEMENT: INSTANT POWER CONSUMPTION (kW)
    % -------------------------------------------------------------------------
    nexttile(tl); 
    
    % Plot Power Consumption using stairs/area
    % (Driving = High Power, Charging/Waiting = 0)
    area(p_time, p_val, 'FaceColor', [0.8500 0.3250 0.0980], 'FaceAlpha', 0.5, 'LineWidth', 1.5);
    hold on;
    
    % Add Average Power Reference
    avg_p = mean(p_val(p_val > 0));
    if ~isnan(avg_p)
        yline(avg_p, '--k', sprintf('Avg: %.1f kW', avg_p));
    end
    
    % Formatting
    title('Average Power Draw (kW)'); 
    xlabel('Time (h)'); 
    ylabel('Power (kW)');
    xlim([0, max(t_log)*1.1]);
    
    % Apply Real-Time Axis Labels
    xticks(x_tick_vals);
    xticklabels(x_tick_labels);
    grid on;
    hold off;
    
    % -------------------------------------------------------------------------
    % 11. SPACE-TIME TRAJECTORY (Real-Time Axis)
    % -------------------------------------------------------------------------
    nexttile(tl); hold on; grid on; 
    title('Space-Time Trajectory');
    tA = solution.t_arr; 
    tC = solution.t_ch;
    
    for k = 1:length(route)-1
        curr = route(k); 
        next = route(k+1);
        
        % Wait/Charge Segment (Vertical-ish if we plotted Node Index on Y)
        % Here we plot Step k vs Time
        
        % 1. Charging Duration (Horizontal line if Y is Node Index, but here Y is sequence index)
        % Let's stick to the original visualization style but update the axis
        
        % Plot Charging Phase (Red)
        plot([tA(curr) tA(curr)+tC(curr)], [k k], 'r-', 'LineWidth', 3); 
        
        % Plot Travel Phase (Blue)
        plot([tA(curr)+tC(curr) tA(next)], [k k+1], 'b-o', 'LineWidth', 1.5); 
    end
    xlim([0 24]);
    xlabel('Time'); ylabel('Route Sequence');
    
    % Apply Real-Time Axis Labels
    xticks(x_tick_vals);
    xticklabels(x_tick_labels);
    
    % --------------------------------------------------------------------------
    % 12. THERMAL COMFORT ANALYSIS (CORRECTED FOR SINGLE SCENARIO)
    % --------------------------------------------------------------------------
    nexttile;
    hold on;
    
    % --- A. Define Graph Limits ---
    % The variable 'sol.total_time' might not exist in this scope. 
    % We calculate the total duration by taking the maximum value from the 
    % arrival time array (t_arr).
    if isfield(solution, 't_arr')
        max_t_val = max(solution.t_arr);
    else
        max_t_val = 0;
    end
    
    % Safety check: If simulation time is 0 or empty, default to 1 hour to avoid plot errors.
    if isempty(max_t_val) || max_t_val < 0.1, max_t_val = 1; end 
    
    % --- Define Comfort Parameters ---
    T_target = data.Tset;
    T_lower  = data.Tset - data.T_tol;
    T_upper  = data.Tset + data.T_tol;
    
    % --- B. Draw Comfort Band (Green Shaded Area) ---
    % This creates a transparent green rectangle indicating the comfortable temp range.
    patch([0, max_t_val*1.1, max_t_val*1.1, 0], ...
          [T_lower, T_lower, T_upper, T_upper], ...
          [0.8 1 0.8], 'FaceAlpha', 0.4, 'EdgeColor', 'none', 'DisplayName', 'Comfort Zone');

    % Draw the Target Temperature Line
    yline(T_target, 'k--', 'Set Temp', 'HandleVisibility', 'off', 'LabelHorizontalAlignment', 'left');
    
    % --- C. Plot Route Temperature Profile ---
    % Calls the helper function to plot the ambient temperature the car experiences.
    % Uses a standard blue color for consistency.
    plot_thermal_curve(solution, route, data, [0 0.4470 0.7410], titlePrefix);
    
    % --- D. Axes and Labels ---
    title(['Thermal Profile: ' titlePrefix]);
    xlabel('Time (Hours)'); 
    ylabel('Ambient Temp (°C)');
    
    % Dynamic Y-axis limits to ensure the graph is readable
    ylim([min(T_lower - 5, 0), max(T_upper + 10, 40)]);
    % Set X-axis slightly larger than the trip duration
    xlim([0, max_t_val*1.05]);
    
    legend('Location', 'best', 'FontSize', 7);
    grid on;
    hold off;

end
% ==============================================================================
% HELPER: PLOT THERMAL CURVE (Time vs Segment Temperature)
% ==============================================================================
function plot_thermal_curve(solution, route, data, color, titlePrefix)
    if isempty(route) || length(route) < 2
        return;
    end
    
    time_vec = [];
    temp_vec = [];
    
    % 1. Start Point (t=0)
    % Get the temperature of the first segment at the start time.
    u1 = route(1); v1 = route(2);
    if isfield(data, 'Tseg')
        t0_temp = data.Tseg(u1, v1, 1);
    else
        t0_temp = data.Tset; 
    end
    
    time_vec(end+1) = 0;
    temp_vec(end+1) = t0_temp;
    
    % 2. Points along the route
    for k = 1:length(route)-1
        u = route(k);
        v = route(k+1);
        
        % Arrival time at node v
        if isfield(solution, 't_arr')
            t_arrival = solution.t_arr(v);
        else
            continue;
        end
        
        % Convert Time to 'Slot' index (e.g., 1.2 hours -> Which 15min slot?)
        slot_idx = floor(t_arrival / data.dt_h) + 1;
        
        % Boundary checks for slot index
        if slot_idx < 1, slot_idx = 1; end
        if slot_idx > data.Tslots, slot_idx = data.Tslots; end
        
        % Get temperature for that segment at that specific time slot
        if isfield(data, 'Tseg')
            val = data.Tseg(u, v, slot_idx);
        else
            val = data.Tset;
        end
        
        time_vec(end+1) = t_arrival;
        temp_vec(end+1) = val;
    end
    
    % Plot the curve
    plot(time_vec, temp_vec, 'Color', color, 'LineWidth', 1.5, ...
         'Marker', '.', 'MarkerSize', 8, 'DisplayName', 'Amb. Temp');
end
function plot_summary_tab(parentTab, sol_c, sol_t, sol_e, sol_d)
    % -------------------------------------------------------------------------
    % PLOT SUMMARY TAB
    % Compares Key Performance Indicators (KPIs) of different strategies.
    % -------------------------------------------------------------------------
    
    tl = tiledlayout(parentTab, 1, 5, 'Padding', 'compact', 'TileSpacing', 'compact');

    % Prepare Data
    % (We assume all solution structures are populated. Error handling for 
    % empty solutions could be added here if necessary.)
    
    strategies = {'Cost Opt', 'Time Opt', 'Energy Opt', 'Dist (Base)'};
    
    % 1. Total Time Comparison
    times = [sol_c.total_time, sol_t.total_time, sol_e.total_time, sol_d.total_time];
    
    nexttile(tl);
    bar(times, 'FaceColor', [0.2 0.2 0.5]);
    title('Total Trip Time (h)');
    set(gca, 'XTickLabel', strategies);
    grid on;
    ylabel('Hours');
    xtickangle(45);

    % 2. Total Cost Comparison
    costs = [sol_c.total_cost, sol_t.total_cost, sol_e.total_cost, sol_d.total_cost];
    
    nexttile(tl);
    bar(costs, 'FaceColor', [0.2 0.5 0.2]);
    title('Total Charging Cost ($)');
    set(gca, 'XTickLabel', strategies);
    grid on;
    ylabel('USD ($)');
    xtickangle(45);

    % 3. Total Energy Comparison
    energies = [sol_c.total_energy, sol_t.total_energy, sol_e.total_energy, sol_d.total_energy];
    
    nexttile(tl);
    bar(energies, 'FaceColor', [0.8 0.4 0.1]);
    title('Total Energy Consumed (kWh)');
    set(gca, 'XTickLabel', strategies);
    grid on;
    ylabel('kWh');
    xtickangle(45);
    
    % 4. Total Distance Comparison
    energies = [sol_c.total_dist, sol_t.total_dist, sol_e.total_dist, sol_d.total_dist];
    
    nexttile(tl);
    bar(energies, 'FaceColor', [0.5 0.2 0.5]);
    title('Total Distance Traveled (km)');
    set(gca, 'XTickLabel', strategies);
    grid on;
    ylabel('km');
    xtickangle(45);

    % 5. Compute Time Comparison
    solve_times = [sol_c.solve_time, sol_t.solve_time, sol_e.solve_time, sol_d.solve_time];
    
    nexttile(tl);
    bar(solve_times, 'FaceColor', [0.5 0.5 0.5]);
    title('Solver Computation Time (s)');
    set(gca, 'XTickLabel', {'Cost', 'Time', 'Energy', 'Dist'});
    grid on;
    ylabel('Seconds');
    xtickangle(45);

    % Main Title
    sgtitle(tl, 'Strategy Comparison Summary');
end
