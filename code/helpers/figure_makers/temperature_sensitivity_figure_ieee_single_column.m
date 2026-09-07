%% ================================================================
% FILE: temperature_sensitivity_figure_ieee_single_column.m
% PURPOSE:
%   Plot total trip energy versus mean ambient temperature using
%   temperature_sensitivity results already available in the workspace.
%
% IEEE SINGLE-COLUMN OUTPUT:
%   - Figure width: 3.5 in
%   - Times New Roman
%   - Publication-scale fonts and line widths
%   - Vector PDF for Overleaf
%   - 600 dpi PNG backup
%
% REQUIREMENT:
%   Run the main optimization / sensitivity analysis first so that
%   temperature_sensitivity exists in the MATLAB workspace.
%
% OUTPUTS:
%   temperature_trip_energy_ieee.pdf
%   temperature_trip_energy_ieee.png
%   temperature_trip_energy_ieee.fig
% ================================================================

clc;

%% ------------------------------------------------
% 1. Check workspace results
% ------------------------------------------------

if ~exist('temperature_sensitivity','var')
    error(['temperature_sensitivity was not found in the workspace. ' ...
           'Run the main optimization / sensitivity analysis first.']);
end

results = temperature_sensitivity;

required_fields = { ...
    'mean_temperature_C', ...
    'trip_energy_kWh'};

for field_idx = 1:numel(required_fields)
    field_name = required_fields{field_idx};

    if ~isfield(results, field_name)
        error('Missing field in temperature_sensitivity: %s', field_name);
    end
end

%% ------------------------------------------------
% 2. Get sensitivity results
% ------------------------------------------------

mean_temperature_C = results.mean_temperature_C(:);
trip_energy_kWh    = results.trip_energy_kWh(:);

if numel(mean_temperature_C) ~= numel(trip_energy_kWh)
    error(['mean_temperature_C and trip_energy_kWh must contain ' ...
           'the same number of elements.']);
end

%% ------------------------------------------------
% 3. Remove invalid results and sort
% ------------------------------------------------

valid_cases = ...
    isfinite(mean_temperature_C) & ...
    isfinite(trip_energy_kWh);

mean_temperature_C = mean_temperature_C(valid_cases);
trip_energy_kWh    = trip_energy_kWh(valid_cases);

if isempty(mean_temperature_C)
    error('No valid temperature-sensitivity results remain after filtering.');
end

[mean_temperature_C, sort_idx] = sort(mean_temperature_C);
trip_energy_kWh = trip_energy_kWh(sort_idx);

%% ------------------------------------------------
% 4. IEEE single-column style
% ------------------------------------------------

font_name = 'Times New Roman';

figure_width_in  = 3.5;
figure_height_in = 2.45;

axes_font_size  = 7.5;
label_font_size = 8;

curve_line_width = 1.15;
marker_size      = 3.8;
axes_line_width  = 0.75;

%% ------------------------------------------------
% 5. Create figure
% ------------------------------------------------

f = figure( ...
    'Name', 'Temperature Sensitivity - IEEE Single Column', ...
    'NumberTitle', 'off', ...
    'Color', 'w', ...
    'Units', 'inches', ...
    'Position', [1 1 figure_width_in figure_height_in], ...
    'Renderer', 'painters');

tl = tiledlayout( ...
    f, ...
    1, 1, ...
    'Padding', 'compact', ...
    'TileSpacing', 'compact');

ax = nexttile(tl);

plot( ...
    ax, ...
    mean_temperature_C, ...
    trip_energy_kWh, ...
    '-o', ...
    'LineWidth', curve_line_width, ...
    'MarkerSize', marker_size, ...
    'MarkerFaceColor', 'w');

grid(ax, 'on');
box(ax, 'on');

set( ...
    ax, ...
    'FontName', font_name, ...
    'FontSize', axes_font_size, ...
    'LineWidth', axes_line_width, ...
    'TickDir', 'in', ...
    'Layer', 'top');

%% ------------------------------------------------
% 6. Axis labels
% ------------------------------------------------

xlabel( ...
    ax, ...
    'Mean Ambient Temperature (°C)', ...
    'FontName', font_name, ...
    'FontSize', label_font_size);

ylabel( ...
    ax, ...
    'Total Trip Energy (kWh)', ...
    'FontName', font_name, ...
    'FontSize', label_font_size);

% No internal MATLAB title is used.
% The IEEE/Overleaf figure caption should provide the descriptive title.

%% ------------------------------------------------
% 7. Axis limits
% ------------------------------------------------

temperature_span = max(mean_temperature_C) - min(mean_temperature_C);

if temperature_span <= 0
    temperature_margin = 0.5;
else
    temperature_margin = 0.05 * temperature_span;
end

xlim( ...
    ax, ...
    [min(mean_temperature_C) - temperature_margin, ...
     max(mean_temperature_C) + temperature_margin]);

energy_span = max(trip_energy_kWh) - min(trip_energy_kWh);

if energy_span <= 0
    energy_margin = max(1, 0.05 * abs(mean(trip_energy_kWh)));
else
    energy_margin = 0.08 * energy_span;
end

ylim( ...
    ax, ...
    [min(trip_energy_kWh) - energy_margin, ...
     max(trip_energy_kWh) + energy_margin]);

%% ------------------------------------------------
% 8. Optional compact tick formatting
% ------------------------------------------------

% Keep MATLAB-selected tick locations, but enforce consistent typography.
ax.XAxis.FontName = font_name;
ax.YAxis.FontName = font_name;

drawnow;

%% ------------------------------------------------
% 9. Export — IEEE publication files
% ------------------------------------------------

pdf_file = 'temperature_trip_energy_ieee.pdf';
png_file = 'temperature_trip_energy_ieee.png';
fig_file = 'temperature_trip_energy_ieee.fig';

% Preferred manuscript file: vector PDF
exportgraphics( ...
    f, ...
    pdf_file, ...
    'ContentType', 'vector', ...
    'BackgroundColor', 'white');

% High-resolution raster backup
exportgraphics( ...
    f, ...
    png_file, ...
    'Resolution', 600, ...
    'BackgroundColor', 'white');

% Editable MATLAB figure
savefig(f, fig_file);

%% ------------------------------------------------
% 10. Console report
% ------------------------------------------------

fprintf('\n============================================================\n');
fprintf('IEEE SINGLE-COLUMN TEMPERATURE-SENSITIVITY FIGURE EXPORTED\n');
fprintf('============================================================\n');
fprintf('Vector PDF for Overleaf:\n');
fprintf('  %s\n', pdf_file);
fprintf('600 dpi PNG backup:\n');
fprintf('  %s\n', png_file);
fprintf('Editable MATLAB figure:\n');
fprintf('  %s\n', fig_file);
fprintf('============================================================\n');
