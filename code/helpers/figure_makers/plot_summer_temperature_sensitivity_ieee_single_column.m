%% =============================================================================
% FILE: plot_summer_temperature_sensitivity_ieee_single_column.m
% PURPOSE:
%   Creates an IEEE single-column grouped bar chart from the CURRENT
%   summer temperature-sensitivity analysis results.
%
% INPUT (preferred workspace variables):
%   summer_temperature_sensitivity
%   summer_temperature_results_table
%
% FALLBACK MAT file:
%   summer_temperature_sensitivity_results.mat
%
% PLOT:
%   - Temperature offsets from -3 C to +3 C only
%   - Reference-route-fixed vs route-re-optimized DeltaE
%   - No route-change diamond/cross markers
%   - Original summer case (0 C offset) marked by a vertical dashed line
%
% OUTPUT:
%   summer_temperature_sensitivity_deltaE_ieee.pdf   (vector; use in Overleaf)
%   summer_temperature_sensitivity_deltaE_ieee.png   (600 dpi backup)
%   summer_temperature_sensitivity_deltaE_ieee.fig
%
% IMPORTANT:
%   This script does NOT run the optimizer.
%% =============================================================================

clc;
close all;

%% -------------------------------------------------------------------------
% 1. LOAD CURRENT SUMMER SENSITIVITY RESULTS
% --------------------------------------------------------------------------

results_mat_file = 'summer_temperature_sensitivity_results.mat';

workspace_has_results = ...
    exist('summer_temperature_sensitivity','var') && ...
    exist('summer_temperature_results_table','var');

if ~workspace_has_results

    if ~isfile(results_mat_file)
        error([ ...
            'Current summer sensitivity results were not found. ' ...
            'Expected workspace variables: summer_temperature_sensitivity ' ...
            'and summer_temperature_results_table, or file: ' ...
            'summer_temperature_sensitivity_results.mat. ' ...
            'Run summer_temperature_sensitivity_analysis.m first.']);
    end

    loaded_results = load( ...
        results_mat_file, ...
        'summer_temperature_sensitivity', ...
        'summer_temperature_results_table');

    summer_temperature_sensitivity = ...
        loaded_results.summer_temperature_sensitivity;

    summer_temperature_results_table = ...
        loaded_results.summer_temperature_results_table;
end

%% -------------------------------------------------------------------------
% 2. VALIDATE REQUIRED RESULTS
% --------------------------------------------------------------------------

required_table_variables = { ...
    'TemperatureOffset_C', ...
    'FixedRouteDeltaE_kWh', ...
    'ReoptimizedDeltaE_kWh'};

for idx = 1:numel(required_table_variables)

    variable_name = required_table_variables{idx};

    if ~ismember( ...
            variable_name, ...
            summer_temperature_results_table.Properties.VariableNames)

        error('Missing table variable: %s', variable_name);
    end
end

required_struct_fields = { ...
    'reference_mean_temperature_C', ...
    'reference_route_text', ...
    'reference_energy_kWh'};

for idx = 1:numel(required_struct_fields)

    field_name = required_struct_fields{idx};

    if ~isfield(summer_temperature_sensitivity, field_name)
        error('Missing structure field: %s', field_name);
    end
end

%% -------------------------------------------------------------------------
% 3. SELECT -3 TO +3 C SCENARIOS
% --------------------------------------------------------------------------

all_results = sortrows( ...
    summer_temperature_results_table, ...
    'TemperatureOffset_C');

plot_mask = ...
    all_results.TemperatureOffset_C >= -3 & ...
    all_results.TemperatureOffset_C <= 3;

results_table = all_results(plot_mask,:);

expected_offsets_C = (-3:1:3)';
temperature_offset_C = results_table.TemperatureOffset_C(:);

if height(results_table) ~= numel(expected_offsets_C) || ...
        ~isequal(temperature_offset_C, expected_offsets_C)

    error([ ...
        'The results must contain all offsets from -3 C to +3 C ' ...
        'in 1 C increments.']);
end

reference_mean_temperature_C = ...
    summer_temperature_sensitivity.reference_mean_temperature_C;

reference_route_text = char(string( ...
    summer_temperature_sensitivity.reference_route_text));

scenario_mean_temperature_C = ...
    reference_mean_temperature_C + temperature_offset_C;

fixed_route_deltaE_kWh = ...
    results_table.FixedRouteDeltaE_kWh(:);

reoptimized_deltaE_kWh = ...
    results_table.ReoptimizedDeltaE_kWh(:);

number_of_scenarios = numel(temperature_offset_C);
plot_position = (1:number_of_scenarios)';
reference_plot_idx = find(temperature_offset_C == 0,1);

%% -------------------------------------------------------------------------
% 4. IEEE SINGLE-COLUMN STYLE
% --------------------------------------------------------------------------

font_name = 'Times New Roman';

figure_width_in  = 3.5;
figure_height_in = 2.70;

axes_font_size       = 7.5;
label_font_size      = 8;
legend_font_size     = 6.5;
value_font_size      = 6.2;
secondary_tick_size  = 6.2;

%% -------------------------------------------------------------------------
% 5. CREATE FIGURE
% --------------------------------------------------------------------------

f = figure( ...
    'Name','Summer Temperature Sensitivity - IEEE Single Column', ...
    'NumberTitle','off', ...
    'Units','inches', ...
    'Position',[1 1 figure_width_in figure_height_in], ...
    'Color','w', ...
    'Renderer','painters');

ax = axes(f);

bar_handle = bar( ...
    ax, ...
    plot_position, ...
    [fixed_route_deltaE_kWh, reoptimized_deltaE_kWh], ...
    'grouped');

bar_handle(1).DisplayName = 'Reference route fixed';
bar_handle(2).DisplayName = 'Route re-optimized';

hold(ax,'on');

% Zero-energy-change reference
yline( ...
    ax, ...
    0, ...
    'k-', ...
    'LineWidth',0.8, ...
    'HandleVisibility','off');

% Original summer reference
xline( ...
    ax, ...
    reference_plot_idx, ...
    'k--', ...
    'LineWidth',0.8, ...
    'HandleVisibility','off');

grid(ax,'on');
box(ax,'on');

set(ax, ...
    'FontName',font_name, ...
    'FontSize',axes_font_size, ...
    'LineWidth',0.75, ...
    'TickDir','in', ...
    'Layer','top');

ax.XLim = [0.45 number_of_scenarios+0.55];
ax.XTick = plot_position;

offset_labels = arrayfun( ...
    @(v) sprintf('%+d',v), ...
    temperature_offset_C, ...
    'UniformOutput',false);

ax.XTickLabel = offset_labels;
ax.XTickLabelRotation = 0;

xlabel( ...
    ax, ...
    'Temperature offset from original summer profile (°C)', ...
    'FontName',font_name, ...
    'FontSize',label_font_size);

ylabel( ...
    ax, ...
    '\DeltaE relative to original summer case (kWh)', ...
    'FontName',font_name, ...
    'FontSize',label_font_size);

%% -------------------------------------------------------------------------
% 6. ADD MEAN TEMPERATURES BELOW X TICKS
% --------------------------------------------------------------------------

drawnow;

current_ylim = ylim(ax);
y_span = diff(current_ylim);

mean_label_y = current_ylim(1) - 0.065*y_span;

for idx = 1:number_of_scenarios

    text( ...
        ax, ...
        plot_position(idx), ...
        mean_label_y, ...
        sprintf('(%.2f°C)',scenario_mean_temperature_C(idx)), ...
        'HorizontalAlignment','center', ...
        'VerticalAlignment','top', ...
        'FontName',font_name, ...
        'FontSize',secondary_tick_size, ...
        'Clipping','off');
end

% Reserve room below for second row of x labels.
ax.Position = [0.17 0.25 0.79 0.70];

%% -------------------------------------------------------------------------
% 7. LEGEND
% --------------------------------------------------------------------------

legend( ...
    ax, ...
    'Location','northeast', ...
    'FontName',font_name, ...
    'FontSize',legend_font_size, ...
    'Box','on');

hold(ax,'off');

%% -------------------------------------------------------------------------
% 8. EXPORT
% --------------------------------------------------------------------------

pdf_file = 'summer_temperature_sensitivity_deltaE_ieee.pdf';
png_file = 'summer_temperature_sensitivity_deltaE_ieee.png';
fig_file = 'summer_temperature_sensitivity_deltaE_ieee.fig';

exportgraphics( ...
    f, ...
    pdf_file, ...
    'ContentType','vector', ...
    'BackgroundColor','white');

exportgraphics( ...
    f, ...
    png_file, ...
    'Resolution',600, ...
    'BackgroundColor','white');

savefig(f,fig_file);

%% -------------------------------------------------------------------------
% 9. REPORT
% --------------------------------------------------------------------------

fprintf('\n============================================================\n');
fprintf('IEEE SUMMER TEMPERATURE-SENSITIVITY FIGURE EXPORTED\n');
fprintf('============================================================\n');
fprintf('Reference mean temperature : %.2f C\n', ...
    reference_mean_temperature_C);
fprintf('Reference route            : %s\n', ...
    reference_route_text);
fprintf('Displayed offsets          : -3 C to +3 C\n');
fprintf('Vector PDF for Overleaf    : %s\n',pdf_file);
fprintf('600 dpi PNG backup         : %s\n',png_file);
fprintf('Editable MATLAB figure     : %s\n',fig_file);
fprintf('============================================================\n');
