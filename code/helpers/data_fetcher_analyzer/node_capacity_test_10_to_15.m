function [detailed_table, summary_table, output_folder] = node_capacity_test_10_to_15(data_fixed)
%% NODE CAPACITY TEST: 10-15 NODE INDUCED-SUBGRAPH BENCHMARK
% -------------------------------------------------------------------------
% PURPOSE
%   Compares the computational capacity of the EV-routing MILP for manually
%   selected 10, 11, 12, 13, 14 and 15-node corridors.
%
% USAGE
%   Standalone:
%       [detail, summary, folder] = node_capacity_test_10_to_15();
%
%   Reuse data_fixed already produced by the main model:
%       [detail, summary, folder] = ...
%           node_capacity_test_10_to_15(data_fixed);
%
% TEST DESIGN
%   - Dataset          : Fixed summer data (15 July 2025)
%   - Objectives       : distance, cost, time, energy
%   - Measured repeats : 50 per node-count/objective combination
%   - Warm-up          : 1 unmeasured solve per combination
%   - Total measured   : 6 x 4 x 50 = 1200 optimization runs
%   - Subgraph type    : Induced subgraph
%   - Solver           : YALMIP + intlinprog
%
% IMPORTANT
%   Removed nodes and every arc entering/leaving those nodes are physically
%   removed from all node-indexed matrices and tensors. This reduces the
%   actual MILP dimensions rather than merely disabling nodes in a 15-node
%   model.
% -------------------------------------------------------------------------

clc;

%% 1. CONFIGURATION
config.repetitions = 1;
config.warmup_runs_per_combination = 1;
config.random_seed = 20260805;
config.stop_if_no_origin_destination_path = true;
config.objectives = ["distance", "cost", "time", "energy"];
config.export_figures = true;
config.verbose_solver = 0;

% Original 15-node labels retained in each reduced corridor.
node_sets = {
    [1,2,3,4,5,7,12,13,14,15]                         % 10 nodes
    [1,2,3,4,5,7,9,12,13,14,15]                       % 11 nodes
    [1,2,3,4,5,7,9,10,12,13,14,15]                    % 12 nodes
    [1,2,3,4,5,6,7,9,10,12,13,14,15]                  % 13 nodes
    [1,2,3,4,5,6,7,9,10,11,12,13,14,15]               % 14 nodes
    1:15                                                % 15 nodes
};

node_counts = cellfun(@numel, node_sets)';

%% 2. LOAD OR VALIDATE THE FIXED SUMMER DATASET
if nargin < 1 || isempty(data_fixed)
    fprintf('Loading fixed summer dataset independently...\n');
    data_fixed = build_fixed_summer_data_15_node();
else
    fprintf('Using data_fixed supplied to the function...\n');
end

validate_full_dataset(data_fixed);

%% 3. CREATE OUTPUT FOLDER
run_stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
output_folder = fullfile(pwd, ['node_capacity_results_' run_stamp]);
if ~exist(output_folder, 'dir')
    mkdir(output_folder);
end

fprintf('\n============================================================\n');
fprintf('NODE CAPACITY TEST: 10 TO 15 NODES\n');
fprintf('Measured repetitions per combination: %d\n', config.repetitions);
fprintf('Objectives: %s\n', strjoin(config.objectives, ', '));
fprintf('Output folder: %s\n', output_folder);
fprintf('============================================================\n');

%% 4. BUILD THE REDUCED DATASETS
scenario_data = cell(numel(node_sets), 1);
scenario_path_exists = false(numel(node_sets), 1);
scenario_arc_counts = zeros(numel(node_sets), 1);

for s = 1:numel(node_sets)
    kept_original_nodes = node_sets{s};
    data_small = reduce_to_induced_subgraph(data_fixed, kept_original_nodes);

    scenario_data{s} = data_small;
    scenario_arc_counts(s) = nnz(data_small.A);
    scenario_path_exists(s) = has_directed_path( ...
        data_small.A, data_small.origin, data_small.dest);

    fprintf('\n%d-node scenario\n', data_small.N);
    fprintf('  Original labels : %s\n', num2str(kept_original_nodes));
    fprintf('  Existing arcs   : %d\n', scenario_arc_counts(s));
    fprintf('  O-D path exists : %s\n', yes_no(scenario_path_exists(s)));

    if ~scenario_path_exists(s)
        message = sprintf([ ...
            '%d-node induced subgraph has no directed path from original ' ...
            'node %d to original node %d.'], ...
            data_small.N, data_fixed.origin, data_fixed.dest);

        if config.stop_if_no_origin_destination_path
            error('%s Adjust the retained node list or set the stop flag to false.', ...
                message);
        else
            warning('%s Solver runs will probably be infeasible.', message);
        end
    end
end

%% 5. DEFINE ALL NODE-COUNT / OBJECTIVE COMBINATIONS
combination_count = numel(node_sets) * numel(config.objectives);
combinations = repmat(struct( ...
    'scenario_index', NaN, ...
    'node_count', NaN, ...
    'objective', ""), combination_count, 1);

c = 0;
for s = 1:numel(node_sets)
    for o = 1:numel(config.objectives)
        c = c + 1;
        combinations(c).scenario_index = s;
        combinations(c).node_count = scenario_data{s}.N;
        combinations(c).objective = config.objectives(o);
    end
end

%% 6. WARM-UP RUNS — EXCLUDED FROM ALL STATISTICS
fprintf('\n============================================================\n');
fprintf('WARM-UP PHASE — NOT RECORDED\n');
fprintf('============================================================\n');

for c = 1:combination_count
    s = combinations(c).scenario_index;
    mode = combinations(c).objective;
    data_run = prepare_objective_dataset(scenario_data{s}, mode);

    fprintf('Warm-up %2d/%2d | N=%d | objective=%s\n', ...
        c, combination_count, data_run.N, mode);

    for w = 1:config.warmup_runs_per_combination
        solve_ev_routing_milp_capacity(data_run, mode, config.verbose_solver);
    end
end

%% 7. MEASURED RUNS
measured_run_count = combination_count * config.repetitions;
records = repmat(empty_result_record(), measured_run_count, 1);
record_index = 0;

rng(config.random_seed, 'twister');

fprintf('\n============================================================\n');
fprintf('MEASURED PHASE — %d OPTIMIZATION RUNS\n', measured_run_count);
fprintf('============================================================\n');

% Each repetition contains every combination once, in a randomized order.
% This reduces systematic bias from machine warm-up or background load.
for repetition = 1:config.repetitions
    combination_order = randperm(combination_count);

    fprintf('\n--- Repetition %d/%d ---\n', repetition, config.repetitions);

    for order_position = 1:combination_count
        c = combination_order(order_position);
        s = combinations(c).scenario_index;
        mode = combinations(c).objective;

        base_scenario = scenario_data{s};
        data_run = prepare_objective_dataset(base_scenario, mode);

        record_index = record_index + 1;

        fprintf('[%4d/%4d] N=%d | arcs=%d | objective=%-8s | rep=%02d ... ', ...
            record_index, measured_run_count, data_run.N, nnz(data_run.A), ...
            char(mode), repetition);

        sol = solve_ev_routing_milp_capacity( ...
            data_run, mode, config.verbose_solver);

        records(record_index) = make_result_record( ...
            sol, data_run, node_sets{s}, mode, repetition, ...
            scenario_path_exists(s));

        fprintf('%s | solver %.4f s | optimize %.4f s\n', ...
            char(records(record_index).Status), ...
            records(record_index).SolverTime_s, ...
            records(record_index).OptimizeWallTime_s);
    end
end

%% 8. DETAILED TABLE
detailed_table = struct2table(records);
detailed_table = sortrows(detailed_table, ...
    {'NodeCount', 'Objective', 'Repetition'});

%% 9. SUMMARY TABLE
summary_table = build_summary_table( ...
    detailed_table, node_counts, config.objectives);
summary_table = sortrows(summary_table, {'NodeCount', 'Objective'});

%% 10. EXPORT CSV AND MAT FILES
detailed_csv = fullfile(output_folder, ...
    'node_capacity_detailed_results.csv');
summary_csv = fullfile(output_folder, ...
    'node_capacity_summary_results.csv');
mat_file = fullfile(output_folder, ...
    'node_capacity_results.mat');

writetable(detailed_table, detailed_csv);
writetable(summary_table, summary_csv);

save(mat_file, ...
    'detailed_table', 'summary_table', 'config', 'node_sets', ...
    'scenario_arc_counts', 'scenario_path_exists', '-v7.3');

%% 11. CAPACITY PLOTS
if config.export_figures
    create_capacity_plot(summary_table, ...
        'MedianSolverTime_s', ...
        'Median Solver Time', ...
        'Solver time (s)', ...
        fullfile(output_folder, 'median_solver_time.png'));

    create_capacity_plot(summary_table, ...
        'MedianOptimizeWallTime_s', ...
        'Median optimize() Wall Time', ...
        'Wall time (s)', ...
        fullfile(output_folder, 'median_optimize_wall_time.png'));

    create_capacity_plot(summary_table, ...
        'MedianEndToEndTime_s', ...
        'Median End-to-End Time', ...
        'Time (s)', ...
        fullfile(output_folder, 'median_end_to_end_time.png'));
end

%% 12. DISPLAY FINAL SUMMARY
fprintf('\n============================================================\n');
fprintf('CAPACITY TEST COMPLETED\n');
fprintf('============================================================\n');
disp(summary_table(:, { ...
    'NodeCount', 'ArcCount', 'Objective', ...
    'OptimalRuns', 'InfeasibleRuns', 'OtherFailureRuns', ...
    'MeanSolverTime_s', 'MedianSolverTime_s', 'StdSolverTime_s', ...
    'MedianRelativeGap_percent', 'MaxRelativeGap_percent', ...
    'MeanOptimizeWallTime_s', 'MedianOptimizeWallTime_s', ...
    'StdOptimizeWallTime_s'}));

fprintf('Detailed CSV : %s\n', detailed_csv);
fprintf('Summary CSV  : %s\n', summary_csv);
fprintf('MAT file     : %s\n', mat_file);

end

%% =========================================================================
% REDUCE FULL DATASET TO AN INDUCED SUBGRAPH
% =========================================================================
function data_small = reduce_to_induced_subgraph(data_full, kept_original_nodes)

kept_original_nodes = kept_original_nodes(:)';

if any(kept_original_nodes < 1) || ...
        any(kept_original_nodes > data_full.N) || ...
        numel(unique(kept_original_nodes)) ~= numel(kept_original_nodes)
    error('The retained-node list contains an invalid or repeated node index.');
end

if ~ismember(data_full.origin, kept_original_nodes)
    error('The origin node must remain in every reduced scenario.');
end

if ~ismember(data_full.dest, kept_original_nodes)
    error('The destination node must remain in every reduced scenario.');
end

data_small = data_full;
data_small.original_node_ids = kept_original_nodes;
data_small.N = numel(kept_original_nodes);
data_small.origin = find(kept_original_nodes == data_full.origin, 1);
data_small.dest = find(kept_original_nodes == data_full.dest, 1);

% N x N matrices
matrix_fields = {'A', 'tij', 'E0', 'dist', 'E'};
for f = 1:numel(matrix_fields)
    field_name = matrix_fields{f};
    if isfield(data_full, field_name)
        full_value = data_full.(field_name);
        data_small.(field_name) = ...
            full_value(kept_original_nodes, kept_original_nodes);
    end
end

% N x N x K tensors
three_dimensional_fields = {'E_dynamic', 'Tseg'};
for f = 1:numel(three_dimensional_fields)
    field_name = three_dimensional_fields{f};
    if isfield(data_full, field_name)
        full_value = data_full.(field_name);
        data_small.(field_name) = full_value( ...
            kept_original_nodes, kept_original_nodes, :);
    end
end

% N x K matrices
node_time_fields = {'LMP'};
for f = 1:numel(node_time_fields)
    field_name = node_time_fields{f};
    if isfield(data_full, field_name)
        full_value = data_full.(field_name);
        data_small.(field_name) = ...
            full_value(kept_original_nodes, :);
    end
end

% N x p node attributes
if isfield(data_full, 'coords')
    data_small.coords = data_full.coords(kept_original_nodes, :);
end

% N x 1 node vectors
node_vector_fields = {'P_charge_kW'};
for f = 1:numel(node_vector_fields)
    field_name = node_vector_fields{f};
    if isfield(data_full, field_name)
        full_value = data_full.(field_name);
        data_small.(field_name) = ...
            full_value(kept_original_nodes, :);
    end
end

% Explicitly guarantee that no self-loop survives.
data_small.A(1:data_small.N+1:end) = 0;

end

%% =========================================================================
% OBJECTIVE-SPECIFIC DATA PREPARATION
% =========================================================================
function data_run = prepare_objective_dataset(data_in, mode)

data_run = data_in;

% Preserve the behavior of the original main model: the distance objective
% uses static traction energy rather than temperature-dependent HVAC energy.
if mode == "distance"
    data_run.E_dynamic = repmat( ...
        data_run.E0, 1, 1, data_run.Tslots);
    data_run.E = data_run.E0;
end

end

%% =========================================================================
% MILP SOLVER — SINGLE optimize() CALL
% =========================================================================
function solution = solve_ev_routing_milp_capacity(data, mode, verbose_level)

import yalmip.*

if nargin < 2
    mode = "cost";
end
if nargin < 3
    verbose_level = 0;
end
mode = lower(string(mode));

% Prevent YALMIP's internal variable database from accumulating over 1200
% independent test runs. This clearing is intentionally outside the timing.
yalmip('clear');

end_to_end_timer = tic;
model_build_timer = tic;

%% Unpack data
N       = data.N;
A       = data.A;
tij     = data.tij;
Ebat    = data.Ebat;
SOCmin  = data.SOC_min;
SOCmax  = data.SOC_max;
SOCinit = data.SOC_init;
SOCdest = data.min_SOC_at_dest;
origin  = data.origin;
dest    = data.dest;
P_charge_vec = data.P_charge_kW;
LMP     = data.LMP;
K       = data.Tslots;
dt      = data.dt_h;

M_time = K * dt + 5;
M_soc = 2.0;

%% Decision variables
x       = binvar(N, N, 'full');
visit   = binvar(N, 1);
y       = binvar(N, N, K, 'full');
SOC_dep = sdpvar(N, 1);
SOC_arr = sdpvar(N, 1);
DeltaE  = sdpvar(N, 1);
t_ch    = sdpvar(N, 1);
t_arr   = sdpvar(N, 1);
z       = binvar(N, K, 'full');
Eik     = sdpvar(N, K, 'full');
a       = binvar(N, K, 'full');
u       = sdpvar(N, 1);

constraints = [];

%% A. Network flow
constraints = [constraints, x(eye(N) == 1) == 0];
constraints = [constraints, x(A == 0) == 0];
constraints = [constraints, sum(x(origin, :)) == 1];
constraints = [constraints, sum(x(:, origin)) == 0];
constraints = [constraints, sum(x(:, dest)) == 1];
constraints = [constraints, sum(x(dest, :)) == 0];

for i = 1:N
    if i ~= origin && i ~= dest
        constraints = [constraints, ...
            sum(x(i, :)) == sum(x(:, i))]; %#ok<AGROW>
        constraints = [constraints, ...
            sum(x(i, :)) == visit(i)]; %#ok<AGROW>
    end
end
constraints = [constraints, visit(origin) == 1, visit(dest) == 1];

%% B. MTZ subtour elimination
constraints = [constraints, u >= 0, u <= N];
constraints = [constraints, u(origin) == 1];

for i = 1:N
    if i ~= origin && i ~= dest
        constraints = [constraints, u(i) >= 2 * visit(i)]; %#ok<AGROW>
        constraints = [constraints, u(i) <= N * visit(i)]; %#ok<AGROW>
    end
end

M_u = N;
for i = 1:N
    for j = 1:N
        if i ~= j && A(i, j) == 1
            if j == origin || i == dest
                continue;
            end
            constraints = [constraints, ...
                u(j) >= u(i) + 1 - M_u * (1 - x(i, j))]; %#ok<AGROW>
        end
    end
end

%% C. Link static x and time-indexed y
for i = 1:N
    for j = 1:N
        if A(i, j) == 1
            constraints = [constraints, ...
                sum(y(i, j, :)) == x(i, j)]; %#ok<AGROW>
        else
            constraints = [constraints, y(i, j, :) == 0]; %#ok<AGROW>
        end
    end
end

%% D. Arrival-slot synchronization
for j = 1:N
    if j ~= origin
        for k = 1:K
            constraints = [constraints, ...
                a(j, k) == sum(y(:, j, k))]; %#ok<AGROW>
        end
        constraints = [constraints, sum(a(j, :)) == visit(j)]; %#ok<AGROW>

        for k = 1:K
            constraints = [constraints, ...
                t_arr(j) >= (k - 1) * dt - M_time * (1 - a(j, k))]; %#ok<AGROW>
            constraints = [constraints, ...
                t_arr(j) <= k * dt + M_time * (1 - a(j, k))]; %#ok<AGROW>
        end
    end
end

%% E. Battery dynamics
for i = 1:N
    for j = 1:N
        if A(i, j) == 1
            cons_dynamic = sum( ...
                squeeze(y(i, j, :)) .* ...
                squeeze(data.E_dynamic(i, j, :))) / Ebat;

            constraints = [constraints, ...
                SOC_arr(j) <= SOC_dep(i) - cons_dynamic + ...
                M_soc * (1 - x(i, j))]; %#ok<AGROW>
            constraints = [constraints, ...
                SOC_arr(j) >= SOC_dep(i) - cons_dynamic - ...
                M_soc * (1 - x(i, j))]; %#ok<AGROW>
        end
    end
end

constraints = [constraints, SOC_dep == SOC_arr + DeltaE / Ebat];
constraints = [constraints, SOCmin <= SOC_arr <= SOCmax];
constraints = [constraints, SOCmin <= SOC_dep <= SOCmax];
constraints = [constraints, SOC_dep(origin) == SOCinit];
constraints = [constraints, SOC_arr(dest) >= SOCdest];
constraints = [constraints, DeltaE(origin) == 0];
constraints = [constraints, DeltaE(dest) == 0];

for i = 1:N
    P = P_charge_vec(i);
    if P > 0
        constraints = [constraints, t_ch(i) == DeltaE(i) / P]; %#ok<AGROW>
        constraints = [constraints, ...
            DeltaE(i) <= Ebat * visit(i)]; %#ok<AGROW>
    else
        constraints = [constraints, DeltaE(i) == 0]; %#ok<AGROW>
        constraints = [constraints, t_ch(i) == 0]; %#ok<AGROW>
    end
end

%% F. Time continuity
constraints = [constraints, t_arr(origin) == 0];
for i = 1:N
    for j = 1:N
        if A(i, j) == 1
            constraints = [constraints, ...
                t_arr(j) >= t_arr(i) + t_ch(i) + tij(i, j) - ...
                M_time * (1 - x(i, j))]; %#ok<AGROW>
            constraints = [constraints, ...
                t_arr(j) <= t_arr(i) + t_ch(i) + tij(i, j) + ...
                M_time * (1 - x(i, j))]; %#ok<AGROW>
        end
    end
end
constraints = [constraints, t_arr <= K * dt];

%% G. Charging-slot allocation
for i = 1:N
    if P_charge_vec(i) > 0
        constraints = [constraints, ...
            sum(z(i, :)) <= K * visit(i)]; %#ok<AGROW>
        constraints = [constraints, ...
            sum(Eik(i, :)) == DeltaE(i)]; %#ok<AGROW>

        max_energy_per_slot = P_charge_vec(i) * dt;
        constraints = [constraints, ...
            0 <= Eik(i, :) <= max_energy_per_slot * z(i, :)]; %#ok<AGROW>

        for k = 1:K
            time_of_slot_start = (k - 1) * dt;
            constraints = [constraints, ...
                time_of_slot_start >= t_arr(i) - ...
                M_time * (1 - z(i, k))]; %#ok<AGROW>
            constraints = [constraints, ...
                time_of_slot_start <= t_arr(i) + t_ch(i) + ...
                M_time * (1 - z(i, k))]; %#ok<AGROW>
        end
    else
        constraints = [constraints, Eik(i, :) == 0]; %#ok<AGROW>
        constraints = [constraints, z(i, :) == 0]; %#ok<AGROW>
    end
end

%% Objective
cost_term = sum(sum(Eik .* LMP));
time_term = t_arr(dest);
energy_term = sum(sum(sum(y .* data.E_dynamic)));
dist_term = sum(sum(x .* data.dist));

switch mode
    case "cost"
        objective = cost_term;
    case "time"
        objective = time_term;
    case "energy"
        objective = energy_term;
    case "distance"
        objective = dist_term + 0.001 * time_term;
    otherwise
        error('Unknown optimization mode: %s', mode);
end

opts = sdpsettings( ...
    'solver', 'intlinprog', ...
    'verbose', verbose_level, ...
    'cachesolvers', 1, ...
    'savesolveroutput', 1);

model_build_time_s = toc(model_build_timer);

%% Memory before the single optimization call
memory_before_MB = NaN;
memory_after_MB = NaN;
memory_change_MB = NaN;
try
    memory_before = memory;
    memory_before_MB = memory_before.MemUsedMATLAB / 1024^2;
catch
end

%% Exactly one optimize() call
optimize_timer = tic;
sol = optimize(constraints, objective, opts);

fprintf('\n===== GAP DEBUG =====\n');

disp('YALMIP diagnostics fields:');
disp(fieldnames(sol));

if isfield(sol,'solveroutput')
    disp('solveroutput:');
    disp(sol.solveroutput);

    if isstruct(sol.solveroutput)
        disp('solveroutput fields:');
        disp(fieldnames(sol.solveroutput));

        if isfield(sol.solveroutput,'output')
            disp('solveroutput.output:');
            disp(sol.solveroutput.output);

            if isstruct(sol.solveroutput.output)
                disp('solveroutput.output fields:');
                disp(fieldnames(sol.solveroutput.output));
            end
        end
    end
else
    error('solveroutput DOES NOT EXIST');
end

fprintf('=====================\n');

optimize_wall_time_s = toc(optimize_timer);

try
    memory_after = memory;
    memory_after_MB = memory_after.MemUsedMATLAB / 1024^2;
    memory_change_MB = memory_after_MB - memory_before_MB;
catch
end

%% Result structure
solution = struct();
solution.mode = mode;
solution.problem = sol.problem;
solution.info = string(sol.info);
solution.model_build_time_s = model_build_time_s;
solution.optimize_wall_time_s = optimize_wall_time_s;
solution.yalmip_time_s = safe_diagnostic_field(sol, 'yalmiptime');
solution.solver_time_s = safe_diagnostic_field(sol, 'solvertime');
solution.memory_before_MB = memory_before_MB;
solution.memory_after_MB = memory_after_MB;
solution.memory_change_MB = memory_change_MB;

%% Optimality gap extraction
solution.relative_gap = NaN;
solution.absolute_gap = NaN;

if isfield(sol, 'solveroutput') && ~isempty(sol.solveroutput)

    solver_out = sol.solveroutput;

    % Case 1: intlinprog output is stored inside .output
    if isstruct(solver_out) && ...
            isfield(solver_out, 'output') && ...
            ~isempty(solver_out.output)

        raw_output = solver_out.output;

    % Case 2: intlinprog output stored directly
    else
        raw_output = solver_out;
    end

    if isstruct(raw_output)

        if isfield(raw_output, 'relativegap') && ...
                ~isempty(raw_output.relativegap)
            solution.relative_gap = raw_output.relativegap;
        end

        if isfield(raw_output, 'absolutegap') && ...
                ~isempty(raw_output.absolutegap)
            solution.absolute_gap = raw_output.absolutegap;
        end
    end
end

solution.relative_gap_percent = ...
    100 * solution.relative_gap;

% Approximate variable counts from the declared full arrays.
solution.approx_binary_variables = ...
    N^2 + N + N^2 * K + 2 * N * K;
solution.approx_continuous_variables = 6 * N + N * K;

if sol.problem == 0
    solution.status = "Optimal";
    solution.x = value(x);
    solution.route = extract_route_safe(solution.x, origin, dest);
    solution.objective_value = value(objective);
    solution.total_cost = value(cost_term);
    solution.total_time = value(time_term);
    solution.total_energy = value(energy_term);
    solution.total_dist = value(dist_term);
else
    solution.status = classify_problem_code(sol.problem);
    solution.x = NaN(N, N);
    solution.route = [];
    solution.objective_value = NaN;
    solution.total_cost = NaN;
    solution.total_time = NaN;
    solution.total_energy = NaN;
    solution.total_dist = NaN;
end

solution.end_to_end_time_s = toc(end_to_end_timer);

end

%% =========================================================================
% RESULT RECORD CREATION
% =========================================================================
function record = make_result_record( ...
    sol, data_run, original_nodes, mode, repetition, topology_path_exists)

record = empty_result_record();
record.NodeCount = data_run.N;
record.ArcCount = nnz(data_run.A);
record.Objective = string(mode);
record.Repetition = repetition;
record.Status = string(sol.status);
record.ProblemCode = sol.problem;
record.SolverInfo = string(sol.info);
record.TopologyPathExists = topology_path_exists;
record.YALMIPTime_s = sol.yalmip_time_s;
record.SolverTime_s = sol.solver_time_s;

record.RelativeGap = sol.relative_gap;
record.RelativeGap_percent = sol.relative_gap_percent;
record.AbsoluteGap = sol.absolute_gap;

record.ModelBuildTime_s = sol.model_build_time_s;
record.OptimizeWallTime_s = sol.optimize_wall_time_s;
record.EndToEndTime_s = sol.end_to_end_time_s;
record.MemoryBefore_MB = sol.memory_before_MB;
record.MemoryAfter_MB = sol.memory_after_MB;
record.MemoryChange_MB = sol.memory_change_MB;
record.ApproxBinaryVariables = sol.approx_binary_variables;
record.ApproxContinuousVariables = sol.approx_continuous_variables;
record.ObjectiveValue = sol.objective_value;
record.TotalDistance_km = sol.total_dist;
record.TotalTime_h = sol.total_time;
record.TotalEnergy_kWh = sol.total_energy;
record.TotalCost_USD = sol.total_cost;
record.KeptOriginalNodes = strjoin(string(original_nodes), '-');

if sol.problem == 0 && ~isempty(sol.route)
    original_route = original_nodes(sol.route);
    record.RouteOriginal = strjoin(string(original_route), '-');
else
    record.RouteOriginal = "";
end

record.RunTimestamp = string(datetime('now', ...
    'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));

end

function record = empty_result_record()
record = struct( ...
    'NodeCount', NaN, ...
    'ArcCount', NaN, ...
    'Objective', "", ...
    'Repetition', NaN, ...
    'Status', "", ...
    'ProblemCode', NaN, ...
    'SolverInfo', "", ...
    'TopologyPathExists', false, ...
    'YALMIPTime_s', NaN, ...
    'SolverTime_s', NaN, ...
    'RelativeGap', NaN, ...
    'RelativeGap_percent', NaN, ...
    'AbsoluteGap', NaN, ...
    'ModelBuildTime_s', NaN, ...
    'OptimizeWallTime_s', NaN, ...
    'EndToEndTime_s', NaN, ...
    'MemoryBefore_MB', NaN, ...
    'MemoryAfter_MB', NaN, ...
    'MemoryChange_MB', NaN, ...
    'ApproxBinaryVariables', NaN, ...
    'ApproxContinuousVariables', NaN, ...
    'ObjectiveValue', NaN, ...
    'TotalDistance_km', NaN, ...
    'TotalTime_h', NaN, ...
    'TotalEnergy_kWh', NaN, ...
    'TotalCost_USD', NaN, ...
    'KeptOriginalNodes', "", ...
    'RouteOriginal', "", ...
    'RunTimestamp', "");
end

%% =========================================================================
% SUMMARY STATISTICS
% =========================================================================
function summary_table = build_summary_table( ...
    detailed_table, node_counts, objectives)

summary_count = numel(node_counts) * numel(objectives);
rows = repmat(empty_summary_record(), summary_count, 1);
row_index = 0;

for n = node_counts(:)'
    for o = 1:numel(objectives)
        objective_name = objectives(o);
        selection = detailed_table.NodeCount == n & ...
            detailed_table.Objective == objective_name;
        group = detailed_table(selection, :);

        row_index = row_index + 1;
        row = empty_summary_record();

        row.NodeCount = n;
        row.ArcCount = first_finite(group.ArcCount);
        row.Objective = objective_name;
        row.TotalRuns = height(group);
        row.OptimalRuns = sum(group.Status == "Optimal");
        row.InfeasibleRuns = sum(group.Status == "Infeasible");
        row.OtherFailureRuns = row.TotalRuns - ...
            row.OptimalRuns - row.InfeasibleRuns;
        row.SuccessRate_percent = 100 * row.OptimalRuns / row.TotalRuns;
        row.TopologyPathExists = all(group.TopologyPathExists);
        row.ApproxBinaryVariables = first_finite( ...
            group.ApproxBinaryVariables);
        row.ApproxContinuousVariables = first_finite( ...
            group.ApproxContinuousVariables);

        [row.MeanYALMIPTime_s, row.MedianYALMIPTime_s, ...
            row.StdYALMIPTime_s] = three_statistics(group.YALMIPTime_s);

        [row.MeanSolverTime_s, row.MedianSolverTime_s, ...
            row.StdSolverTime_s] = three_statistics(group.SolverTime_s);

        [row.MeanRelativeGap_percent, row.MedianRelativeGap_percent, ...
            row.StdRelativeGap_percent] = ...
            three_statistics(group.RelativeGap_percent);

        valid_gaps = group.RelativeGap_percent( ...
            isfinite(group.RelativeGap_percent));

        if isempty(valid_gaps)
            row.MaxRelativeGap_percent = NaN;
        else
            row.MaxRelativeGap_percent = max(valid_gaps);
        end

        [row.MeanModelBuildTime_s, row.MedianModelBuildTime_s, ...
            row.StdModelBuildTime_s] = ...
            three_statistics(group.ModelBuildTime_s);

        [row.MeanOptimizeWallTime_s, row.MedianOptimizeWallTime_s, ...
            row.StdOptimizeWallTime_s] = ...
            three_statistics(group.OptimizeWallTime_s);

        [row.MeanEndToEndTime_s, row.MedianEndToEndTime_s, ...
            row.StdEndToEndTime_s] = ...
            three_statistics(group.EndToEndTime_s);

        [row.MeanMemoryChange_MB, row.MedianMemoryChange_MB, ...
            row.StdMemoryChange_MB] = ...
            three_statistics(group.MemoryChange_MB);

        optimal_group = group(group.Status == "Optimal", :);
        [row.MeanObjectiveValue, row.MedianObjectiveValue, ...
            row.StdObjectiveValue] = ...
            three_statistics(optimal_group.ObjectiveValue);

        rows(row_index) = row;
    end
end

summary_table = struct2table(rows);

end

function row = empty_summary_record()
row = struct( ...
    'NodeCount', NaN, ...
    'ArcCount', NaN, ...
    'Objective', "", ...
    'TotalRuns', NaN, ...
    'OptimalRuns', NaN, ...
    'InfeasibleRuns', NaN, ...
    'OtherFailureRuns', NaN, ...
    'SuccessRate_percent', NaN, ...
    'TopologyPathExists', false, ...
    'ApproxBinaryVariables', NaN, ...
    'ApproxContinuousVariables', NaN, ...
    'MeanYALMIPTime_s', NaN, ...
    'MedianYALMIPTime_s', NaN, ...
    'StdYALMIPTime_s', NaN, ...
    'MeanSolverTime_s', NaN, ...
    'MedianSolverTime_s', NaN, ...
    'StdSolverTime_s', NaN, ...
    'MeanRelativeGap_percent', NaN, ...
    'MedianRelativeGap_percent', NaN, ...
    'StdRelativeGap_percent', NaN, ...
    'MaxRelativeGap_percent', NaN, ...
    'MeanModelBuildTime_s', NaN, ...
    'MedianModelBuildTime_s', NaN, ...
    'StdModelBuildTime_s', NaN, ...
    'MeanOptimizeWallTime_s', NaN, ...
    'MedianOptimizeWallTime_s', NaN, ...
    'StdOptimizeWallTime_s', NaN, ...
    'MeanEndToEndTime_s', NaN, ...
    'MedianEndToEndTime_s', NaN, ...
    'StdEndToEndTime_s', NaN, ...
    'MeanMemoryChange_MB', NaN, ...
    'MedianMemoryChange_MB', NaN, ...
    'StdMemoryChange_MB', NaN, ...
    'MeanObjectiveValue', NaN, ...
    'MedianObjectiveValue', NaN, ...
    'StdObjectiveValue', NaN);
end

function [mean_value, median_value, std_value] = three_statistics(values)
values = values(isfinite(values));
if isempty(values)
    mean_value = NaN;
    median_value = NaN;
    std_value = NaN;
    return;
end
mean_value = mean(values);
median_value = median(values);
if numel(values) > 1
    std_value = std(values, 0);
else
    std_value = 0;
end
end

function value_out = first_finite(values)
values = values(isfinite(values));
if isempty(values)
    value_out = NaN;
else
    value_out = values(1);
end
end

%% =========================================================================
% PLOTS
% =========================================================================
function create_capacity_plot( ...
    summary_table, metric_name, plot_title, y_label, output_file)

fig = figure('Visible', 'off', 'Name', plot_title);
hold on;
grid on;

objectives = unique(summary_table.Objective, 'stable');
for o = 1:numel(objectives)
    objective_name = objectives(o);
    rows = summary_table(summary_table.Objective == objective_name, :);
    rows = sortrows(rows, 'NodeCount');
    plot(rows.NodeCount, rows.(metric_name), '-o', ...
        'LineWidth', 1.5, 'DisplayName', char(objective_name));
end

xlabel('Number of nodes');
ylabel(y_label);
title(plot_title);
xticks(unique(summary_table.NodeCount));
legend('Location', 'best');

try
    exportgraphics(fig, output_file, 'Resolution', 200);
catch
    saveas(fig, output_file);
end
close(fig);

end

%% =========================================================================
% GRAPH AND DIAGNOSTIC HELPERS
% =========================================================================
function tf = has_directed_path(A, origin, dest)
G = digraph(A);
d = distances(G, origin, dest);
tf = isfinite(d);
end

function output = yes_no(input_value)
if input_value
    output = 'YES';
else
    output = 'NO';
end
end

function value_out = safe_diagnostic_field(diagnostic, field_name)
if isfield(diagnostic, field_name)
    value_out = diagnostic.(field_name);
else
    value_out = NaN;
end
end

function status = classify_problem_code(problem_code)
switch problem_code
    case 1
        status = "Infeasible";
    case 2
        status = "Unbounded";
    case 3
        status = "SolverLimitOrFailure";
    case 4
        status = "NumericalProblem";
    case 9
        status = "UnknownSolverProblem";
    otherwise
        status = "FailureCode_" + string(problem_code);
end
end

function route = extract_route_safe(x, origin, dest)
N = size(x, 1);
route = origin;
current_node = origin;
visited_guard = false(N, 1);
visited_guard(current_node) = true;

while current_node ~= dest
    candidate_values = x(current_node, :);
    [best_value, next_node] = max(candidate_values);

    if isempty(best_value) || best_value < 0.5
        route = [];
        return;
    end

    if visited_guard(next_node)
        route = [];
        return;
    end

    route(end + 1) = next_node; %#ok<AGROW>
    current_node = next_node;
    visited_guard(current_node) = true;

    if numel(route) > N
        route = [];
        return;
    end
end
end

%% =========================================================================
% DATASET VALIDATION
% =========================================================================
function validate_full_dataset(data)
required_fields = { ...
    'N', 'origin', 'dest', 'A', 'tij', 'E0', 'dist', ...
    'E_dynamic', 'Ebat', 'SOC_min', 'SOC_max', 'SOC_init', ...
    'min_SOC_at_dest', 'P_charge_kW', 'LMP', 'Tslots', 'dt_h'};

for f = 1:numel(required_fields)
    if ~isfield(data, required_fields{f})
        error('Required data field is missing: %s', required_fields{f});
    end
end

if data.N ~= 15
    error('The capacity test expects a full 15-node base dataset.');
end

if size(data.A, 1) ~= 15 || size(data.A, 2) ~= 15
    error('data.A must be a 15 x 15 matrix.');
end

if size(data.E_dynamic, 1) ~= 15 || ...
        size(data.E_dynamic, 2) ~= 15 || ...
        size(data.E_dynamic, 3) ~= data.Tslots
    error('data.E_dynamic must have dimensions 15 x 15 x Tslots.');
end
end

%% =========================================================================
% INDEPENDENT FIXED SUMMER DATA GENERATOR
% =========================================================================
function data = build_fixed_summer_data_15_node()

current_hour = 10;
N = 15;

data.start_hour = current_hour;
data.N = N;
data.origin = 1;
data.dest = 15;

data.coords = [
    58 92;
    45 82;
    63 68;
    35 78;
    14 58;
    32 48;
    52 36;
    80 48;
    11 46;
    22 33;
    39 28;
    12 28;
    40 12;
    25 08;
    18 04
];

%% Road data
road_file = 'Analiz_Sonuclari_Final.xlsx';
if ~isfile(road_file)
    error('Road-data file not found: %s', road_file);
end

opts = detectImportOptions(road_file);
opts.VariableNamingRule = 'preserve';
route_data = readtable(road_file, opts);

A = zeros(N);
E0_static = zeros(N);
tij = zeros(N);
dist_matrix = zeros(N);

base_rate = 0.16;
climb_penalty = 0.006;
descent_bonus = 0.0035;

for row = 1:height(route_data)
    i = route_data.Start(row);
    j = route_data.End(row);
    distance_km = route_data.Distance_km(row);
    gain = route_data.TotalGain(row);
    loss = route_data.TotalLoss(row);
    travel_time_min = route_data.TravelTime_min(row);

    A(i, j) = 1;
    dist_matrix(i, j) = distance_km;
    E0_static(i, j) = distance_km * base_rate + ...
        gain * climb_penalty - loss * descent_bonus;
    tij(i, j) = travel_time_min / 60;
end

data.A = A;
data.tij = tij;
data.E0 = E0_static;
data.dist = dist_matrix;

%% Time setup
data.dt_min = 15;
data.dt_h = data.dt_min / 60;
data.Tslots = 96;

%% Fixed weather
weather_file = 'Fixed_Weather_Data_15July.xlsx';
if ~isfile(weather_file)
    error('Fixed weather file not found: %s', weather_file);
end

weather_table = readtable(weather_file, 'ReadRowNames', true);
node_temperature_24h = table2array(weather_table);

if size(node_temperature_24h, 1) ~= N || ...
        size(node_temperature_24h, 2) ~= 24
    error('Fixed weather data must be a 15 x 24 matrix.');
end

node_temperature_24h = circshift( ...
    node_temperature_24h, -current_hour, 2);

%% HVAC parameters
data.Tset = 22;
data.T_tol = 2.0;
data.base_kW = 0.3;
data.alpha_h = 0.12;
data.alpha_c = 0.08;
data.P_max_h = 5.0;
data.P_max_c = 3.0;

original_hours = 1:24;
target_slots = linspace(1, 24, data.Tslots);
node_temperature_high_resolution = zeros(N, data.Tslots);

for n = 1:N
    node_temperature_high_resolution(n, :) = interp1( ...
        original_hours, node_temperature_24h(n, :), ...
        target_slots, 'pchip');
end

E_dynamic = zeros(N, N, data.Tslots);
data.Tseg = zeros(N, N, data.Tslots);

for k = 1:data.Tslots
    for i = 1:N
        for j = 1:N
            if A(i, j) ~= 1
                continue;
            end

            current_temperature = ...
                node_temperature_high_resolution(j, k);
            data.Tseg(i, j, k) = current_temperature;

            if current_temperature < data.Tset - data.T_tol
                delta_temperature = data.Tset - data.T_tol - ...
                    current_temperature;
                active_power = min( ...
                    data.alpha_h * delta_temperature^2 + data.base_kW, ...
                    data.P_max_h);
            elseif current_temperature > data.Tset + data.T_tol
                delta_temperature = current_temperature - ...
                    (data.Tset + data.T_tol);
                active_power = min( ...
                    data.alpha_c * delta_temperature^2 + data.base_kW, ...
                    data.P_max_c);
            else
                active_power = data.base_kW;
            end

            hvac_energy = active_power * tij(i, j);
            E_dynamic(i, j, k) = E0_static(i, j) + hvac_energy;
        end
    end
end

data.E_dynamic = E_dynamic;
data.E = mean(E_dynamic, 3);

%% Battery and charging parameters
data.Ebat = 80;
data.SOC_min = 0.10;
data.SOC_max = 0.95;
data.SOC_init = 0.35;
data.min_SOC_at_dest = 0.25;

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

%% Fixed LMP data
lmp_file = 'LMP_PJM_Data_Altered.xlsx';
if ~isfile(lmp_file)
    warning('LMP file not found. A constant 0.30 USD/kWh profile is used.');
    data.LMP = 0.30 * ones(N, data.Tslots);
else
    opts_lmp = detectImportOptions(lmp_file, 'Sheet', 'Sheet1');
    opts_lmp.VariableNamingRule = 'preserve';
    lmp_table = readtable(lmp_file, opts_lmp);

    lmp_high_resolution = zeros(N, data.Tslots);
    original_price_hours = 0:23;
    target_price_slots = linspace(0, 23.75, data.Tslots);

    for i = 1:N
        node_rows = lmp_table( ...
            lmp_table.("Node Karşılığı") == i, :);

        if ismember('datetime_beginning_ept', ...
                node_rows.Properties.VariableNames)
            node_rows = sortrows(node_rows, ...
                'datetime_beginning_ept');
        end

        prices_24h = node_rows.("kWh format");

        if isempty(prices_24h)
            error('No LMP records were found for original node %d.', i);
        elseif numel(prices_24h) < 24
            prices_24h = [prices_24h; ...
                repmat(mean(prices_24h), ...
                24 - numel(prices_24h), 1)];
        elseif numel(prices_24h) > 24
            prices_24h = prices_24h(1:24);
        end

        shifted_prices = circshift(prices_24h, -current_hour);
        lmp_high_resolution(i, :) = interp1( ...
            original_price_hours, shifted_prices, ...
            target_price_slots, 'previous', 'extrap');
    end

    data.LMP = lmp_high_resolution;
end

data.w_time = 1.0;
data.w_ch = 3.0;
data.w_cost = 5.0;

end
