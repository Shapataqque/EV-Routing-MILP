%% capacity_results_from_csv.m
% =========================================================================
% Post-processes node_capacity_detailed_results CSV without re-running MILP.
%
% Outputs:
%   1) capacity_summary_for_paper.csv
%   2) Fig_1_solver_time_scaling.png/.pdf
%   3) Fig_2_model_size_growth.png/.pdf
%   4) Fig_3_max_optimality_gap.png/.pdf
%   5) Fig_4_runtime_variability.png/.pdf
%   6) capacity_key_metrics.txt
%
% The script uses only the detailed CSV produced by node_capacity_test_10_to_15.
% No optimization is performed.
% =========================================================================

clear; clc; close all;

%% 1. INPUT CSV
csv_file = '/MATLAB Drive/EV Routing Thesis Study/node_capacity_results_20260811_111341/node_capacity_detailed_results.csv';

if ~isfile(csv_file)
    candidates = dir('node_capacity_detailed_results*.csv');
    if isempty(candidates)
        error(['No node_capacity_detailed_results*.csv file was found in ' ...
               'the current folder. Put the CSV next to this script or ' ...
               'edit csv_file at the top of the script.']);
    end

    [~, newest_idx] = max([candidates.datenum]);
    csv_file = candidates(newest_idx).name;
    fprintf('Requested CSV not found. Using newest matching file:\n  %s\n', csv_file);
end

T = readtable(csv_file, 'VariableNamingRule', 'preserve');

%% 2. VALIDATE REQUIRED COLUMNS
required = { ...
    'NodeCount','ArcCount','Objective','Repetition','Status', ...
    'YALMIPTime_s','SolverTime_s','RelativeGap_percent','AbsoluteGap', ...
    'ModelBuildTime_s','OptimizeWallTime_s','EndToEndTime_s', ...
    'ApproxBinaryVariables','ApproxContinuousVariables'};

for i = 1:numel(required)
    if ~ismember(required{i}, T.Properties.VariableNames)
        error('Required CSV column is missing: %s', required{i});
    end
end

% Normalize string-like columns
T.Objective = string(T.Objective);
T.Status    = string(T.Status);

objective_order = ["distance","cost","time","energy"];
node_counts = unique(T.NodeCount)';
node_counts = sort(node_counts);

%% 3. INTEGRITY CHECKS
fprintf('\n============================================================\n');
fprintf('CSV INTEGRITY CHECK\n');
fprintf('============================================================\n');
fprintf('File                       : %s\n', csv_file);
fprintf('Total measured runs        : %d\n', height(T));
fprintf('Optimal runs               : %d\n', sum(T.Status == "Optimal"));
fprintf('Non-optimal runs           : %d\n', sum(T.Status ~= "Optimal"));
fprintf('Finite relative-gap values : %d/%d\n', ...
    sum(isfinite(T.RelativeGap_percent)), height(T));

if any(T.Status ~= "Optimal")
    warning('The CSV contains non-optimal runs. Review them before publication.');
end

%% 4. BUILD SUMMARY TABLE
row_count = numel(node_counts) * numel(objective_order);

NodeCount = nan(row_count,1);
ArcCount = nan(row_count,1);
Objective = strings(row_count,1);
Runs = nan(row_count,1);
OptimalRuns = nan(row_count,1);

MeanSolverTime_s = nan(row_count,1);
MedianSolverTime_s = nan(row_count,1);
StdSolverTime_s = nan(row_count,1);
CVSolverTime_percent = nan(row_count,1);

MeanYALMIPTime_s = nan(row_count,1);
MedianYALMIPTime_s = nan(row_count,1);

MeanModelBuildTime_s = nan(row_count,1);
MedianModelBuildTime_s = nan(row_count,1);

MeanOptimizeWallTime_s = nan(row_count,1);
MedianOptimizeWallTime_s = nan(row_count,1);

MeanEndToEndTime_s = nan(row_count,1);
MedianEndToEndTime_s = nan(row_count,1);

MedianRelativeGap_percent = nan(row_count,1);
MaxRelativeGap_percent = nan(row_count,1);
MaxAbsoluteGap = nan(row_count,1);

ApproxBinaryVariables = nan(row_count,1);
ApproxContinuousVariables = nan(row_count,1);

r = 0;

for n = node_counts
    for obj = objective_order
        mask = T.NodeCount == n & lower(T.Objective) == obj;
        G = T(mask,:);

        if isempty(G)
            continue;
        end

        r = r + 1;

        NodeCount(r) = n;
        ArcCount(r) = G.ArcCount(1);
        Objective(r) = obj;
        Runs(r) = height(G);
        OptimalRuns(r) = sum(G.Status == "Optimal");

        MeanSolverTime_s(r) = mean(G.SolverTime_s, 'omitnan');
        MedianSolverTime_s(r) = median(G.SolverTime_s, 'omitnan');
        StdSolverTime_s(r) = std(G.SolverTime_s, 0, 'omitnan');

        if MeanSolverTime_s(r) > 0
            CVSolverTime_percent(r) = ...
                100 * StdSolverTime_s(r) / MeanSolverTime_s(r);
        end

        MeanYALMIPTime_s(r) = mean(G.YALMIPTime_s, 'omitnan');
        MedianYALMIPTime_s(r) = median(G.YALMIPTime_s, 'omitnan');

        MeanModelBuildTime_s(r) = mean(G.ModelBuildTime_s, 'omitnan');
        MedianModelBuildTime_s(r) = median(G.ModelBuildTime_s, 'omitnan');

        MeanOptimizeWallTime_s(r) = mean(G.OptimizeWallTime_s, 'omitnan');
        MedianOptimizeWallTime_s(r) = median(G.OptimizeWallTime_s, 'omitnan');

        MeanEndToEndTime_s(r) = mean(G.EndToEndTime_s, 'omitnan');
        MedianEndToEndTime_s(r) = median(G.EndToEndTime_s, 'omitnan');

        MedianRelativeGap_percent(r) = ...
            median(G.RelativeGap_percent, 'omitnan');
        MaxRelativeGap_percent(r) = ...
            max(G.RelativeGap_percent, [], 'omitnan');
        MaxAbsoluteGap(r) = max(G.AbsoluteGap, [], 'omitnan');

        ApproxBinaryVariables(r) = G.ApproxBinaryVariables(1);
        ApproxContinuousVariables(r) = G.ApproxContinuousVariables(1);
    end
end

% Remove unfilled preallocated rows, if any
valid = ~isnan(NodeCount);
summary = table( ...
    NodeCount(valid), ArcCount(valid), Objective(valid), ...
    Runs(valid), OptimalRuns(valid), ...
    MeanSolverTime_s(valid), MedianSolverTime_s(valid), ...
    StdSolverTime_s(valid), CVSolverTime_percent(valid), ...
    MeanYALMIPTime_s(valid), MedianYALMIPTime_s(valid), ...
    MeanModelBuildTime_s(valid), MedianModelBuildTime_s(valid), ...
    MeanOptimizeWallTime_s(valid), MedianOptimizeWallTime_s(valid), ...
    MeanEndToEndTime_s(valid), MedianEndToEndTime_s(valid), ...
    MedianRelativeGap_percent(valid), MaxRelativeGap_percent(valid), ...
    MaxAbsoluteGap(valid), ApproxBinaryVariables(valid), ...
    ApproxContinuousVariables(valid), ...
    'VariableNames', { ...
    'NodeCount','ArcCount','Objective','Runs','OptimalRuns', ...
    'MeanSolverTime_s','MedianSolverTime_s','StdSolverTime_s', ...
    'CVSolverTime_percent', ...
    'MeanYALMIPTime_s','MedianYALMIPTime_s', ...
    'MeanModelBuildTime_s','MedianModelBuildTime_s', ...
    'MeanOptimizeWallTime_s','MedianOptimizeWallTime_s', ...
    'MeanEndToEndTime_s','MedianEndToEndTime_s', ...
    'MedianRelativeGap_percent','MaxRelativeGap_percent', ...
    'MaxAbsoluteGap','ApproxBinaryVariables', ...
    'ApproxContinuousVariables'});

summary = sortrows(summary, {'NodeCount','Objective'});
writetable(summary, 'capacity_summary_for_paper.csv');

%% 5. DERIVE KEY METRICS
n_min = min(node_counts);
n_max = max(node_counts);

bin_min = T.ApproxBinaryVariables(find(T.NodeCount == n_min,1));
bin_max = T.ApproxBinaryVariables(find(T.NodeCount == n_max,1));

cont_min = T.ApproxContinuousVariables(find(T.NodeCount == n_min,1));
cont_max = T.ApproxContinuousVariables(find(T.NodeCount == n_max,1));

arc_min = T.ArcCount(find(T.NodeCount == n_min,1));
arc_max = T.ArcCount(find(T.NodeCount == n_max,1));

max_gap_all = max(T.RelativeGap_percent, [], 'omitnan');
max_abs_gap_all = max(T.AbsoluteGap, [], 'omitnan');

fprintf('\n============================================================\n');
fprintf('KEY RESULTS\n');
fprintf('============================================================\n');
fprintf('Network range       : %d -> %d nodes\n', n_min, n_max);
fprintf('Arc count           : %d -> %d\n', arc_min, arc_max);
fprintf('Binary variables    : %d -> %d (%.2fx)\n', ...
    bin_min, bin_max, bin_max/bin_min);
fprintf('Continuous variables: %d -> %d (%.2fx)\n', ...
    cont_min, cont_max, cont_max/cont_min);
fprintf('Maximum rel. gap    : %.12g %%\n', max_gap_all);
fprintf('Maximum abs. gap    : %.12g\n', max_abs_gap_all);

for obj = objective_order
    s0 = summary(summary.NodeCount == n_min & summary.Objective == obj,:);
    s1 = summary(summary.NodeCount == n_max & summary.Objective == obj,:);

    if ~isempty(s0) && ~isempty(s1)
        ratio = s1.MedianSolverTime_s / s0.MedianSolverTime_s;
        fprintf('%-8s median solver time: %.4f -> %.4f s (%.2fx)\n', ...
            char(obj), s0.MedianSolverTime_s, ...
            s1.MedianSolverTime_s, ratio);
    end
end

%% 6. OUTPUT DIRECTORY
out_dir = 'capacity_figures_from_csv';
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

%% 7. FIGURE STYLE
font_name = 'Times New Roman';
font_size = 9;
line_width = 1.4;
marker_size = 6;

%% 8. FIGURE 1 — MEDIAN SOLVER TIME SCALING
try
    fig = figure('Visible','off', 'Color','w', ...
        'Units','inches', 'Position',[1 1 7.16 4.4]);

    hold on; grid on; box on;

    markers = {'o','s','^','d'};

    for oi = 1:numel(objective_order)
        obj = objective_order(oi);
        S = summary(summary.Objective == obj,:);
        S = sortrows(S,'NodeCount');

        plot(S.NodeCount, S.MedianSolverTime_s, ...
            ['-' markers{oi}], ...
            'LineWidth', line_width, ...
            'MarkerSize', marker_size, ...
            'DisplayName', title_case_objective(obj));
    end

    xlabel('Number of nodes');
    ylabel('Median solver time (s)');
    title('Computational scaling of the MILP formulation');
    xticks(node_counts);
    legend('Location','northwest');

    set(gca, 'FontName',font_name, 'FontSize',font_size, ...
        'LineWidth',0.8);

    export_pair(fig, out_dir, 'Fig_1_solver_time_scaling');
    close(fig);
catch ME
    warning('Figure 1 could not be created: %s', ME.message);
end

%% 9. FIGURE 2 — MODEL SIZE GROWTH
try
    node_summary = unique(T(:,{ ...
        'NodeCount','ArcCount','ApproxBinaryVariables', ...
        'ApproxContinuousVariables'}), 'rows');
    node_summary = sortrows(node_summary,'NodeCount');

    fig = figure('Visible','off', 'Color','w', ...
        'Units','inches', 'Position',[1 1 7.16 4.4]);

    tiledlayout(1,2,'Padding','compact','TileSpacing','compact');

    nexttile;
    plot(node_summary.NodeCount, node_summary.ApproxBinaryVariables, ...
        '-o','LineWidth',line_width,'MarkerSize',marker_size);
    grid on; box on;
    xlabel('Number of nodes');
    ylabel('Binary variables');
    title('(a) Binary-variable growth');
    xticks(node_counts);
    set(gca,'FontName',font_name,'FontSize',font_size,'LineWidth',0.8);

    nexttile;
    yyaxis left
    plot(node_summary.NodeCount, node_summary.ApproxContinuousVariables, ...
        '-s','LineWidth',line_width,'MarkerSize',marker_size);
    ylabel('Continuous variables');

    yyaxis right
    plot(node_summary.NodeCount, node_summary.ArcCount, ...
        '--d','LineWidth',line_width,'MarkerSize',marker_size);
    ylabel('Directed arcs');

    grid on; box on;
    xlabel('Number of nodes');
    title('(b) Continuous variables and arcs');
    xticks(node_counts);
    set(gca,'FontName',font_name,'FontSize',font_size,'LineWidth',0.8);

    export_pair(fig, out_dir, 'Fig_2_model_size_growth');
    close(fig);
catch ME
    warning('Figure 2 could not be created: %s', ME.message);
end

%% 10. FIGURE 3 — MAXIMUM RELATIVE OPTIMALITY GAP
try
    max_gap_by_node = nan(numel(node_counts),1);

    for i = 1:numel(node_counts)
        vals = T.RelativeGap_percent(T.NodeCount == node_counts(i));
        max_gap_by_node(i) = max(vals, [], 'omitnan');
    end

    fig = figure('Visible','off', 'Color','w', ...
        'Units','inches', 'Position',[1 1 3.5 3.0]);

    bar(node_counts, max_gap_by_node);
    grid on; box on;
    xlabel('Number of nodes');
    ylabel('Maximum relative gap (%)');
    title('Optimality-gap verification');
    xticks(node_counts);

    ax = gca;
    ax.YAxis.Exponent = 0;
    ytickformat('%.1e');

    set(gca,'FontName',font_name,'FontSize',font_size,'LineWidth',0.8);

    export_pair(fig, out_dir, 'Fig_3_max_optimality_gap');
    close(fig);
catch ME
    warning('Figure 3 could not be created: %s', ME.message);
end

%% 11. FIGURE 4 — RUNTIME VARIABILITY (COEFFICIENT OF VARIATION)
try
    fig = figure('Visible','off', 'Color','w', ...
        'Units','inches', 'Position',[1 1 7.16 4.4]);

    hold on; grid on; box on;

    markers = {'o','s','^','d'};

    for oi = 1:numel(objective_order)
        obj = objective_order(oi);
        S = summary(summary.Objective == obj,:);
        S = sortrows(S,'NodeCount');

        plot(S.NodeCount, S.CVSolverTime_percent, ...
            ['-' markers{oi}], ...
            'LineWidth',line_width, ...
            'MarkerSize',marker_size, ...
            'DisplayName',title_case_objective(obj));
    end

    xlabel('Number of nodes');
    ylabel('Solver-time coefficient of variation (%)');
    title('Run-to-run computational variability');
    xticks(node_counts);
    legend('Location','best');

    set(gca,'FontName',font_name,'FontSize',font_size,'LineWidth',0.8);

    export_pair(fig, out_dir, 'Fig_4_runtime_variability');
    close(fig);
catch ME
    warning('Figure 4 could not be created: %s', ME.message);
end

%% 12. WRITE MACHINE-READABLE / MANUSCRIPT-READY KEY METRICS
txt_file = fullfile(out_dir, 'capacity_key_metrics.txt');
fid = fopen(txt_file,'w');

fprintf(fid, 'Capacity-test key metrics\n');
fprintf(fid, '=========================\n');
fprintf(fid, 'Measured runs: %d\n', height(T));
fprintf(fid, 'Optimal runs: %d\n', sum(T.Status == "Optimal"));
fprintf(fid, 'Success rate: %.2f %%\n', ...
    100*sum(T.Status == "Optimal")/height(T));
fprintf(fid, 'Node range: %d-%d\n', n_min, n_max);
fprintf(fid, 'Arc range: %d-%d\n', arc_min, arc_max);
fprintf(fid, 'Binary variables: %d -> %d (%.4fx)\n', ...
    bin_min, bin_max, bin_max/bin_min);
fprintf(fid, 'Continuous variables: %d -> %d (%.4fx)\n', ...
    cont_min, cont_max, cont_max/cont_min);
fprintf(fid, 'Maximum relative gap: %.12g %%\n', max_gap_all);
fprintf(fid, 'Maximum absolute gap: %.12g\n', max_abs_gap_all);

for obj = objective_order
    s0 = summary(summary.NodeCount == n_min & summary.Objective == obj,:);
    s1 = summary(summary.NodeCount == n_max & summary.Objective == obj,:);

    if ~isempty(s0) && ~isempty(s1)
        ratio = s1.MedianSolverTime_s / s0.MedianSolverTime_s;
        fprintf(fid, '%s median solver time: %.6f -> %.6f s (%.4fx)\n', ...
            char(obj), s0.MedianSolverTime_s, ...
            s1.MedianSolverTime_s, ratio);
    end
end

fprintf(fid, '\n15-node results\n');
fprintf(fid, '---------------\n');

for obj = objective_order
    S = summary(summary.NodeCount == n_max & summary.Objective == obj,:);
    if ~isempty(S)
        fprintf(fid, ...
            ['%s: median solver %.6f s; std %.6f s; CV %.4f %%; ' ...
             'median relative gap %.12g %%\n'], ...
            char(obj), S.MedianSolverTime_s, ...
            S.StdSolverTime_s, S.CVSolverTime_percent, ...
            S.MedianRelativeGap_percent);
    end
end

fclose(fid);

fprintf('\n============================================================\n');
fprintf('POST-PROCESSING COMPLETED\n');
fprintf('============================================================\n');
fprintf('Summary CSV : capacity_summary_for_paper.csv\n');
fprintf('Figures     : %s\n', out_dir);
fprintf('Key metrics : %s\n', txt_file);

%% =========================================================================
% LOCAL FUNCTIONS
% =========================================================================
function label = title_case_objective(obj)
    obj = lower(string(obj));
    switch obj
        case "distance"
            label = 'Distance';
        case "cost"
            label = 'Cost';
        case "time"
            label = 'Time';
        case "energy"
            label = 'Energy';
        otherwise
            label = char(obj);
    end
end

function export_pair(fig, out_dir, base_name)
    png_file = fullfile(out_dir, [base_name '.png']);
    pdf_file = fullfile(out_dir, [base_name '.pdf']);

    exportgraphics(fig, png_file, 'Resolution', 300);
    exportgraphics(fig, pdf_file, 'ContentType', 'vector');
end
