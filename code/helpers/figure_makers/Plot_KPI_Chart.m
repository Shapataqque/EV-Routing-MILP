%% ================================================================
% FILE: summary_figures_separate_ieee_png.m
% PURPOSE:
%   Generate each Summary plot as a separate IEEE-style single-column
%   figure and save as 300 DPI PNG
%
%   Updated:
%   - Reduced excessive bottom whitespace
%   - Kept HVAC annotations, but moved them closer to the axis
%   - Cleaner export using exportgraphics
% ================================================================

clearvars -except results_list sol_cost sol_time sol_energy sol_distance
clc;

%% ------------------------------------------------
% 1. Get results from workspace
% ------------------------------------------------
use_results_list = false;

if exist('results_list','var') && ~isempty(results_list) && numel(results_list)>=2 ...
        && ~isempty(results_list{2})
    use_results_list = true;
end

if use_results_list
    res = results_list{2};   % fixed dataset

    sol_c = res.sol_cost;
    sol_t = res.sol_time;
    sol_e = res.sol_energy;
    sol_d = res.sol_dist;

else
    requiredVars = {'sol_cost','sol_time','sol_energy','sol_distance'};
    for i = 1:length(requiredVars)
        if ~exist(requiredVars{i},'var')
            error(['Missing variable: ', requiredVars{i}, '. Run main script first.'])
        end
    end

    sol_c = sol_cost;
    sol_t = sol_time;
    sol_e = sol_energy;
    sol_d = sol_distance;
end

%% ------------------------------------------------
% 2. Data
% ------------------------------------------------
labels_main = {'Cost Opt','Time Opt','Energy Opt','Dist Opt'};

times   = [sol_c.total_time,   sol_t.total_time,   sol_e.total_time,   sol_d.total_time];
costs   = [sol_c.total_cost,   sol_t.total_cost,   sol_e.total_cost,   sol_d.total_cost];
energy  = [sol_c.total_energy, sol_t.total_energy, sol_e.total_energy, sol_d.total_energy];
dist    = [sol_c.total_dist,   sol_t.total_dist,   sol_e.total_dist,   sol_d.total_dist];

solve_times = nan(1,4);
if isfield(sol_c,'solve_time'); solve_times(1)=sol_c.solve_time; end
if isfield(sol_t,'solve_time'); solve_times(2)=sol_t.solve_time; end
if isfield(sol_e,'solve_time'); solve_times(3)=sol_e.solve_time; end
if isfield(sol_d,'solve_time'); solve_times(4)=sol_d.solve_time; end

%% ------------------------------------------------
% 3. Common IEEE Figure Settings
% ------------------------------------------------
fig_w = 3.5;      % IEEE single-column width (inches)
fig_h = 2.70;     % reduced figure height to avoid visual emptiness
fs_axis  = 7;
fs_title = 8;
fs_annot = 6.2;
bar_lw   = 0.8;

make_ieee_bar_png_grouped(times, labels_main, ...
    'Total Trip Time (h)', 'Hours', [0.2 0.2 0.5], ...
    'Total_trip_time.png', fig_w, fig_h, fs_axis, fs_title, fs_annot, bar_lw);

make_ieee_bar_png_grouped(costs, labels_main, ...
    'Total Charging Cost ($)', 'USD ($)', [0.2 0.5 0.2], ...
    'Total_charging_cost.png', fig_w, fig_h, fs_axis, fs_title, fs_annot, bar_lw);

make_ieee_bar_png_grouped(energy, labels_main, ...
    'Total Energy Consumed (kWh)', 'kWh', [0.85 0.45 0.1], ...
    'Total_energy.png', fig_w, fig_h, fs_axis, fs_title, fs_annot, bar_lw);

make_ieee_bar_png_grouped(dist, labels_main, ...
    'Total Distance Traveled (km)', 'km', [0.5 0.2 0.5], ...
    'Total_distance.png', fig_w, fig_h, fs_axis, fs_title, fs_annot, bar_lw);

make_ieee_bar_png_grouped(solve_times, labels_main, ...
    'Solver Computation Time (s)', 'Seconds', [0.5 0.5 0.5], ...
    'Solver_time.png', fig_w, fig_h, fs_axis, fs_title, fs_annot, bar_lw);

disp('All IEEE-style PNG figures saved successfully.')

%% ================================================================
% HELPER FUNCTION
% ================================================================
function make_ieee_bar_png_grouped(values, labels, plot_title, ylab, face_color, out_name, ...
                                   fig_w, fig_h, fs_axis, fs_title, fs_annot, bar_lw)

    f = figure('Color','w', ...
               'Units','inches', ...
               'Position',[1 1 fig_w fig_h], ...
               'PaperUnits','inches');

    % Reduced bottom margin; annotations will sit closer to axis
    ax = axes('Parent',f, 'Position',[0.16 0.20 0.78 0.69]);

    b = bar(ax, values, 'FaceColor', face_color, 'LineWidth', bar_lw);
    hold(ax, 'on');
    grid(ax, 'on');
    box(ax, 'on');

    b.EdgeColor = [0.15 0.15 0.15];

    ax.FontSize = fs_axis;
    ax.LineWidth = 0.8;
    ax.XTick = 1:numel(labels);
    ax.XTickLabel = labels;
    ax.Color = 'w';

    ylabel(ax, ylab, 'FontSize', fs_axis);
    title(ax, plot_title, 'FontSize', fs_title, 'FontWeight', 'bold');

    xlim(ax, [0.5 4.5]);

    valid_vals = values(~isnan(values));
    if isempty(valid_vals)
        ymax = 1;
    else
        ymax = max(valid_vals);
        if ymax <= 0
            ymax = 1;
        end
    end
    ylim(ax, [0 1.15*ymax]);

    % Tighten axis outer padding
    ax.LooseInset = max(ax.TightInset, [0.02 0.02 0.02 0.02]);

    % ------------------------------------------------
    % Figure-level annotations (normalized coordinates)
    % ------------------------------------------------
    axpos = ax.Position;   % [left bottom width height]

    x_to_fig = @(xdata) axpos(1) + axpos(3) * ((xdata - 0.5) / (4.5 - 0.5));

    % Move annotations closer to x-axis to eliminate big bottom whitespace
    y_line = axpos(2) - 0.050;
    y_text = axpos(2) - 0.088;

    % HVAC Aware under bars 1-3
    x1 = x_to_fig(1.0);
    x2 = x_to_fig(3.0);

    annotation(f,'line',[x1 x2],[y_line y_line],'Color','k','LineWidth',0.8);
    annotation(f,'line',[x1 x1],[y_line-0.008 y_line+0.008],'Color','k','LineWidth',0.8);
    annotation(f,'line',[x2 x2],[y_line-0.008 y_line+0.008],'Color','k','LineWidth',0.8);

    annotation(f,'textbox',[(x1+x2)/2 - 0.13, y_text, 0.26, 0.028], ...
        'String','HVAC Aware', ...
        'HorizontalAlignment','center', ...
        'VerticalAlignment','middle', ...
        'LineStyle','none', ...
        'FontSize',fs_annot, ...
        'Margin',0);

    % no HVAC under bar 4
    x3 = x_to_fig(3.75);
    x4 = x_to_fig(4.25);

    annotation(f,'line',[x3 x4],[y_line y_line],'Color','k','LineWidth',0.8);
    annotation(f,'line',[x3 x3],[y_line-0.008 y_line+0.008],'Color','k','LineWidth',0.8);
    annotation(f,'line',[x4 x4],[y_line-0.008 y_line+0.008],'Color','k','LineWidth',0.8);

    annotation(f,'textbox',[(x3+x4)/2 - 0.07, y_text, 0.14, 0.028], ...
        'String','no HVAC', ...
        'HorizontalAlignment','center', ...
        'VerticalAlignment','middle', ...
        'LineStyle','none', ...
        'FontSize',fs_annot, ...
        'Margin',0);

    % Export with tighter cropping
    exportgraphics(f, out_name, 'Resolution', 300);
    close(f);
end