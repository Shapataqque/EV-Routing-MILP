function [benchmark, summary_table, output_folder] = price_awareness_benchmark(data_fixed)
%% PRICE-AWARE vs PRICE-UNAWARE BENCHMARK
% Compares the same MILP under two price-information settings:
%   1) Price-aware: original time- and location-varying LMP matrix.
%   2) Price-unaware: one uniform price equal to the global mean LMP.
%
% Fair comparison rule:
%   The price-unaware solution is evaluated ex post using the ORIGINAL
%   dynamic LMP matrix. The reported saving is therefore attributable to
%   access to dynamic price information, not to changing the objective.
%
% To remove degeneracy caused by a completely uniform price, the
% price-unaware baseline is selected lexicographically without using any
% dynamic-price information:
%   Stage 1: minimum uniform-price charging cost
%   Stage 2: among Stage-1 optima, minimum trip time
%   Stage 3: among Stage-1/2 optima, minimum route distance
%   Stage 4: among Stage-1/2/3 optima, earliest charging-slot allocation
%
% Recommended usage after running the main model:
%   [benchmark, summary_table, output_folder] = ...
%       price_awareness_benchmark(data_fixed);

clc;

%% 1. Obtain data_fixed
if nargin < 1 || isempty(data_fixed)
    if evalin('base','exist(''data_fixed'',''var'')')
        data_fixed = evalin('base','data_fixed');
        fprintf('Using data_fixed from base workspace.\n');
    else
        error(['data_fixed not found. Run the main model first, then call ' ...
            'price_awareness_benchmark(data_fixed).']);
    end
end

validate_benchmark_dataset(data_fixed);

%% 2. Configuration
config.verbose_solver = 0;
config.cost_abs_tolerance = 1e-4;
config.time_abs_tolerance = 1e-4;
config.distance_abs_tolerance = 1e-4;
config.output_folder = fullfile(pwd,'price_awareness_benchmark_output');

if ~exist(config.output_folder,'dir')
    mkdir(config.output_folder);
end
output_folder = config.output_folder;

actual_LMP = data_fixed.LMP;
finite_prices = actual_LMP(isfinite(actual_LMP));
if isempty(finite_prices)
    error('No finite values exist in data_fixed.LMP.');
end
uniform_price = mean(finite_prices);

fprintf('\n============================================================\n');
fprintf('PRICE-AWARE vs PRICE-UNAWARE BENCHMARK\n');
fprintf('Nodes: %d | Arcs: %d | Slots: %d\n', ...
    data_fixed.N, nnz(data_fixed.A), data_fixed.Tslots);
fprintf('Uniform baseline price: %.8f USD/kWh\n', uniform_price);
fprintf('============================================================\n');

%% 3. Price-aware case
fprintf('\n[1/5] Solving PRICE-AWARE case...\n');
aware = solve_price_benchmark_model(data_fixed,"cost",struct(), ...
    config.verbose_solver);
if aware.problem ~= 0
    error('Price-aware case failed: %s',aware.info);
end
aware.nominal_optimization_cost_USD = aware.total_cost;
aware.realized_dynamic_cost_USD = sum(aware.Eik .* actual_LMP,'all');
aware.total_charged_energy_kWh = sum(aware.DeltaE);

%% 4. Price-unaware dataset: no temporal or spatial price information
unaware_data = data_fixed;
unaware_data.LMP = uniform_price * ones(size(actual_LMP));

%% 5. Lexicographic price-unaware baseline
fprintf('[2/5] Price-unaware Stage 1: minimum uniform-price cost...\n');
u1 = solve_price_benchmark_model(unaware_data,"cost",struct(), ...
    config.verbose_solver);
if u1.problem ~= 0
    error('Price-unaware Stage 1 failed: %s',u1.info);
end

cost_tol = max(config.cost_abs_tolerance,1e-7*max(1,abs(u1.total_cost)));
caps2.cost_cap = u1.total_cost + cost_tol;

fprintf('[3/5] Price-unaware Stage 2: minimum time among cost-optima...\n');
u2 = solve_price_benchmark_model(unaware_data,"time",caps2, ...
    config.verbose_solver);
if u2.problem ~= 0
    error('Price-unaware Stage 2 failed: %s',u2.info);
end

time_tol = max(config.time_abs_tolerance,1e-7*max(1,abs(u2.total_time)));
caps3 = caps2;
caps3.time_cap = u2.total_time + time_tol;

fprintf('[4/5] Price-unaware Stage 3: minimum distance among ties...\n');
u3 = solve_price_benchmark_model(unaware_data,"distance",caps3, ...
    config.verbose_solver);
if u3.problem ~= 0
    error('Price-unaware Stage 3 failed: %s',u3.info);
end

dist_tol = max(config.distance_abs_tolerance,1e-7*max(1,abs(u3.total_dist)));
caps4 = caps3;
caps4.distance_cap = u3.total_dist + dist_tol;

fprintf('[5/5] Price-unaware Stage 4: earliest price-independent charging...\n');
unaware = solve_price_benchmark_model(unaware_data,"earliest",caps4, ...
    config.verbose_solver);
if unaware.problem ~= 0
    error('Price-unaware Stage 4 failed: %s',unaware.info);
end

unaware.nominal_optimization_cost_USD = unaware.total_cost;
unaware.realized_dynamic_cost_USD = sum(unaware.Eik .* actual_LMP,'all');
unaware.total_charged_energy_kWh = sum(unaware.DeltaE);

%% 6. Price-awareness benefit
absolute_cost_saving_USD = unaware.realized_dynamic_cost_USD - ...
    aware.realized_dynamic_cost_USD;

if unaware.realized_dynamic_cost_USD > 0
    cost_saving_percent = 100 * absolute_cost_saving_USD / ...
        unaware.realized_dynamic_cost_USD;
else
    cost_saving_percent = NaN;
end

%% 7. Package results
benchmark.created_at = datetime('now');
benchmark.uniform_price_USD_per_kWh = uniform_price;
benchmark.actual_LMP = actual_LMP;
benchmark.config = config;
benchmark.aware = aware;
benchmark.unaware = unaware;
benchmark.unaware_stage1 = u1;
benchmark.unaware_stage2 = u2;
benchmark.unaware_stage3 = u3;
benchmark.absolute_cost_saving_USD = absolute_cost_saving_USD;
benchmark.cost_saving_percent = cost_saving_percent;

%% 8. Summary table
Strategy = ["Price-unaware";"Price-aware"];
OptimizationPriceModel = ["Uniform global mean"; ...
    "Time- and location-varying LMP"];
Route = [route_to_string(unaware.route);route_to_string(aware.route)];
NominalOptimizationCost_USD = [unaware.nominal_optimization_cost_USD; ...
    aware.nominal_optimization_cost_USD];
RealizedDynamicCost_USD = [unaware.realized_dynamic_cost_USD; ...
    aware.realized_dynamic_cost_USD];
TotalChargedEnergy_kWh = [unaware.total_charged_energy_kWh; ...
    aware.total_charged_energy_kWh];
TotalRouteEnergy_kWh = [unaware.total_energy;aware.total_energy];
TotalTripTime_h = [unaware.total_time;aware.total_time];
TotalDistance_km = [unaware.total_dist;aware.total_dist];
SolverTime_s = [unaware.solver_time_s;aware.solver_time_s];
RelativeGap_percent = [unaware.relative_gap_percent; ...
    aware.relative_gap_percent];

summary_table = table(Strategy,OptimizationPriceModel,Route, ...
    NominalOptimizationCost_USD,RealizedDynamicCost_USD, ...
    TotalChargedEnergy_kWh,TotalRouteEnergy_kWh,TotalTripTime_h, ...
    TotalDistance_km,SolverTime_s,RelativeGap_percent);

%% 9. Slot-level schedule table
K = data_fixed.Tslots;
dt = data_fixed.dt_h;
TimeSlot = (1:K)';
TimeFromDeparture_h = (0:K-1)'*dt;
PriceUnawareCharging_kWh = sum(unaware.Eik,1)';
PriceAwareCharging_kWh = sum(aware.Eik,1)';
SystemMeanActualLMP_USD_per_kWh = mean(actual_LMP,1,'omitnan')';

charging_schedule_table = table(TimeSlot,TimeFromDeparture_h, ...
    PriceUnawareCharging_kWh,PriceAwareCharging_kWh, ...
    SystemMeanActualLMP_USD_per_kWh);

%% 10. Export
mat_file = fullfile(output_folder,'price_awareness_benchmark_results.mat');
summary_csv = fullfile(output_folder,'price_awareness_benchmark_summary.csv');
schedule_csv = fullfile(output_folder,'price_awareness_charging_schedule.csv');

save(mat_file,'benchmark','summary_table','charging_schedule_table', ...
    'config','-v7.3');
writetable(summary_table,summary_csv);
writetable(charging_schedule_table,schedule_csv);

%% 11. Console report
fprintf('\n============================================================\n');
fprintf('BENCHMARK RESULTS\n');
fprintf('============================================================\n');
fprintf('Price-unaware route      : %s\n',route_to_string(unaware.route));
fprintf('Price-aware route        : %s\n',route_to_string(aware.route));
fprintf('Unaware realized cost    : %.6f USD\n', ...
    unaware.realized_dynamic_cost_USD);
fprintf('Aware realized cost      : %.6f USD\n', ...
    aware.realized_dynamic_cost_USD);
fprintf('Absolute saving          : %.6f USD\n',absolute_cost_saving_USD);
fprintf('Price-awareness saving   : %.3f %%\n',cost_saving_percent);
fprintf('Output folder            : %s\n',output_folder);
fprintf('============================================================\n');

end

%% =========================================================================
% CORE SOLVER: same model structure as the current main formulation
% =========================================================================
function solution = solve_price_benchmark_model(data,objective_mode,caps,verbose_level)

import yalmip.*
if nargin < 3 || isempty(caps), caps = struct(); end
if nargin < 4, verbose_level = 0; end
objective_mode = lower(string(objective_mode));

yalmip('clear');

N = data.N; A = data.A; tij = data.tij;
Ebat = data.Ebat; SOCmin = data.SOC_min; SOCmax = data.SOC_max;
SOCinit = data.SOC_init; SOCdest = data.min_SOC_at_dest;
origin = data.origin; dest = data.dest;
P_charge_vec = data.P_charge_kW; LMP = data.LMP;
K = data.Tslots; dt = data.dt_h;

M_time = K*dt + 5;
M_soc = 2.0;
M_u = N;

%% Decision variables
x = binvar(N,N,'full');
visit = binvar(N,1);
y = binvar(N,N,K,'full');
SOC_dep = sdpvar(N,1);
SOC_arr = sdpvar(N,1);
DeltaE = sdpvar(N,1);
t_ch = sdpvar(N,1);
t_arr = sdpvar(N,1);
z = binvar(N,K,'full');
Eik = sdpvar(N,K,'full');
a = binvar(N,K,'full');
u = sdpvar(N,1);

constraints = [];

%% A. Network flow
constraints = [constraints,x(eye(N)==1)==0];
constraints = [constraints,x(A==0)==0];
constraints = [constraints,sum(x(origin,:))==1];
constraints = [constraints,sum(x(:,origin))==0];
constraints = [constraints,sum(x(:,dest))==1];
constraints = [constraints,sum(x(dest,:))==0];

for i = 1:N
    if i ~= origin && i ~= dest
        constraints = [constraints,sum(x(i,:))==sum(x(:,i))]; %#ok<AGROW>
        constraints = [constraints,sum(x(i,:))==visit(i)]; %#ok<AGROW>
    end
end
constraints = [constraints,visit(origin)==1,visit(dest)==1];

%% B. MTZ
constraints = [constraints,u>=0,u<=N,u(origin)==1];
for i = 1:N
    if i ~= origin && i ~= dest
        constraints = [constraints,u(i)>=2*visit(i)]; %#ok<AGROW>
        constraints = [constraints,u(i)<=N*visit(i)]; %#ok<AGROW>
    end
end
for i = 1:N
    for j = 1:N
        if i ~= j && A(i,j)==1
            if j==origin || i==dest, continue; end
            constraints = [constraints, ...
                u(j)>=u(i)+1-M_u*(1-x(i,j))]; %#ok<AGROW>
        end
    end
end

%% C. x-y linkage
for i = 1:N
    for j = 1:N
        if A(i,j)==1
            constraints = [constraints,sum(y(i,j,:))==x(i,j)]; %#ok<AGROW>
        else
            constraints = [constraints,y(i,j,:)==0]; %#ok<AGROW>
        end
    end
end

%% D. Arrival-slot synchronization
for j = 1:N
    if j ~= origin
        for k = 1:K
            constraints = [constraints,a(j,k)==sum(y(:,j,k))]; %#ok<AGROW>
        end
        constraints = [constraints,sum(a(j,:))==visit(j)]; %#ok<AGROW>
        for k = 1:K
            constraints = [constraints,t_arr(j)>=(k-1)*dt- ...
                M_time*(1-a(j,k))]; %#ok<AGROW>
            constraints = [constraints,t_arr(j)<=k*dt+ ...
                M_time*(1-a(j,k))]; %#ok<AGROW>
        end
    end
end

%% E. Battery dynamics
for i = 1:N
    for j = 1:N
        if A(i,j)==1
            cons_dynamic = sum(squeeze(y(i,j,:)).* ...
                squeeze(data.E_dynamic(i,j,:)))/Ebat;
            constraints = [constraints,SOC_arr(j)<=SOC_dep(i)- ...
                cons_dynamic+M_soc*(1-x(i,j))]; %#ok<AGROW>
            constraints = [constraints,SOC_arr(j)>=SOC_dep(i)- ...
                cons_dynamic-M_soc*(1-x(i,j))]; %#ok<AGROW>
        end
    end
end

constraints = [constraints,SOC_dep==SOC_arr+DeltaE/Ebat];
constraints = [constraints,SOCmin<=SOC_arr<=SOCmax];
constraints = [constraints,SOCmin<=SOC_dep<=SOCmax];
constraints = [constraints,SOC_dep(origin)==SOCinit];
constraints = [constraints,SOC_arr(dest)>=SOCdest];
constraints = [constraints,DeltaE(origin)==0,DeltaE(dest)==0];

for i = 1:N
    P = P_charge_vec(i);
    if P > 0
        constraints = [constraints,t_ch(i)==DeltaE(i)/P]; %#ok<AGROW>
        constraints = [constraints,DeltaE(i)<=Ebat*visit(i)]; %#ok<AGROW>
    else
        constraints = [constraints,DeltaE(i)==0,t_ch(i)==0]; %#ok<AGROW>
    end
end

%% F. Time continuity
constraints = [constraints,t_arr(origin)==0];
for i = 1:N
    for j = 1:N
        if A(i,j)==1
            constraints = [constraints,t_arr(j)>=t_arr(i)+t_ch(i)+ ...
                tij(i,j)-M_time*(1-x(i,j))]; %#ok<AGROW>
            constraints = [constraints,t_arr(j)<=t_arr(i)+t_ch(i)+ ...
                tij(i,j)+M_time*(1-x(i,j))]; %#ok<AGROW>
        end
    end
end
constraints = [constraints,t_arr<=K*dt];

%% G. Charging-slot allocation
for i = 1:N
    if P_charge_vec(i) > 0
        constraints = [constraints,sum(z(i,:))<=K*visit(i)]; %#ok<AGROW>
        constraints = [constraints,sum(Eik(i,:))==DeltaE(i)]; %#ok<AGROW>
        max_energy_per_slot = P_charge_vec(i)*dt;
        constraints = [constraints,0<=Eik(i,:)<= ...
            max_energy_per_slot*z(i,:)]; %#ok<AGROW>
        for k = 1:K
            slot_start = (k-1)*dt;
            constraints = [constraints,slot_start>=t_arr(i)- ...
                M_time*(1-z(i,k))]; %#ok<AGROW>
            constraints = [constraints,slot_start<=t_arr(i)+t_ch(i)+ ...
                M_time*(1-z(i,k))]; %#ok<AGROW>
        end
    else
        constraints = [constraints,Eik(i,:)==0,z(i,:)==0]; %#ok<AGROW>
    end
end

%% Expressions
cost_term = sum(sum(Eik.*LMP));
time_term = t_arr(dest);
energy_term = sum(sum(sum(y.*data.E_dynamic)));
dist_term = sum(sum(x.*data.dist));
slot_weights = repmat(1:K,N,1);
earliest_term = sum(sum(Eik.*slot_weights));

%% Lexicographic caps
if isfield(caps,'cost_cap') && isfinite(caps.cost_cap)
    constraints = [constraints,cost_term<=caps.cost_cap];
end
if isfield(caps,'time_cap') && isfinite(caps.time_cap)
    constraints = [constraints,time_term<=caps.time_cap];
end
if isfield(caps,'distance_cap') && isfinite(caps.distance_cap)
    constraints = [constraints,dist_term<=caps.distance_cap];
end

%% Stage objective
switch objective_mode
    case "cost"
        objective = cost_term;
    case "time"
        objective = time_term;
    case "distance"
        objective = dist_term;
    case "earliest"
        objective = earliest_term;
    otherwise
        error('Unknown objective mode: %s',objective_mode);
end

opts = sdpsettings('solver','intlinprog','verbose',verbose_level, ...
    'cachesolvers',1,'savesolveroutput',1);

solve_timer = tic;
diagnostic = optimize(constraints,objective,opts);
optimize_wall_time_s = toc(solve_timer);

solution.problem = diagnostic.problem;
solution.info = string(diagnostic.info);
solution.yalmip_time_s = safe_diag_value(diagnostic,'yalmiptime');
solution.solver_time_s = safe_diag_value(diagnostic,'solvertime');
solution.optimize_wall_time_s = optimize_wall_time_s;
solution.relative_gap = extract_solver_gap(diagnostic,"relative");
solution.absolute_gap = extract_solver_gap(diagnostic,"absolute");
solution.relative_gap_percent = 100*solution.relative_gap;

if diagnostic.problem == 0
    solution.status = "Optimal";
    solution.x = value(x);
    solution.visit = value(visit);
    solution.y = value(y);
    solution.SOC_dep = value(SOC_dep);
    solution.SOC_arr = value(SOC_arr);
    solution.DeltaE = value(DeltaE);
    solution.t_ch = value(t_ch);
    solution.t_arr = value(t_arr);
    solution.z = value(z);
    solution.Eik = value(Eik);
    solution.total_cost = value(cost_term);
    solution.total_time = value(time_term);
    solution.total_energy = value(energy_term);
    solution.total_dist = value(dist_term);
    solution.route = extract_route_safe(solution.x,origin,dest);
else
    solution.status = "Failure";
    solution.x = NaN(N);
    solution.visit = NaN(N,1);
    solution.y = NaN(N,N,K);
    solution.SOC_dep = NaN(N,1);
    solution.SOC_arr = NaN(N,1);
    solution.DeltaE = NaN(N,1);
    solution.t_ch = NaN(N,1);
    solution.t_arr = NaN(N,1);
    solution.z = NaN(N,K);
    solution.Eik = NaN(N,K);
    solution.total_cost = NaN;
    solution.total_time = NaN;
    solution.total_energy = NaN;
    solution.total_dist = NaN;
    solution.route = [];
end

end

%% =========================================================================
% Helpers
% =========================================================================
function validate_benchmark_dataset(data)
required_fields = {'N','origin','dest','A','tij','dist','E_dynamic', ...
    'Ebat','SOC_min','SOC_max','SOC_init','min_SOC_at_dest', ...
    'P_charge_kW','LMP','Tslots','dt_h'};
for f = 1:numel(required_fields)
    if ~isfield(data,required_fields{f})
        error('Missing data field: %s',required_fields{f});
    end
end
if ~isequal(size(data.LMP),[data.N,data.Tslots])
    error('data.LMP must be N x Tslots.');
end
if size(data.E_dynamic,1)~=data.N || size(data.E_dynamic,2)~=data.N || ...
        size(data.E_dynamic,3)~=data.Tslots
    error('data.E_dynamic must be N x N x Tslots.');
end
end

function route = extract_route_safe(x,origin,dest)
N = size(x,1);
route = origin;
current = origin;
visited = false(N,1);
visited(origin) = true;
while current ~= dest
    [best,next] = max(x(current,:));
    if isempty(best) || best < 0.5 || visited(next)
        route = [];
        return;
    end
    route(end+1) = next; %#ok<AGROW>
    current = next;
    visited(current) = true;
    if numel(route) > N
        route = [];
        return;
    end
end
end

function out = route_to_string(route)
if isempty(route)
    out = "";
else
    out = strjoin(string(route),'-');
end
end

function value_out = safe_diag_value(diagnostic,field_name)
if isfield(diagnostic,field_name)
    value_out = diagnostic.(field_name);
else
    value_out = NaN;
end
end

function gap_value = extract_solver_gap(diagnostic,gap_type)
gap_value = NaN;
if ~isfield(diagnostic,'solveroutput') || isempty(diagnostic.solveroutput)
    return;
end
if gap_type == "relative"
    names = {'relativegap','RelativeGap','relativeGap','mipgap','MIPGap'};
else
    names = {'absolutegap','AbsoluteGap','absoluteGap'};
end
gap_value = find_numeric_field_recursive(diagnostic.solveroutput,names,0,6);
end

function value_found = find_numeric_field_recursive(input_value,names,depth,max_depth)
value_found = NaN;
if depth > max_depth, return; end

if isstruct(input_value)
    fields = fieldnames(input_value);
    for c = 1:numel(names)
        for f = 1:numel(fields)
            if strcmpi(fields{f},names{c})
                candidate = input_value.(fields{f});
                if isnumeric(candidate) && isscalar(candidate) && isfinite(candidate)
                    value_found = double(candidate);
                    return;
                end
            end
        end
    end
    for f = 1:numel(fields)
        candidate = input_value.(fields{f});
        if isstruct(candidate) || iscell(candidate)
            value_found = find_numeric_field_recursive(candidate,names,depth+1,max_depth);
            if isfinite(value_found), return; end
        end
    end
elseif iscell(input_value)
    for i = 1:numel(input_value)
        value_found = find_numeric_field_recursive(input_value{i},names,depth+1,max_depth);
        if isfinite(value_found), return; end
    end
end
end
