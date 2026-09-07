function output_files = plot_price_awareness_comparison_ieee(results_mat_file)
%% PLOT_PRICE_AWARENESS_COMPARISON_IEEE
% IEEE single-column publication version.
%
% Creates:
%   1) Price-awareness realized-cost comparison
%   2) Charging profile under dynamic electricity prices
%
% Output format:
%   - Vector PDF for Overleaf / manuscript
%   - 600 dpi PNG as raster backup
%
% Both figures are created at approximately IEEE single-column width
% (3.5 inches) so that text and line sizes remain readable after insertion.
%
% FIGURE 2:
%   - X-axis ends at the later route-completion time.
%   - A vertical line marks "End of route".
%   - Legend is placed below the graph.
%   - Legend is horizontally centered relative to the entire figure.
%
% Usage:
%   plot_price_awareness_comparison_ieee
%
% or:
%   plot_price_awareness_comparison_ieee( ...
%       'path/to/price_awareness_benchmark_results.mat')

clc;

%% ========================================================================
% 1. LOAD BENCHMARK RESULTS
% ========================================================================

if nargin < 1 || isempty(results_mat_file)
    results_mat_file = fullfile( ...
        pwd, ...
        'price_awareness_benchmark_output', ...
        'price_awareness_benchmark_results.mat');
end

if ~isfile(results_mat_file)
    error('Benchmark MAT file not found: %s', results_mat_file);
end

S = load(results_mat_file);

if ~isfield(S, 'benchmark')
    error('The MAT file does not contain variable benchmark.');
end

benchmark = S.benchmark;

output_folder = fileparts(results_mat_file);

if isempty(output_folder)
    output_folder = pwd;
end

cost_unaware = benchmark.unaware.realized_dynamic_cost_USD;
cost_aware   = benchmark.aware.realized_dynamic_cost_USD;
saving_percent = benchmark.cost_saving_percent;

%% ========================================================================
% 2. COMMON IEEE FIGURE SETTINGS
% ========================================================================

font_name = 'Times New Roman';

axes_font_size       = 8;
label_font_size      = 8;
legend_font_size     = 7;
annotation_font_size = 7;

single_column_width_in = 3.5;

%% ========================================================================
% 3. FIGURE 1 — REALIZED CHARGING COST
% ========================================================================

fig1 = figure( ...
    'Name', 'Price Awareness Cost Comparison - IEEE', ...
    'NumberTitle', 'off', ...
    'Units', 'inches', ...
    'Position', [1 1 single_column_width_in 2.65], ...
    'Color', 'w', ...
    'Renderer', 'painters');

ax1 = axes(fig1);

cost_values = [cost_unaware, cost_aware];

bar(ax1, 1:2, cost_values, 0.58);

grid(ax1, 'on');
box(ax1, 'on');

set(ax1, ...
    'XTick', 1:2, ...
    'XTickLabel', {'Price-unaware', 'Price-aware'}, ...
    'FontName', font_name, ...
    'FontSize', axes_font_size, ...
    'LineWidth', 0.8);

ylabel(ax1, ...
    'Realized charging cost (USD)', ...
    'FontName', font_name, ...
    'FontSize', label_font_size);

% No MATLAB title/subtitle.
% The manuscript caption provides the figure description.

y_max = max(cost_values);

if ~isfinite(y_max) || y_max <= 0
    y_max = 1;
end

ylim(ax1, [0, 1.28*y_max]);

% Cost value labels
for i = 1:2

    text(ax1, ...
        i, ...
        cost_values(i) + 0.025*y_max, ...
        sprintf('$%.2f', cost_values(i)), ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'bottom', ...
        'FontName', font_name, ...
        'FontSize', annotation_font_size);

end

% Saving annotation
if isfinite(saving_percent)

    text(ax1, ...
        1.5, ...
        1.17*y_max, ...
        sprintf('Saving = %.1f%%', saving_percent), ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontName', font_name, ...
        'FontSize', annotation_font_size, ...
        'FontWeight', 'bold');

end

% Compact IEEE single-column axes placement
ax1.Position = [0.17 0.18 0.80 0.77];

%% ------------------------------------------------------------------------
% Export Figure 1
% -------------------------------------------------------------------------

cost_png = fullfile( ...
    output_folder, ...
    'price_awareness_cost_comparison_ieee.png');

cost_pdf = fullfile( ...
    output_folder, ...
    'price_awareness_cost_comparison_ieee.pdf');

exportgraphics( ...
    fig1, ...
    cost_pdf, ...
    'ContentType', 'vector', ...
    'BackgroundColor', 'white');

exportgraphics( ...
    fig1, ...
    cost_png, ...
    'Resolution', 600, ...
    'BackgroundColor', 'white');

%% ========================================================================
% 4. FIGURE 2 — CHARGING PROFILE AND ACTUAL LMP
% ========================================================================

actual_LMP = benchmark.actual_LMP;

Eik_unaware = benchmark.unaware.Eik;
Eik_aware   = benchmark.aware.Eik;

K = size(actual_LMP, 2);

dt = 24 / K;

time_h = (0:K-1) * dt;

charge_unaware = sum(Eik_unaware, 1);
charge_aware   = sum(Eik_aware, 1);

mean_price = mean(actual_LMP, 1, 'omitnan');

%% ------------------------------------------------------------------------
% Determine route-completion time
% -------------------------------------------------------------------------

aware_end_h   = benchmark.aware.total_time;
unaware_end_h = benchmark.unaware.total_time;

route_end_candidates = [ ...
    aware_end_h, ...
    unaware_end_h];

route_end_candidates = route_end_candidates( ...
    isfinite(route_end_candidates) & ...
    route_end_candidates > 0);

if isempty(route_end_candidates)

    warning([ ...
        'Valid route-completion time was not found. ' ...
        'The full available horizon will be displayed.']);

    route_end_h = 24;

else

    % Later completion time is used so neither strategy is truncated.
    route_end_h = max(route_end_candidates);

end

route_end_h = min(route_end_h, 24);

%% ------------------------------------------------------------------------
% Create IEEE single-column figure
% -------------------------------------------------------------------------

% Slightly taller than Fig. 1 to leave space for:
%   x-axis label + centered external legend

fig2 = figure( ...
    'Name', 'Price Awareness Charging Profile - IEEE', ...
    'NumberTitle', 'off', ...
    'Units', 'inches', ...
    'Position', [1 1 single_column_width_in 3.25], ...
    'Color', 'w', ...
    'Renderer', 'painters');

ax2 = axes(fig2);

%% ------------------------------------------------------------------------
% LEFT Y-AXIS — Charging decisions
% -------------------------------------------------------------------------

yyaxis(ax2, 'left');

h_unaware = stairs( ...
    ax2, ...
    time_h, ...
    charge_unaware, ...
    'LineWidth', 1.2, ...
    'DisplayName', 'Price-unaware');

hold(ax2, 'on');

h_aware = stairs( ...
    ax2, ...
    time_h, ...
    charge_aware, ...
    '--', ...
    'LineWidth', 1.2, ...
    'DisplayName', 'Price-aware');

ylabel( ...
    ax2, ...
    'Charging energy per slot (kWh)', ...
    'FontName', font_name, ...
    'FontSize', label_font_size);

%% ------------------------------------------------------------------------
% RIGHT Y-AXIS — Actual LMP
% -------------------------------------------------------------------------

yyaxis(ax2, 'right');

h_price = plot( ...
    ax2, ...
    time_h, ...
    mean_price, ...
    'LineWidth', 1.1, ...
    'DisplayName', 'Mean actual LMP');

ylabel( ...
    ax2, ...
    'Mean actual LMP (USD/kWh)', ...
    'FontName', font_name, ...
    'FontSize', label_font_size);

%% ------------------------------------------------------------------------
% Restrict graph to route duration
% -------------------------------------------------------------------------

xlim(ax2, [0, route_end_h]);

xline( ...
    ax2, ...
    route_end_h, ...
    'k--', ...
    'End of route', ...
    'LineWidth', 0.9, ...
    'LabelOrientation', 'horizontal', ...
    'LabelVerticalAlignment', 'top', ...
    'LabelHorizontalAlignment', 'right', ...
    'FontName', font_name, ...
    'FontSize', annotation_font_size, ...
    'HandleVisibility', 'off');

xlabel( ...
    ax2, ...
    'Time from departure (h)', ...
    'FontName', font_name, ...
    'FontSize', label_font_size);

grid(ax2, 'on');
box(ax2, 'on');

set(ax2, ...
    'FontName', font_name, ...
    'FontSize', axes_font_size, ...
    'LineWidth', 0.8);

%% ------------------------------------------------------------------------
% AXES POSITION
% -------------------------------------------------------------------------
% Extra bottom margin is reserved for:
%   1) x-axis label
%   2) legend
%
% Because yyaxis creates asymmetric left/right margins,
% the legend will later be centered relative to the entire FIGURE.

ax2.Units = 'normalized';

ax2.Position = [ ...
    0.17 ...
    0.24 ...
    0.68 ...
    0.70];

%% ------------------------------------------------------------------------
% LEGEND — BELOW GRAPH AND CENTERED RELATIVE TO FIGURE
% -------------------------------------------------------------------------

lgd = legend( ...
    ax2, ...
    [h_unaware, h_aware, h_price], ...
    {'Price-unaware', 'Price-aware', 'Mean actual LMP'}, ...
    'Location', 'southoutside', ...
    'Orientation', 'horizontal', ...
    'NumColumns', 3, ...
    'FontName', font_name, ...
    'FontSize', legend_font_size, ...
    'Box', 'on');

% MATLAB first calculates the legend dimensions.
drawnow;

% Then override its horizontal location relative to the full figure.
lgd.Units = 'normalized';

legend_position = lgd.Position;

% If the legend is too wide for the figure, slightly reduce its font.
if legend_position(3) > 0.96

    lgd.FontSize = 6.5;

    drawnow;

    legend_position = lgd.Position;

end

% Center legend horizontally relative to entire figure.
legend_position(1) = ...
    0.5 - legend_position(3)/2;

% Fixed vertical location below x-axis label.
legend_position(2) = 0.15;

lgd.Position = legend_position;

%% ------------------------------------------------------------------------
% Re-check axes position after legend creation
% -------------------------------------------------------------------------
% Some MATLAB versions modify the axes automatically when creating an
% external legend. Restore the intended axes position.

ax2.Position = [ ...
    0.17 ...
    0.30 ...
    0.68 ...
    0.64];

drawnow;

%% ------------------------------------------------------------------------
% Export Figure 2
% -------------------------------------------------------------------------

profile_png = fullfile( ...
    output_folder, ...
    'price_awareness_charging_profile_route_horizon_ieee.png');

profile_pdf = fullfile( ...
    output_folder, ...
    'price_awareness_charging_profile_route_horizon_ieee.pdf');

exportgraphics( ...
    fig2, ...
    profile_pdf, ...
    'ContentType', 'vector', ...
    'BackgroundColor', 'white');

exportgraphics( ...
    fig2, ...
    profile_png, ...
    'Resolution', 600, ...
    'BackgroundColor', 'white');

%% ========================================================================
% 5. OUTPUTS
% ========================================================================

output_files.cost_png = cost_png;
output_files.cost_pdf = cost_pdf;

output_files.profile_png = profile_png;
output_files.profile_pdf = profile_pdf;

fprintf('\n');
fprintf('============================================================\n');
fprintf('IEEE SINGLE-COLUMN PRICE-AWARENESS FIGURES EXPORTED\n');
fprintf('============================================================\n');

fprintf( ...
    'Price-aware route completion   : %.3f h\n', ...
    aware_end_h);

fprintf( ...
    'Price-unaware route completion : %.3f h\n', ...
    unaware_end_h);

fprintf( ...
    'Displayed profile horizon      : %.3f h\n', ...
    route_end_h);

fprintf('------------------------------------------------------------\n');

fprintf('Vector PDF files for Overleaf:\n');
fprintf('  %s\n', cost_pdf);
fprintf('  %s\n', profile_pdf);

fprintf('------------------------------------------------------------\n');

fprintf('600 dpi PNG backup files:\n');
fprintf('  %s\n', cost_png);
fprintf('  %s\n', profile_png);

fprintf('============================================================\n');

end