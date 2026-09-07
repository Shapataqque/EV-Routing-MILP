%% =============================================================================
% FILE: summer_temperature_sensitivity_analysis.m
% PURPOSE:
%   Performs a summer-data temperature sensitivity analysis for the ENERGY
%   objective after ev_routing_milp_time_dependent_v6.m has been executed.
%
% ANALYSIS DESIGN:
%   1. Uses the original fixed summer temperature profile as the reference.
%   2. Preserves the spatial and temporal temperature pattern.
%   3. Shifts every valid arc temperature by -5, -4, ..., 0, ..., +4, +5 C.
%   4. Re-optimizes the energy-minimizing route for every temperature offset.
%   5. Separately forces the reference route to remain unchanged and calculates
%      the same-route energy impact.
%   6. Reports whether unrestricted re-optimization changes the route.
%   7. Classifies route changes as energy-equivalent or energy-improving.
%   8. Exports the numerical results as MAT and CSV files.
%
% GRAPHING:
%   Run plot_summer_temperature_sensitivity.m after this analysis.
%   The graph script does not re-run the optimization.
%
% REQUIREMENT:
%   First run ev_routing_milp_time_dependent_v6.m.
%   The MATLAB workspace must contain:
%       data_fixed          : fixed summer dataset
%       temperature_solver  : @solve_ev_routing_milp
%
% IMPORTANT:
%   Do not add "clear" to this script because it uses workspace variables
%   created by the main model.
%% =============================================================================

clc;

%% -------------------------------------------------------------------------
% 1. CHECK REQUIRED WORKSPACE VARIABLES
% --------------------------------------------------------------------------

if ~exist('data_fixed', 'var') || ~isstruct(data_fixed)
    error([ ...
        'The fixed summer dataset "data_fixed" was not found in the workspace. ' ...
        'Run ev_routing_milp_time_dependent_v6.m first.']);
end

if ~exist('temperature_solver', 'var') || ...
        ~isa(temperature_solver, 'function_handle')
    error([ ...
        'temperature_solver was not found in the workspace. ' ...
        'The main script must contain: ' ...
        'temperature_solver = @solve_ev_routing_milp;']);
end

required_fields = { ...
    'N', 'A', 'Tslots', 'Tseg', 'E0', 'tij', ...
    'Tset', 'T_tol', 'base_kW', 'alpha_h', 'alpha_c', ...
    'P_max_h', 'P_max_c', 'origin', 'dest'};

for field_idx = 1:numel(required_fields)
    field_name = required_fields{field_idx};
    if ~isfield(data_fixed, field_name)
        error('Required summer-data field is missing: data_fixed.%s', field_name);
    end
end

summer_reference_data = data_fixed;

%% -------------------------------------------------------------------------
% 2. DEFINE TEMPERATURE-OFFSET SCENARIOS
% --------------------------------------------------------------------------

% The original temperature profile is retained. Only an additive offset is
% applied to every valid arc and time slot.
temperature_offset_C = (-5:1:5)';
number_of_scenarios = numel(temperature_offset_C);
reference_scenario_idx = find(temperature_offset_C == 0, 1);

% Mean temperature is calculated only from existing arcs. Zero entries that
% represent nonexistent arcs are excluded.
reference_mean_temperature_C = calculate_existing_arc_mean_temperature( ...
    summer_reference_data);

scenario_mean_temperature_C = ...
    reference_mean_temperature_C + temperature_offset_C;

%% -------------------------------------------------------------------------
% 3. SOLVE THE REFERENCE ENERGY-OPTIMAL SUMMER CASE
% --------------------------------------------------------------------------

fprintf('\n======================================================\n');
fprintf('>>> SUMMER TEMPERATURE SENSITIVITY ANALYSIS <<<\n');
fprintf('======================================================\n');
fprintf('Reference mean ambient temperature : %.4f C\n', ...
    reference_mean_temperature_C);
fprintf('Temperature offsets                : -5 C to +5 C\n');
fprintf('Optimization objective             : Energy\n');

fprintf('\nSolving reference summer scenario (offset = 0 C)...\n');
reference_timer = tic;
reference_solution = temperature_solver( ...
    summer_reference_data, "energy");
reference_end_to_end_time_s = toc(reference_timer);

if ~isfield(reference_solution, 'problem') || ...
        reference_solution.problem ~= 0

    if isfield(reference_solution, 'info')
        reference_error_text = string(reference_solution.info);
    else
        reference_error_text = "Unknown solver error";
    end

    error('Reference summer energy optimization failed: %s', ...
        reference_error_text);
end

reference_route = get_solution_route( ...
    reference_solution, ...
    summer_reference_data.origin, ...
    summer_reference_data.dest);

if isempty(reference_route) || reference_route(end) ~= summer_reference_data.dest
    error('A valid reference route could not be extracted.');
end

reference_route_text = route_to_string(reference_route);
reference_reoptimized_energy_kWh = reference_solution.total_energy;

fprintf('Reference route                     : %s\n', reference_route_text);
fprintf('Reference total route energy        : %.6f kWh\n', ...
    reference_reoptimized_energy_kWh);


%% -------------------------------------------------------------------------
% 4. PREALLOCATE RESULTS
% --------------------------------------------------------------------------

% Unrestricted energy optimization results
reoptimized_energy_kWh = NaN(number_of_scenarios, 1);
reoptimized_deltaE_kWh = NaN(number_of_scenarios, 1);
reoptimized_deltaE_percent = NaN(number_of_scenarios, 1);
reoptimized_route = strings(number_of_scenarios, 1);
route_changed = false(number_of_scenarios, 1);
reoptimized_solver_status = strings(number_of_scenarios, 1);

% Same-reference-route results
fixed_route_energy_kWh = NaN(number_of_scenarios, 1);
fixed_route_deltaE_kWh = NaN(number_of_scenarios, 1);
fixed_route_deltaE_percent = NaN(number_of_scenarios, 1);
fixed_route_solver_status = strings(number_of_scenarios, 1);

% Computational metrics for unrestricted solves
yalmip_time_s = NaN(number_of_scenarios, 1);
solver_time_s = NaN(number_of_scenarios, 1);
optimize_wall_time_s = NaN(number_of_scenarios, 1);
end_to_end_time_s = NaN(number_of_scenarios, 1);
memory_change_MB = NaN(number_of_scenarios, 1);

% Computational metrics for fixed-route solves
fixed_route_solver_time_s = NaN(number_of_scenarios, 1);
fixed_route_end_to_end_time_s = NaN(number_of_scenarios, 1);

% Reuse the already solved reference case for offset = 0 C.
reoptimized_energy_kWh(reference_scenario_idx) = ...
    reference_reoptimized_energy_kWh;
reoptimized_deltaE_kWh(reference_scenario_idx) = 0;
reoptimized_deltaE_percent(reference_scenario_idx) = 0;
reoptimized_route(reference_scenario_idx) = string(reference_route_text);
route_changed(reference_scenario_idx) = false;
reoptimized_solver_status(reference_scenario_idx) = "Optimal";
end_to_end_time_s(reference_scenario_idx) = reference_end_to_end_time_s;

[yalmip_time_s(reference_scenario_idx), ...
 solver_time_s(reference_scenario_idx), ...
 optimize_wall_time_s(reference_scenario_idx), ...
 memory_change_MB(reference_scenario_idx)] = ...
    read_computational_metrics(reference_solution);

% The unrestricted reference solution is also energy-optimal on its own route.
fixed_route_energy_kWh(reference_scenario_idx) = ...
    reference_reoptimized_energy_kWh;
fixed_route_deltaE_kWh(reference_scenario_idx) = 0;
fixed_route_deltaE_percent(reference_scenario_idx) = 0;
fixed_route_solver_status(reference_scenario_idx) = "Optimal";
fixed_route_solver_time_s(reference_scenario_idx) = ...
    solver_time_s(reference_scenario_idx);
fixed_route_end_to_end_time_s(reference_scenario_idx) = ...
    reference_end_to_end_time_s;

%% -------------------------------------------------------------------------
% 5. RUN ALL NONZERO TEMPERATURE-OFFSET SCENARIOS
% --------------------------------------------------------------------------

for scenario_idx = 1:number_of_scenarios

    current_offset_C = temperature_offset_C(scenario_idx);

    if current_offset_C == 0
        continue;
    end

    fprintf('\n------------------------------------------------------\n');
    fprintf('Scenario %d/%d | Offset: %+d C | Mean: %.4f C\n', ...
        scenario_idx, ...
        number_of_scenarios, ...
        current_offset_C, ...
        scenario_mean_temperature_C(scenario_idx));

    % Apply the offset to the original summer temperature profile.
    data_temperature_shifted = apply_temperature_offset( ...
        summer_reference_data, current_offset_C);

    % ---------------------------------------------------------------------
    % 5A. UNRESTRICTED ENERGY RE-OPTIMIZATION
    % ---------------------------------------------------------------------
    unrestricted_timer = tic;
    unrestricted_solution = temperature_solver( ...
        data_temperature_shifted, "energy");
    end_to_end_time_s(scenario_idx) = toc(unrestricted_timer);

    if isfield(unrestricted_solution, 'problem') && ...
            unrestricted_solution.problem == 0

        reoptimized_solver_status(scenario_idx) = "Optimal";
        reoptimized_energy_kWh(scenario_idx) = ...
            unrestricted_solution.total_energy;

        current_route = get_solution_route( ...
            unrestricted_solution, ...
            summer_reference_data.origin, ...
            summer_reference_data.dest);

        reoptimized_route(scenario_idx) = ...
            string(route_to_string(current_route));

        route_changed(scenario_idx) = ...
            ~isequal(current_route(:)', reference_route(:)');

        [yalmip_time_s(scenario_idx), ...
         solver_time_s(scenario_idx), ...
         optimize_wall_time_s(scenario_idx), ...
         memory_change_MB(scenario_idx)] = ...
            read_computational_metrics(unrestricted_solution);

        fprintf('  Reoptimized energy : %.6f kWh\n', ...
            reoptimized_energy_kWh(scenario_idx));
        fprintf('  Reoptimized route  : %s\n', ...
            reoptimized_route(scenario_idx));
        fprintf('  Route changed      : %s\n', ...
            string(route_changed(scenario_idx)));

    else
        reoptimized_solver_status(scenario_idx) = ...
            get_solver_status_text(unrestricted_solution);

        fprintf('  Reoptimized model  : %s\n', ...
            reoptimized_solver_status(scenario_idx));
    end

    % ---------------------------------------------------------------------
    % 5B. SAME-ROUTE ENERGY OPTIMIZATION
    % ---------------------------------------------------------------------
    fixed_route_shifted_data = constrain_network_to_route( ...
        data_temperature_shifted, reference_route);

    fixed_route_timer = tic;
    fixed_route_solution = temperature_solver( ...
        fixed_route_shifted_data, "energy");
    fixed_route_end_to_end_time_s(scenario_idx) = toc(fixed_route_timer);

    if isfield(fixed_route_solution, 'problem') && ...
            fixed_route_solution.problem == 0

        fixed_route_solver_status(scenario_idx) = "Optimal";
        fixed_route_energy_kWh(scenario_idx) = ...
            fixed_route_solution.total_energy;

        if isfield(fixed_route_solution, 'solver_time_s')
            fixed_route_solver_time_s(scenario_idx) = ...
                fixed_route_solution.solver_time_s;
        end

        fprintf('  Same-route energy  : %.6f kWh\n', ...
            fixed_route_energy_kWh(scenario_idx));

    else
        fixed_route_solver_status(scenario_idx) = ...
            get_solver_status_text(fixed_route_solution);

        fprintf('  Same-route model   : %s\n', ...
            fixed_route_solver_status(scenario_idx));
    end
end

%% -------------------------------------------------------------------------
% 6. CALCULATE DELTA-E VALUES RELATIVE TO THE ORIGINAL SUMMER CASE
% --------------------------------------------------------------------------

reference_fixed_route_energy_kWh = ...
    fixed_route_energy_kWh(reference_scenario_idx);

valid_reoptimized = isfinite(reoptimized_energy_kWh);
reoptimized_deltaE_kWh(valid_reoptimized) = ...
    reoptimized_energy_kWh(valid_reoptimized) ...
    - reference_reoptimized_energy_kWh;

reoptimized_deltaE_percent(valid_reoptimized) = ...
    100 * reoptimized_deltaE_kWh(valid_reoptimized) ...
    / reference_reoptimized_energy_kWh;

valid_fixed_route = isfinite(fixed_route_energy_kWh);
fixed_route_deltaE_kWh(valid_fixed_route) = ...
    fixed_route_energy_kWh(valid_fixed_route) ...
    - reference_fixed_route_energy_kWh;

fixed_route_deltaE_percent(valid_fixed_route) = ...
    100 * fixed_route_deltaE_kWh(valid_fixed_route) ...
    / reference_fixed_route_energy_kWh;

%% -------------------------------------------------------------------------
% 6B. CLASSIFY ROUTE CHANGES BY THEIR ENERGY EFFECT
% --------------------------------------------------------------------------

% Positive value means re-optimization found a lower-energy route than the
% forced reference route. A near-zero value means that a different route has
% the same objective value within numerical tolerance.
reoptimization_energy_saving_kWh = ...
    fixed_route_energy_kWh - reoptimized_energy_kWh;

energy_equivalence_tolerance_kWh = max( ...
    1e-5, 1e-6 * abs(reference_reoptimized_energy_kWh));

energy_equivalent_route_change = ...
    route_changed & ...
    isfinite(reoptimization_energy_saving_kWh) & ...
    abs(reoptimization_energy_saving_kWh) <= ...
        energy_equivalence_tolerance_kWh;

energy_improving_route_change = ...
    route_changed & ...
    isfinite(reoptimization_energy_saving_kWh) & ...
    reoptimization_energy_saving_kWh > ...
        energy_equivalence_tolerance_kWh;

route_change_interpretation = strings(number_of_scenarios, 1);
route_change_interpretation(~route_changed) = "Reference route retained";
route_change_interpretation(energy_equivalent_route_change) = ...
    "Alternative route with equivalent energy";
route_change_interpretation(energy_improving_route_change) = ...
    "Alternative route with lower energy";

other_changed_idx = ...
    route_changed & ...
    route_change_interpretation == "";
route_change_interpretation(other_changed_idx) = ...
    "Alternative route; difference within solver/reporting details";

%% -------------------------------------------------------------------------
% 7. CREATE RESULT TABLE
% --------------------------------------------------------------------------

summer_temperature_results_table = table( ...
    temperature_offset_C, ...
    scenario_mean_temperature_C, ...
    fixed_route_energy_kWh, ...
    fixed_route_deltaE_kWh, ...
    fixed_route_deltaE_percent, ...
    reoptimized_energy_kWh, ...
    reoptimized_deltaE_kWh, ...
    reoptimized_deltaE_percent, ...
    route_changed, ...
    energy_equivalent_route_change, ...
    reoptimization_energy_saving_kWh, ...
    route_change_interpretation, ...
    reoptimized_route, ...
    fixed_route_solver_status, ...
    reoptimized_solver_status, ...
    fixed_route_solver_time_s, ...
    solver_time_s, ...
    yalmip_time_s, ...
    optimize_wall_time_s, ...
    fixed_route_end_to_end_time_s, ...
    end_to_end_time_s, ...
    memory_change_MB, ...
    'VariableNames', { ...
        'TemperatureOffset_C', ...
        'ScenarioMeanTemperature_C', ...
        'FixedRouteEnergy_kWh', ...
        'FixedRouteDeltaE_kWh', ...
        'FixedRouteDeltaE_percent', ...
        'ReoptimizedEnergy_kWh', ...
        'ReoptimizedDeltaE_kWh', ...
        'ReoptimizedDeltaE_percent', ...
        'RouteChanged', ...
        'EnergyEquivalentRouteChange', ...
        'ReoptimizationEnergySaving_kWh', ...
        'RouteChangeInterpretation', ...
        'ReoptimizedRoute', ...
        'FixedRouteSolverStatus', ...
        'ReoptimizedSolverStatus', ...
        'FixedRouteSolverTime_s', ...
        'ReoptimizedSolverTime_s', ...
        'ReoptimizedYALMIPTime_s', ...
        'ReoptimizedOptimizeWallTime_s', ...
        'FixedRouteEndToEndTime_s', ...
        'ReoptimizedEndToEndTime_s', ...
        'ReoptimizedNetMemoryChange_MB'});

%% -------------------------------------------------------------------------
% 8. STORE RESULTS IN WORKSPACE
% --------------------------------------------------------------------------

summer_temperature_sensitivity = struct();
summer_temperature_sensitivity.reference_dataset_name = ...
    get_dataset_name(summer_reference_data);
summer_temperature_sensitivity.reference_mean_temperature_C = ...
    reference_mean_temperature_C;
summer_temperature_sensitivity.reference_route = reference_route;
summer_temperature_sensitivity.reference_route_text = ...
    string(reference_route_text);
summer_temperature_sensitivity.reference_energy_kWh = ...
    reference_reoptimized_energy_kWh;
summer_temperature_sensitivity.temperature_offset_C = ...
    temperature_offset_C;
summer_temperature_sensitivity.scenario_mean_temperature_C = ...
    scenario_mean_temperature_C;
summer_temperature_sensitivity.fixed_route_energy_kWh = ...
    fixed_route_energy_kWh;
summer_temperature_sensitivity.fixed_route_deltaE_kWh = ...
    fixed_route_deltaE_kWh;
summer_temperature_sensitivity.fixed_route_deltaE_percent = ...
    fixed_route_deltaE_percent;
summer_temperature_sensitivity.reoptimized_energy_kWh = ...
    reoptimized_energy_kWh;
summer_temperature_sensitivity.reoptimized_deltaE_kWh = ...
    reoptimized_deltaE_kWh;
summer_temperature_sensitivity.reoptimized_deltaE_percent = ...
    reoptimized_deltaE_percent;
summer_temperature_sensitivity.route_changed = route_changed;
summer_temperature_sensitivity.energy_equivalent_route_change = ...
    energy_equivalent_route_change;
summer_temperature_sensitivity.reoptimization_energy_saving_kWh = ...
    reoptimization_energy_saving_kWh;
summer_temperature_sensitivity.route_change_interpretation = ...
    route_change_interpretation;
summer_temperature_sensitivity.reoptimized_route = reoptimized_route;
summer_temperature_sensitivity.results_table = ...
    summer_temperature_results_table;

%% -------------------------------------------------------------------------
% 9. DISPLAY AND EXPORT RESULTS
% --------------------------------------------------------------------------

fprintf('\n======================================================\n');
fprintf('>>> SUMMER TEMPERATURE SENSITIVITY RESULTS <<<\n');
fprintf('======================================================\n');
fprintf('Reference mean temperature : %.4f C\n', ...
    reference_mean_temperature_C);
fprintf('Reference route            : %s\n', reference_route_text);
fprintf('Reference energy           : %.6f kWh\n\n', ...
    reference_reoptimized_energy_kWh);

disp(summer_temperature_results_table);

plus_one_idx = find(temperature_offset_C == 1, 1);
minus_one_idx = find(temperature_offset_C == -1, 1);

if ~isempty(plus_one_idx) && isfinite(fixed_route_deltaE_kWh(plus_one_idx))
    fprintf([ ...
        '\nSame-route interpretation for +1 C:\n' ...
        '  Energy change = %+.6f kWh (%+.4f%%)\n'], ...
        fixed_route_deltaE_kWh(plus_one_idx), ...
        fixed_route_deltaE_percent(plus_one_idx));
end

if ~isempty(minus_one_idx) && isfinite(fixed_route_deltaE_kWh(minus_one_idx))
    fprintf([ ...
        'Same-route interpretation for -1 C:\n' ...
        '  Energy change = %+.6f kWh (%+.4f%%)\n'], ...
        fixed_route_deltaE_kWh(minus_one_idx), ...
        fixed_route_deltaE_percent(minus_one_idx));
end

if any(route_changed)
    fprintf('\nRoute changes detected at these offsets:\n');
    changed_rows = summer_temperature_results_table(route_changed, ...
        {'TemperatureOffset_C', ...
         'ScenarioMeanTemperature_C', ...
         'ReoptimizedRoute', ...
         'ReoptimizedDeltaE_kWh', ...
         'ReoptimizationEnergySaving_kWh', ...
         'RouteChangeInterpretation'});
    disp(changed_rows);

    if any(energy_equivalent_route_change)
        fprintf([ ...
            '\nNote: Some route changes have the same energy as the forced ' ...
            'reference route within %.6g kWh tolerance.\n' ...
            'These are alternative energy-optimal routes, not additional ' ...
            'energy savings.\n'], ...
            energy_equivalence_tolerance_kWh);
    end
else
    fprintf('\nNo route change was detected for offsets from -5 C to +5 C.\n');
end

save( ...
    'summer_temperature_sensitivity_results.mat', ...
    'summer_temperature_sensitivity', ...
    'summer_temperature_results_table');

writetable( ...
    summer_temperature_results_table, ...
    'summer_temperature_sensitivity_results.csv');


fprintf('\nResults stored in workspace as:\n');
fprintf('  summer_temperature_sensitivity\n');
fprintf('  summer_temperature_results_table\n');
fprintf('\nSaved files:\n');
fprintf('  summer_temperature_sensitivity_results.mat\n');
fprintf('  summer_temperature_sensitivity_results.csv\n');
fprintf('\nRun plot_summer_temperature_sensitivity.m to create the graph.\n');

%% =============================================================================
% LOCAL HELPER: APPLY AN ADDITIVE TEMPERATURE OFFSET
%% =============================================================================
function data_out = apply_temperature_offset(data_in, temperature_offset_C)

    data_out = data_in;

    N = data_in.N;
    K = data_in.Tslots;

    % Retain the original spatial and temporal temperature variation.
    data_out.Tseg = data_in.Tseg;

    E_dynamic = zeros(N, N, K);

    for k = 1:K
        for i = 1:N
            for j = 1:N

                if data_in.A(i,j) ~= 1
                    continue;
                end

                T_curr = ...
                    data_in.Tseg(i,j,k) + temperature_offset_C;

                data_out.Tseg(i,j,k) = T_curr;

                % Heating region
                if T_curr < (data_in.Tset - data_in.T_tol)

                    dT = ...
                        (data_in.Tset - data_in.T_tol) - T_curr;

                    P_act = min( ...
                        data_in.alpha_h * (dT^2) ...
                        + data_in.base_kW, ...
                        data_in.P_max_h);

                % Cooling region
                elseif T_curr > (data_in.Tset + data_in.T_tol)

                    dT = ...
                        T_curr - ...
                        (data_in.Tset + data_in.T_tol);

                    P_act = min( ...
                        data_in.alpha_c * (dT^2) ...
                        + data_in.base_kW, ...
                        data_in.P_max_c);

                % Comfort region
                else
                    P_act = data_in.base_kW;
                end

                E_hvac = P_act * data_in.tij(i,j);

                E_dynamic(i,j,k) = ...
                    data_in.E0(i,j) + E_hvac;
            end
        end
    end

    data_out.E_dynamic = E_dynamic;
    data_out.E = mean(E_dynamic, 3);
end

%% =============================================================================
% LOCAL HELPER: CALCULATE MEAN TEMPERATURE ON EXISTING ARCS ONLY
%% =============================================================================
function mean_temperature_C = ...
        calculate_existing_arc_mean_temperature(data_in)

    valid_arc_mask_3D = repmat( ...
        logical(data_in.A), ...
        1, 1, data_in.Tslots);

    valid_temperature_values = ...
        data_in.Tseg(valid_arc_mask_3D);

    valid_temperature_values = ...
        valid_temperature_values(isfinite(valid_temperature_values));

    if isempty(valid_temperature_values)
        error('No valid temperature values were found on existing arcs.');
    end

    mean_temperature_C = mean(valid_temperature_values);
end

%% =============================================================================
% LOCAL HELPER: CONSTRAIN THE NETWORK TO ONE REFERENCE ROUTE
%% =============================================================================
function data_out = constrain_network_to_route(data_in, route)

    data_out = data_in;
    route_adjacency = zeros(data_in.N);

    for route_idx = 1:(numel(route) - 1)
        i = route(route_idx);
        j = route(route_idx + 1);

        if data_in.A(i,j) ~= 1
            error('Reference route contains a nonexistent arc: %d -> %d.', i, j);
        end

        route_adjacency(i,j) = 1;
    end

    data_out.A = route_adjacency;
end

%% =============================================================================
% LOCAL HELPER: EXTRACT ROUTE FROM SOLUTION
%% =============================================================================
function route = get_solution_route(solution, origin, dest)

    if isfield(solution, 'route') && ~isempty(solution.route)
        route = solution.route(:)';
    elseif isfield(solution, 'x') && ~isempty(solution.x)
        route = extract_route_local(solution.x, origin, dest);
    else
        route = [];
    end

    % Remove trailing repeated/invalid entries if present.
    route = route(isfinite(route));
end

%% =============================================================================
% LOCAL HELPER: ROUTE EXTRACTION
%% =============================================================================
function route = extract_route_local(x, origin, dest)

    N = size(x, 1);
    route = origin;
    current_node = origin;

    while current_node ~= dest
        [maximum_value, next_node] = max(x(current_node, :));

        if isempty(next_node) || maximum_value < 0.5
            break;
        end

        route(end + 1) = next_node; %#ok<AGROW>
        current_node = next_node;

        if numel(route) > N
            break;
        end
    end
end

%% =============================================================================
% LOCAL HELPER: CONVERT ROUTE VECTOR TO TEXT
%% =============================================================================
function route_text = route_to_string(route)

    if isempty(route)
        route_text = 'Unavailable';
        return;
    end

    route_text = strjoin(string(route), ' -> ');
    route_text = char(route_text);
end

%% =============================================================================
% LOCAL HELPER: READ SOLVER STATUS
%% =============================================================================
function status_text = get_solver_status_text(solution)

    if isfield(solution, 'info') && strlength(string(solution.info)) > 0
        status_text = string(solution.info);
    elseif isfield(solution, 'problem')
        status_text = "Solver problem code " + string(solution.problem);
    else
        status_text = "Unknown solver error";
    end
end

%% =============================================================================
% LOCAL HELPER: READ COMPUTATIONAL METRICS
%% =============================================================================
function [yalmip_time, solver_time, wall_time, memory_change] = ...
        read_computational_metrics(solution)

    yalmip_time = NaN;
    solver_time = NaN;
    wall_time = NaN;
    memory_change = NaN;

    if isfield(solution, 'yalmip_time_s')
        yalmip_time = solution.yalmip_time_s;
    end

    if isfield(solution, 'solver_time_s')
        solver_time = solution.solver_time_s;
    end

    if isfield(solution, 'total_solve_time_s')
        wall_time = solution.total_solve_time_s;
    end

    if isfield(solution, 'memory_change_MB')
        memory_change = solution.memory_change_MB;
    end
end

%% =============================================================================
% LOCAL HELPER: DATASET NAME
%% =============================================================================
function dataset_name = get_dataset_name(data_in)

    if isfield(data_in, 'name')
        dataset_name = string(data_in.name);
    else
        dataset_name = "Fixed Summer Data";
    end
end
