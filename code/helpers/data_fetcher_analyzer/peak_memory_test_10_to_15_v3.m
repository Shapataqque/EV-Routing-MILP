function [detailed_table, summary_table, output_folder] = peak_memory_test_10_to_15_v3(varargin)
detailed_table = [];
summary_table = [];
output_folder = '';
%% PEAK MEMORY TEST FOR 10-15 NODE EV-ROUTING MILP
% =========================================================================
% PURPOSE
%   Measures peak MATLAB-process memory while optimize() is running for the
%   same 10-15 node induced-subgraph cases used in the capacity benchmark.
%
% WHY A CHILD MATLAB PROCESS?
%   intlinprog blocks the MATLAB session that calls optimize(). Therefore,
%   this benchmark launches each measured case in a fresh MATLAB process and
%   monitors that child process from the parent MATLAB process. This avoids
%   relying on before/after memory differences and reduces carry-over from
%   previous solves.
%
% PRIMARY OUTPUT METRICS
%   PeakOptimizeWorkingSet_MB
%       Maximum physical RAM resident in the child MATLAB process while
%       optimize() is active.
%
%   PeakOptimizePrivateMemory_MB
%       Maximum private process memory while optimize() is active.
%
%   AdditionalPeakWorkingSet_MB
%       PeakOptimizeWorkingSet_MB minus the working set immediately before
%       optimize(). This is an approximate incremental RAM increase during
%       the solver call, NOT isolated intlinprog-only memory.
%
%   PeakModelPlusSolveWorkingSet_MB
%       Peak physical RAM from the start of YALMIP model construction until
%       optimize() finishes.
%
% NORMAL USAGE
%   After the main EV-routing script has created data_fixed:
%
%       [detail, summary, folder] = peak_memory_test_10_to_15_v3(data_fixed);
%
%   Or, if data_fixed exists in the base workspace:
%
%       [detail, summary, folder] = peak_memory_test_10_to_15_v3();
%
% PUBLICATION SETTINGS / MEASUREMENT DESIGN
%   Default repetitions = 3.
%   Memory is sampled externally every 50 ms from the PID reported by the
%   worker MATLAB process itself. A PID/ready handshake is used so the parent
%   attaches to the actual worker process before model construction begins.
%
% IMPORTANT
%   - Windows only (uses .NET System.Diagnostics.Process).
%   - Each measured case runs in a fresh MATLAB child process.
%   - No figures are created.
%   - The same MILP structure and induced-subgraph node sets are used as in
%     node_capacity_test_10_to_15.
%   - Reported peak memory is MATLAB-process memory, not isolated intlinprog
%     memory. "AdditionalPeak..." is the increase above the process baseline
%     immediately before the measured phase.
% =========================================================================

%% INTERNAL WORKER DISPATCH
if nargin >= 1 && (ischar(varargin{1}) || isstring(varargin{1}))
    action = lower(string(varargin{1}));
    if action == "worker"
        worker_main(varargin{2:end});
        return;
    end
end

%% PARENT BENCHMARK
if ~ispc
    error(['This benchmark is written for Windows because it monitors a ' ...
           'separate MATLAB process through System.Diagnostics.Process.']);
end

%% 1. CONFIGURATION
config.repetitions = 20;           % Publication-oriented default
config.sample_period_s = 0.05;     % 50 ms external memory sampling
config.worker_pid_timeout_s = 60;  % Wait for worker PID handshake
config.monitor_ready_timeout_s = 60;
config.run_completion_timeout_s = 600; % Safety timeout for failed monitoring
config.objectives = ["distance","cost","time","energy"];
config.verbose_solver = 0;

node_sets = {
    [1,2,3,4,5,7,12,13,14,15]                         % 10
    [1,2,3,4,5,7,9,12,13,14,15]                       % 11
    [1,2,3,4,5,7,9,10,12,13,14,15]                    % 12
    [1,2,3,4,5,6,7,9,10,12,13,14,15]                  % 13
    [1,2,3,4,5,6,7,9,10,11,12,13,14,15]               % 14
    1:15                                                % 15
};

%% 2. GET data_fixed
if nargin >= 1 && isstruct(varargin{1})
    data_fixed = varargin{1};
elseif evalin('base', 'exist(''data_fixed'',''var'')')
    data_fixed = evalin('base', 'data_fixed');
else
    error(['data_fixed was not supplied and was not found in the base ' ...
           'workspace. Run the main model first or call ' ...
           'peak_memory_test_10_to_15_v3(data_fixed).']);
end

validate_full_dataset(data_fixed);

%% 3. OUTPUT FOLDER
run_stamp = char(datetime('now','Format','yyyyMMdd_HHmmss'));
output_folder = fullfile(pwd, ['peak_memory_results_' run_stamp]);
mkdir(output_folder);

parent_path = path; %#ok<NASGU>
input_mat = fullfile(output_folder, 'peak_memory_input.mat');
save(input_mat, 'data_fixed', 'parent_path', 'node_sets', 'config', '-v7.3');

script_file = mfilename('fullpath');
script_dir = fileparts(script_file);
matlab_exe = fullfile(matlabroot, 'bin', 'matlab.exe');

fprintf('\n============================================================\n');
fprintf('PEAK MEMORY TEST: 10 TO 15 NODES\n');
fprintf('Fresh MATLAB process per measured run\n');
fprintf('Repetitions per combination : %d\n', config.repetitions);
fprintf('Sampling interval           : %.0f ms\n', 1000*config.sample_period_s);
fprintf('Worker PID timeout          : %.0f s\n', config.worker_pid_timeout_s);
fprintf('Output folder               : %s\n', output_folder);
fprintf('============================================================\n');

%% 4. RUN ALL CASES
total_runs = numel(node_sets) * numel(config.objectives) * config.repetitions;
records = repmat(empty_record(), total_runs, 1);
record_idx = 0;

for rep = 1:config.repetitions
    for s = 1:numel(node_sets)
        n = numel(node_sets{s});

        for oi = 1:numel(config.objectives)
            objective = config.objectives(oi);
            record_idx = record_idx + 1;

            run_id = sprintf('N%02d_%s_rep%02d', n, char(objective), rep);
            run_dir = fullfile(output_folder, run_id);
            mkdir(run_dir);

            result_mat = fullfile(run_dir, 'worker_result.mat');
            worker_pid_file = fullfile(run_dir, 'worker_pid.txt');
            monitor_ready_flag = fullfile(run_dir, 'monitor_ready.flag');
            model_start_flag = fullfile(run_dir, 'model_started.flag');
            optimize_start_flag = fullfile(run_dir, 'optimize_started.flag');
            optimize_finish_flag = fullfile(run_dir, 'optimize_finished.flag');

            fprintf('[%2d/%2d] N=%d | objective=%-8s | rep=%d ... ', ...
                record_idx, total_runs, n, char(objective), rep);

            worker_cmd = sprintf( ...
                ['addpath(''%s''); ' ...
                 'peak_memory_test_10_to_15_v3(''worker'',''%s'',%d,''%s'',%d,''%s'');'], ...
                escape_sq(script_dir), escape_sq(input_mat), ...
                s, char(objective), rep, escape_sq(run_dir));

            arguments = ['-batch "' worker_cmd '"'];

            psi = System.Diagnostics.ProcessStartInfo;
            psi.FileName = matlab_exe;
            psi.Arguments = arguments;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;

            starter_proc = System.Diagnostics.Process.Start(psi);
            starter_pid = double(starter_proc.Id);

            % -------------------------------------------------------------
            % PID HANDSHAKE
            % The worker writes its own true Windows PID. The parent then
            % attaches directly to that PID rather than assuming that the
            % Process.Start() object is the MATLAB process doing the solve.
            % -------------------------------------------------------------
            [worker_pid, pid_ok] = wait_for_worker_pid( ...
                worker_pid_file, config.worker_pid_timeout_s, ...
                config.sample_period_s);

            worker_proc = [];
            monitoring_attached = false;
            monitoring_source = "none";
            attach_error = "";

            if pid_ok
                try
                    worker_proc = System.Diagnostics.Process.GetProcessById( ...
                        int32(worker_pid));
                    worker_proc.Refresh();
                    monitoring_attached = true;
                    monitoring_source = "worker-reported-pid";
                catch MEattach
                    attach_error = string(MEattach.message);
                end
            else
                attach_error = "Worker PID file was not received before timeout.";
            end

            % Release the worker only after the parent has attempted to attach.
            % If attachment failed, the worker still runs so solver outputs are
            % preserved, but memory metrics are marked invalid.
            touch_file(monitor_ready_flag);

            raw_peak_model_ws = NaN;
            raw_peak_model_private = NaN;
            raw_peak_opt_ws = NaN;
            raw_peak_opt_private = NaN;
            samples_model = 0;
            samples_opt = 0;

            if monitoring_attached
                % External monitoring of the actual worker PID.
                while true
                    if process_has_exited(worker_proc)
                        break;
                    end

                    try
                        worker_proc.Refresh();
                        ws_mb = double(worker_proc.WorkingSet64) / 1024^2;
                        private_mb = double(worker_proc.PrivateMemorySize64) / 1024^2;

                        if isfile(model_start_flag) && ~isfile(optimize_finish_flag)
                            raw_peak_model_ws = finite_max(raw_peak_model_ws, ws_mb);
                            raw_peak_model_private = finite_max( ...
                                raw_peak_model_private, private_mb);
                            samples_model = samples_model + 1;
                        end

                        if isfile(optimize_start_flag) && ~isfile(optimize_finish_flag)
                            raw_peak_opt_ws = finite_max(raw_peak_opt_ws, ws_mb);
                            raw_peak_opt_private = finite_max( ...
                                raw_peak_opt_private, private_mb);
                            samples_opt = samples_opt + 1;
                        end
                    catch
                        % Process can terminate between HasExited and Refresh.
                    end

                    pause(config.sample_period_s);
                end
            else
                % No valid memory attachment. Do not use the starter process
                % for memory metrics because it may only be a launcher. Wait
                % for the worker result file instead so the solve can finish.
                wait_for_file(result_mat, config.run_completion_timeout_s, 0.10);
            end

            % Wait for process termination and collect exit codes safely.
            % worker_proc can be empty when attachment failed.
            worker_exit_code = safe_exit_code(worker_proc);
            starter_exit_code = safe_exit_code_with_timeout(starter_proc, 10);

            rec = empty_record();
            rec.NodeCount = n;
            rec.Objective = objective;
            rec.Repetition = rep;
            rec.StarterProcessId = starter_pid;
            rec.WorkerProcessId = worker_pid;
            rec.StarterWorkerPidMatch = ...
                isfinite(worker_pid) && (starter_pid == worker_pid);
            rec.MonitoringAttached = monitoring_attached;
            rec.MonitoringSource = monitoring_source;
            rec.StarterExitCode = starter_exit_code;
            rec.WorkerExitCode = worker_exit_code;
            rec.SamplingPeriod_s = config.sample_period_s;
            rec.MemorySamples_ModelPlusSolve = samples_model;
            rec.MemorySamples_Optimize = samples_opt;

            % Store raw externally sampled peaks before combining them with
            % the exact phase-start baselines measured inside the worker.
            rec.SampledPeakModelPlusSolveWorkingSet_MB = raw_peak_model_ws;
            rec.SampledPeakModelPlusSolvePrivateMemory_MB = ...
                raw_peak_model_private;
            rec.SampledPeakOptimizeWorkingSet_MB = raw_peak_opt_ws;
            rec.SampledPeakOptimizePrivateMemory_MB = raw_peak_opt_private;

            if isfile(result_mat)
                S = load(result_mat, 'worker_result');
                W = S.worker_result;

                rec.ArcCount = W.arc_count;
                rec.Status = string(W.status);
                rec.ProblemCode = W.problem;
                rec.SolverInfo = string(W.info);
                rec.BaselineBeforeModelWorkingSet_MB = W.baseline_model_ws_mb;
                rec.BaselineBeforeModelPrivateMemory_MB = ...
                    W.baseline_model_private_mb;
                rec.BaselineBeforeOptimizeWorkingSet_MB = W.baseline_opt_ws_mb;
                rec.BaselineBeforeOptimizePrivateMemory_MB = ...
                    W.baseline_opt_private_mb;
                rec.SolverTime_s = W.solver_time_s;
                rec.YALMIPTime_s = W.yalmip_time_s;
                rec.OptimizeWallTime_s = W.optimize_wall_time_s;
                rec.RelativeGap_percent = W.relative_gap_percent;
                rec.AbsoluteGap = W.absolute_gap;
                rec.ApproxBinaryVariables = W.approx_binary_variables;
                rec.ApproxContinuousVariables = W.approx_continuous_variables;
                rec.ErrorMessage = string(W.error_message);

                % Cross-check that the PID written by the worker agrees with
                % the PID recorded in worker_result.mat.
                if isfield(W,'worker_pid')
                    rec.WorkerPidConfirmedByResult = ...
                        isfinite(worker_pid) && (double(W.worker_pid) == worker_pid);
                end
            else
                rec.Status = "WorkerFailed";
                rec.ErrorMessage = "worker_result.mat was not created";
            end

            % -------------------------------------------------------------
            % FINAL PEAK METRICS
            % The baseline instant belongs to each measured interval. Hence
            % the true observed peak cannot be below that baseline. We combine
            % the worker-side baseline with the externally sampled maximum.
            % This is done only after the actual worker PID has been attached.
            % -------------------------------------------------------------
            memory_valid = monitoring_attached && ...
                rec.WorkerPidConfirmedByResult && ...
                isfinite(rec.BaselineBeforeModelWorkingSet_MB) && ...
                isfinite(rec.BaselineBeforeOptimizeWorkingSet_MB) && ...
                samples_model > 0 && samples_opt > 0;

            if memory_valid
                rec.PeakModelPlusSolveWorkingSet_MB = finite_max( ...
                    raw_peak_model_ws, rec.BaselineBeforeModelWorkingSet_MB);
                rec.PeakModelPlusSolvePrivateMemory_MB = finite_max( ...
                    raw_peak_model_private, ...
                    rec.BaselineBeforeModelPrivateMemory_MB);

                rec.PeakOptimizeWorkingSet_MB = finite_max( ...
                    raw_peak_opt_ws, rec.BaselineBeforeOptimizeWorkingSet_MB);
                rec.PeakOptimizePrivateMemory_MB = finite_max( ...
                    raw_peak_opt_private, ...
                    rec.BaselineBeforeOptimizePrivateMemory_MB);

                rec.AdditionalPeakWorkingSet_MB = ...
                    rec.PeakOptimizeWorkingSet_MB - ...
                    rec.BaselineBeforeOptimizeWorkingSet_MB;

                rec.AdditionalPeakPrivateMemory_MB = ...
                    rec.PeakOptimizePrivateMemory_MB - ...
                    rec.BaselineBeforeOptimizePrivateMemory_MB;

                rec.AdditionalModelPlusSolveWorkingSet_MB = ...
                    rec.PeakModelPlusSolveWorkingSet_MB - ...
                    rec.BaselineBeforeModelWorkingSet_MB;

                rec.AdditionalModelPlusSolvePrivateMemory_MB = ...
                    rec.PeakModelPlusSolvePrivateMemory_MB - ...
                    rec.BaselineBeforeModelPrivateMemory_MB;

                rec.MemoryMeasurementValid = true;
                rec.MemoryMeasurementNote = "OK";
            else
                rec.MemoryMeasurementValid = false;

                notes = strings(0,1);
                if ~pid_ok
                    notes(end+1) = "worker PID handshake failed"; %#ok<AGROW>
                end
                if ~monitoring_attached
                    notes(end+1) = "parent could not attach to worker PID"; %#ok<AGROW>
                end
                if ~rec.WorkerPidConfirmedByResult
                    notes(end+1) = "worker PID cross-check failed"; %#ok<AGROW>
                end
                if samples_model == 0
                    notes(end+1) = "no model-phase memory samples"; %#ok<AGROW>
                end
                if samples_opt == 0
                    notes(end+1) = "no optimize-phase memory samples"; %#ok<AGROW>
                end
                if strlength(attach_error) > 0
                    notes(end+1) = "attach error: " + attach_error; %#ok<AGROW>
                end

                if isempty(notes)
                    rec.MemoryMeasurementNote = "memory measurement invalid";
                else
                    rec.MemoryMeasurementNote = strjoin(notes, "; ");
                end
            end

            records(record_idx) = rec;

            if rec.MemoryMeasurementValid
                fprintf(['%s | worker PID %.0f | peak WS %.1f MB | ' ...
                         'increment %.1f MB\n'], ...
                    char(rec.Status), rec.WorkerProcessId, ...
                    rec.PeakOptimizeWorkingSet_MB, ...
                    rec.AdditionalPeakWorkingSet_MB);
            else
                fprintf('%s | MEMORY INVALID | %s\n', ...
                    char(rec.Status), char(rec.MemoryMeasurementNote));
            end
        end
    end
end

%% 5. TABLES
detailed_table = struct2table(records);
detailed_table = sortrows(detailed_table, ...
    {'NodeCount','Objective','Repetition'});

summary_table = build_summary(detailed_table, ...
    unique(detailed_table.NodeCount)', config.objectives);

detailed_csv = fullfile(output_folder, 'peak_memory_detailed_results.csv');
summary_csv = fullfile(output_folder, 'peak_memory_summary_results.csv');
mat_file = fullfile(output_folder, 'peak_memory_results.mat');

writetable(detailed_table, detailed_csv);
writetable(summary_table, summary_csv);
save(mat_file, 'detailed_table', 'summary_table', 'config', 'node_sets');

%% 6. CONSOLE SUMMARY
fprintf('\n============================================================\n');
fprintf('PEAK MEMORY TEST COMPLETED\n');
fprintf('============================================================\n');

disp(summary_table(:, { ...
    'NodeCount','ArcCount','Objective','OptimalRuns','ValidMemoryRuns', ...
    'MedianPeakOptimizeWorkingSet_MB', ...
    'MedianPeakOptimizePrivateMemory_MB', ...
    'MedianAdditionalPeakWorkingSet_MB', ...
    'MedianAdditionalPeakPrivateMemory_MB', ...
    'MedianPeakModelPlusSolveWorkingSet_MB', ...
    'MedianAdditionalModelPlusSolveWorkingSet_MB', ...
    'MedianSolverTime_s', ...
    'MaxRelativeGap_percent'}));

fprintf('Detailed CSV : %s\n', detailed_csv);
fprintf('Summary CSV  : %s\n', summary_csv);
fprintf('MAT file     : %s\n', mat_file);

% Named outputs are returned directly.

end

%% =========================================================================
% CHILD MATLAB WORKER
% =========================================================================
function worker_main(input_mat, scenario_index, objective, repetition, run_dir)

worker_result = initialize_worker_result();
worker_result.repetition = repetition;

try
    S = load(input_mat, 'data_fixed', 'parent_path', 'node_sets', 'config');

    % Reuse the parent's MATLAB/YALMIP search path.
    try
        path(S.parent_path);
    catch
    end

    % -------------------------------------------------------------
    % PID / READY HANDSHAKE
    % The worker reports its own true PID. It then waits until the
    % parent confirms that it has attempted to attach to that PID.
    % This guarantees that model construction does not begin before
    % external monitoring is ready.
    % -------------------------------------------------------------
    p_self = System.Diagnostics.Process.GetCurrentProcess();
    p_self.Refresh();
    worker_result.worker_pid = double(p_self.Id);

    worker_pid_file = fullfile(run_dir, 'worker_pid.txt');
    monitor_ready_flag = fullfile(run_dir, 'monitor_ready.flag');

    write_numeric_file(worker_pid_file, worker_result.worker_pid);

    ready_ok = wait_for_file( ...
        monitor_ready_flag, S.config.monitor_ready_timeout_s, 0.05);

    if ~ready_ok
        error('Parent monitor did not acknowledge the worker PID within %.1f s.', ...
            S.config.monitor_ready_timeout_s);
    end

    data_small = reduce_to_induced_subgraph( ...
        S.data_fixed, S.node_sets{scenario_index});
    data_run = prepare_objective_dataset(data_small, string(objective));

    worker_result.arc_count = nnz(data_run.A);

    % Baseline immediately before YALMIP model construction.
    [worker_result.baseline_model_ws_mb, ...
     worker_result.baseline_model_private_mb] = current_process_memory_mb();

    touch_file(fullfile(run_dir, 'model_started.flag'));

    worker_result = solve_memory_case( ...
        data_run, string(objective), S.config.verbose_solver, ...
        run_dir, worker_result);

catch ME
    worker_result.status = "WorkerError";
    worker_result.problem = NaN;
    worker_result.info = "Worker exception";
    worker_result.error_message = string(getReport(ME,'extended','hyperlinks','off'));

    % Ensure parent does not wait for an unfinished optimization phase.
    touch_file(fullfile(run_dir, 'optimize_finished.flag'));
end

save(fullfile(run_dir, 'worker_result.mat'), 'worker_result');

end

%% =========================================================================
% MILP MODEL + SOLVE
% =========================================================================
function R = solve_memory_case(data, mode, verbose_level, run_dir, R)

import yalmip.*
yalmip('clear');

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
M_soc  = 2.0;

%% Decision variables
x       = binvar(N,N,'full');
visit   = binvar(N,1);
y       = binvar(N,N,K,'full');
SOC_dep = sdpvar(N,1);
SOC_arr = sdpvar(N,1);
DeltaE  = sdpvar(N,1);
t_ch    = sdpvar(N,1);
t_arr   = sdpvar(N,1);
z       = binvar(N,K,'full');
Eik     = sdpvar(N,K,'full');
a       = binvar(N,K,'full');
u       = sdpvar(N,1);

constraints = [];

%% A. Network flow
constraints = [constraints, x(eye(N)==1) == 0];
constraints = [constraints, x(A==0) == 0];
constraints = [constraints, sum(x(origin,:)) == 1];
constraints = [constraints, sum(x(:,origin)) == 0];
constraints = [constraints, sum(x(:,dest)) == 1];
constraints = [constraints, sum(x(dest,:)) == 0];

for i = 1:N
    if i ~= origin && i ~= dest
        constraints = [constraints, sum(x(i,:)) == sum(x(:,i))]; %#ok<AGROW>
        constraints = [constraints, sum(x(i,:)) == visit(i)]; %#ok<AGROW>
    end
end
constraints = [constraints, visit(origin)==1, visit(dest)==1];

%% B. MTZ subtour elimination
constraints = [constraints, u >= 0, u <= N];
constraints = [constraints, u(origin) == 1];

for i = 1:N
    if i ~= origin && i ~= dest
        constraints = [constraints, u(i) >= 2*visit(i)]; %#ok<AGROW>
        constraints = [constraints, u(i) <= N*visit(i)]; %#ok<AGROW>
    end
end

M_u = N;
for i = 1:N
    for j = 1:N
        if i ~= j && A(i,j) == 1
            if j == origin || i == dest
                continue;
            end
            constraints = [constraints, ...
                u(j) >= u(i) + 1 - M_u*(1-x(i,j))]; %#ok<AGROW>
        end
    end
end

%% C. x-y linking
for i = 1:N
    for j = 1:N
        if A(i,j) == 1
            constraints = [constraints, ...
                sum(y(i,j,:)) == x(i,j)]; %#ok<AGROW>
        else
            constraints = [constraints, y(i,j,:) == 0]; %#ok<AGROW>
        end
    end
end

%% D. Arrival-slot synchronization
for j = 1:N
    if j ~= origin
        for k = 1:K
            constraints = [constraints, ...
                a(j,k) == sum(y(:,j,k))]; %#ok<AGROW>
        end
        constraints = [constraints, sum(a(j,:)) == visit(j)]; %#ok<AGROW>

        for k = 1:K
            constraints = [constraints, ...
                t_arr(j) >= (k-1)*dt - M_time*(1-a(j,k))]; %#ok<AGROW>
            constraints = [constraints, ...
                t_arr(j) <= k*dt + M_time*(1-a(j,k))]; %#ok<AGROW>
        end
    end
end

%% E. Battery dynamics
for i = 1:N
    for j = 1:N
        if A(i,j) == 1
            cons_dynamic = sum( ...
                squeeze(y(i,j,:)) .* ...
                squeeze(data.E_dynamic(i,j,:))) / Ebat;

            constraints = [constraints, ...
                SOC_arr(j) <= SOC_dep(i) - cons_dynamic + ...
                M_soc*(1-x(i,j))]; %#ok<AGROW>
            constraints = [constraints, ...
                SOC_arr(j) >= SOC_dep(i) - cons_dynamic - ...
                M_soc*(1-x(i,j))]; %#ok<AGROW>
        end
    end
end

constraints = [constraints, SOC_dep == SOC_arr + DeltaE/Ebat];
constraints = [constraints, SOCmin <= SOC_arr <= SOCmax];
constraints = [constraints, SOCmin <= SOC_dep <= SOCmax];
constraints = [constraints, SOC_dep(origin) == SOCinit];
constraints = [constraints, SOC_arr(dest) >= SOCdest];
constraints = [constraints, DeltaE(origin) == 0];
constraints = [constraints, DeltaE(dest) == 0];

for i = 1:N
    P = P_charge_vec(i);
    if P > 0
        constraints = [constraints, t_ch(i) == DeltaE(i)/P]; %#ok<AGROW>
        constraints = [constraints, ...
            DeltaE(i) <= Ebat*visit(i)]; %#ok<AGROW>
    else
        constraints = [constraints, DeltaE(i) == 0]; %#ok<AGROW>
        constraints = [constraints, t_ch(i) == 0]; %#ok<AGROW>
    end
end

%% F. Time continuity
constraints = [constraints, t_arr(origin) == 0];

for i = 1:N
    for j = 1:N
        if A(i,j) == 1
            constraints = [constraints, ...
                t_arr(j) >= t_arr(i) + t_ch(i) + tij(i,j) - ...
                M_time*(1-x(i,j))]; %#ok<AGROW>
            constraints = [constraints, ...
                t_arr(j) <= t_arr(i) + t_ch(i) + tij(i,j) + ...
                M_time*(1-x(i,j))]; %#ok<AGROW>
        end
    end
end
constraints = [constraints, t_arr <= K*dt];

%% G. Charging-slot allocation
for i = 1:N
    if P_charge_vec(i) > 0
        constraints = [constraints, ...
            sum(z(i,:)) <= K*visit(i)]; %#ok<AGROW>
        constraints = [constraints, ...
            sum(Eik(i,:)) == DeltaE(i)]; %#ok<AGROW>

        max_energy_per_slot = P_charge_vec(i)*dt;
        constraints = [constraints, ...
            0 <= Eik(i,:) <= max_energy_per_slot*z(i,:)]; %#ok<AGROW>

        for k = 1:K
            slot_start = (k-1)*dt;
            constraints = [constraints, ...
                slot_start >= t_arr(i) - M_time*(1-z(i,k))]; %#ok<AGROW>
            constraints = [constraints, ...
                slot_start <= t_arr(i) + t_ch(i) + ...
                M_time*(1-z(i,k))]; %#ok<AGROW>
        end
    else
        constraints = [constraints, Eik(i,:) == 0]; %#ok<AGROW>
        constraints = [constraints, z(i,:) == 0]; %#ok<AGROW>
    end
end

%% Objective
cost_term   = sum(sum(Eik .* LMP));
time_term   = t_arr(dest);
energy_term = sum(sum(sum(y .* data.E_dynamic)));
dist_term   = sum(sum(x .* data.dist));

switch mode
    case "cost"
        objective = cost_term;
    case "time"
        objective = time_term;
    case "energy"
        objective = energy_term;
    case "distance"
        objective = dist_term + 0.001*time_term;
    otherwise
        error('Unknown optimization mode: %s', mode);
end

R.approx_binary_variables = N^2 + N + N^2*K + 2*N*K;
R.approx_continuous_variables = 6*N + N*K;

opts = sdpsettings( ...
    'solver','intlinprog', ...
    'verbose',verbose_level, ...
    'cachesolvers',1, ...
    'savesolveroutput',1);

%% Baseline immediately before optimize()
[R.baseline_opt_ws_mb, ...
 R.baseline_opt_private_mb] = current_process_memory_mb();

touch_file(fullfile(run_dir, 'optimize_started.flag'));

solve_timer = tic;
sol = optimize(constraints, objective, opts);
R.optimize_wall_time_s = toc(solve_timer);

touch_file(fullfile(run_dir, 'optimize_finished.flag'));

R.problem = sol.problem;
R.info = string(sol.info);
R.yalmip_time_s = safe_field(sol,'yalmiptime');
R.solver_time_s = safe_field(sol,'solvertime');

R.relative_gap_percent = NaN;
R.absolute_gap = NaN;

if isfield(sol,'solveroutput') && ...
        isfield(sol.solveroutput,'output') && ...
        isstruct(sol.solveroutput.output)

    out = sol.solveroutput.output;

    if isfield(out,'relativegap')
        R.relative_gap_percent = 100*out.relativegap;
    end

    if isfield(out,'absolutegap')
        R.absolute_gap = out.absolutegap;
    end
end

if sol.problem == 0
    R.status = "Optimal";
else
    R.status = "Failure";
end

end

%% =========================================================================
% DATA REDUCTION
% =========================================================================
function data_small = reduce_to_induced_subgraph(data_full, kept_nodes)

kept_nodes = kept_nodes(:)';

data_small = data_full;
data_small.original_node_ids = kept_nodes;
data_small.N = numel(kept_nodes);
data_small.origin = find(kept_nodes == data_full.origin,1);
data_small.dest   = find(kept_nodes == data_full.dest,1);

matrix_fields = {'A','tij','E0','dist','E'};
for f = 1:numel(matrix_fields)
    name = matrix_fields{f};
    if isfield(data_full,name)
        V = data_full.(name);
        data_small.(name) = V(kept_nodes,kept_nodes);
    end
end

tensor_fields = {'E_dynamic','Tseg'};
for f = 1:numel(tensor_fields)
    name = tensor_fields{f};
    if isfield(data_full,name)
        V = data_full.(name);
        data_small.(name) = V(kept_nodes,kept_nodes,:);
    end
end

if isfield(data_full,'LMP')
    data_small.LMP = data_full.LMP(kept_nodes,:);
end

if isfield(data_full,'coords')
    data_small.coords = data_full.coords(kept_nodes,:);
end

if isfield(data_full,'P_charge_kW')
    data_small.P_charge_kW = data_full.P_charge_kW(kept_nodes,:);
end

data_small.A(1:data_small.N+1:end) = 0;

end

function data_run = prepare_objective_dataset(data_in, mode)
data_run = data_in;

if mode == "distance"
    data_run.E_dynamic = repmat(data_run.E0,1,1,data_run.Tslots);
    data_run.E = data_run.E0;
end
end

%% =========================================================================
% SUMMARY
% =========================================================================
function summary = build_summary(T, node_counts, objectives)

rows = [];

for n = node_counts
    for obj = objectives
        G = T(T.NodeCount == n & T.Objective == obj,:);

        if isempty(G)
            continue;
        end

        row.NodeCount = n;
        row.ArcCount = first_finite(G.ArcCount);
        row.Objective = obj;
        row.TotalRuns = height(G);
        row.OptimalRuns = sum(G.Status == "Optimal");
        row.ValidMemoryRuns = sum(G.MemoryMeasurementValid);

        GM = G(G.MemoryMeasurementValid,:);

        row.MeanPeakOptimizeWorkingSet_MB = ...
            finite_mean(GM.PeakOptimizeWorkingSet_MB);
        row.MedianPeakOptimizeWorkingSet_MB = ...
            finite_median(GM.PeakOptimizeWorkingSet_MB);
        row.StdPeakOptimizeWorkingSet_MB = ...
            finite_std(GM.PeakOptimizeWorkingSet_MB);

        row.MeanPeakOptimizePrivateMemory_MB = ...
            finite_mean(GM.PeakOptimizePrivateMemory_MB);
        row.MedianPeakOptimizePrivateMemory_MB = ...
            finite_median(GM.PeakOptimizePrivateMemory_MB);
        row.StdPeakOptimizePrivateMemory_MB = ...
            finite_std(GM.PeakOptimizePrivateMemory_MB);

        row.MedianAdditionalPeakWorkingSet_MB = ...
            finite_median(GM.AdditionalPeakWorkingSet_MB);
        row.MedianAdditionalPeakPrivateMemory_MB = ...
            finite_median(GM.AdditionalPeakPrivateMemory_MB);

        row.MedianPeakModelPlusSolveWorkingSet_MB = ...
            finite_median(GM.PeakModelPlusSolveWorkingSet_MB);
        row.MedianPeakModelPlusSolvePrivateMemory_MB = ...
            finite_median(GM.PeakModelPlusSolvePrivateMemory_MB);

        row.MedianAdditionalModelPlusSolveWorkingSet_MB = ...
            finite_median(GM.AdditionalModelPlusSolveWorkingSet_MB);
        row.MedianAdditionalModelPlusSolvePrivateMemory_MB = ...
            finite_median(GM.AdditionalModelPlusSolvePrivateMemory_MB);

        row.MedianSolverTime_s = finite_median(G.SolverTime_s);
        row.MaxRelativeGap_percent = finite_max_vector(G.RelativeGap_percent);

        if isempty(rows)
            rows = row;
        else
            rows(end+1) = row; %#ok<AGROW>
        end
    end
end

summary = struct2table(rows);
summary = sortrows(summary, {'NodeCount','Objective'});

end

%% =========================================================================
% MEMORY + UTILITY HELPERS
% =========================================================================
function [ws_mb, private_mb] = current_process_memory_mb()
p = System.Diagnostics.Process.GetCurrentProcess();
p.Refresh();
ws_mb = double(p.WorkingSet64) / 1024^2;
private_mb = double(p.PrivateMemorySize64) / 1024^2;
end

function touch_file(filename)
fid = fopen(filename,'w');
if fid >= 0
    fprintf(fid,'%s\n',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss.SSS')));
    fclose(fid);
end
end

function [pid, ok] = wait_for_worker_pid(filename, timeout_s, poll_s)
pid = NaN;
ok = false;
t0 = tic;

while toc(t0) < timeout_s
    if isfile(filename)
        try
            txt = strtrim(fileread(filename));
            value = str2double(txt);
            if isfinite(value) && value > 0
                pid = value;
                ok = true;
                return;
            end
        catch
        end
    end
    pause(poll_s);
end
end

function ok = wait_for_file(filename, timeout_s, poll_s)
ok = false;
t0 = tic;
while toc(t0) < timeout_s
    if isfile(filename)
        ok = true;
        return;
    end
    pause(poll_s);
end
end

function write_numeric_file(filename, value)
fid = fopen(filename,'w');
if fid < 0
    error('Could not create file: %s', filename);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%.0f\n',double(value));
end

function tf = process_has_exited(proc)
if isempty(proc)
    tf = true;
    return;
end
try
    tf = logical(proc.HasExited);
catch
    tf = true;
end
end

function code = safe_exit_code(proc)
code = NaN;
if isempty(proc)
    return;
end

try
    proc.WaitForExit();
catch
end

try
    code = double(proc.ExitCode);
catch
end
end

function code = safe_exit_code_with_timeout(proc, timeout_s)
code = NaN;
if isempty(proc)
    return;
end

try
    exited = proc.WaitForExit(int32(round(timeout_s*1000)));
    if ~exited
        return;
    end
catch
    return;
end

try
    code = double(proc.ExitCode);
catch
end
end

function y = finite_max(a,b)
if ~isfinite(a)
    y = b;
elseif ~isfinite(b)
    y = a;
else
    y = max(a,b);
end
end

function y = finite_mean(x)
x = x(isfinite(x));
if isempty(x), y = NaN; else, y = mean(x); end
end

function y = finite_median(x)
x = x(isfinite(x));
if isempty(x), y = NaN; else, y = median(x); end
end

function y = finite_std(x)
x = x(isfinite(x));
if isempty(x)
    y = NaN;
elseif numel(x) == 1
    y = 0;
else
    y = std(x,0);
end
end

function y = finite_max_vector(x)
x = x(isfinite(x));
if isempty(x), y = NaN; else, y = max(x); end
end

function value = first_finite(x)
x = x(isfinite(x));
if isempty(x), value = NaN; else, value = x(1); end
end

function value = safe_field(S,name)
if isfield(S,name)
    value = S.(name);
else
    value = NaN;
end
end

function out = escape_sq(in)
% Escape single-quote characters for the MATLAB -batch command.
out = char(in);
q = char(39);
out = strrep(out, q, [q q]);
end

function validate_full_dataset(data)
required = {'N','origin','dest','A','tij','E0','dist','E_dynamic', ...
    'Ebat','SOC_min','SOC_max','SOC_init','min_SOC_at_dest', ...
    'P_charge_kW','LMP','Tslots','dt_h'};

for i = 1:numel(required)
    if ~isfield(data,required{i})
        error('Required data field missing: %s',required{i});
    end
end

if data.N ~= 15
    error('This benchmark expects the full 15-node base dataset.');
end
end

function R = initialize_worker_result()
R = struct( ...
    'repetition',NaN, ...
    'worker_pid',NaN, ...
    'arc_count',NaN, ...
    'status',"", ...
    'problem',NaN, ...
    'info',"", ...
    'baseline_model_ws_mb',NaN, ...
    'baseline_model_private_mb',NaN, ...
    'baseline_opt_ws_mb',NaN, ...
    'baseline_opt_private_mb',NaN, ...
    'solver_time_s',NaN, ...
    'yalmip_time_s',NaN, ...
    'optimize_wall_time_s',NaN, ...
    'relative_gap_percent',NaN, ...
    'absolute_gap',NaN, ...
    'approx_binary_variables',NaN, ...
    'approx_continuous_variables',NaN, ...
    'error_message',"");
end

function R = empty_record()
R = struct( ...
    'NodeCount',NaN, ...
    'ArcCount',NaN, ...
    'Objective',"", ...
    'Repetition',NaN, ...
    'Status',"", ...
    'ProblemCode',NaN, ...
    'SolverInfo',"", ...
    'StarterProcessId',NaN, ...
    'WorkerProcessId',NaN, ...
    'StarterWorkerPidMatch',false, ...
    'WorkerPidConfirmedByResult',false, ...
    'MonitoringAttached',false, ...
    'MonitoringSource',"", ...
    'StarterExitCode',NaN, ...
    'WorkerExitCode',NaN, ...
    'SamplingPeriod_s',NaN, ...
    'MemorySamples_ModelPlusSolve',NaN, ...
    'MemorySamples_Optimize',NaN, ...
    'BaselineBeforeModelWorkingSet_MB',NaN, ...
    'BaselineBeforeModelPrivateMemory_MB',NaN, ...
    'BaselineBeforeOptimizeWorkingSet_MB',NaN, ...
    'BaselineBeforeOptimizePrivateMemory_MB',NaN, ...
    'SampledPeakModelPlusSolveWorkingSet_MB',NaN, ...
    'SampledPeakModelPlusSolvePrivateMemory_MB',NaN, ...
    'SampledPeakOptimizeWorkingSet_MB',NaN, ...
    'SampledPeakOptimizePrivateMemory_MB',NaN, ...
    'PeakModelPlusSolveWorkingSet_MB',NaN, ...
    'PeakModelPlusSolvePrivateMemory_MB',NaN, ...
    'PeakOptimizeWorkingSet_MB',NaN, ...
    'PeakOptimizePrivateMemory_MB',NaN, ...
    'AdditionalPeakWorkingSet_MB',NaN, ...
    'AdditionalPeakPrivateMemory_MB',NaN, ...
    'AdditionalModelPlusSolveWorkingSet_MB',NaN, ...
    'AdditionalModelPlusSolvePrivateMemory_MB',NaN, ...
    'MemoryMeasurementValid',false, ...
    'MemoryMeasurementNote',"", ...
    'SolverTime_s',NaN, ...
    'YALMIPTime_s',NaN, ...
    'OptimizeWallTime_s',NaN, ...
    'RelativeGap_percent',NaN, ...
    'AbsoluteGap',NaN, ...
    'ApproxBinaryVariables',NaN, ...
    'ApproxContinuousVariables',NaN, ...
    'ErrorMessage',"");
end
