%% ================================================================
% FILE: energy_rate_over_time_ieee.m
% PURPOSE:
%   Generate two separate IEEE-style single-column PNG figures:
%   1) Cumulative average energy-use rate over time  [kW]
%   2) Instantaneous segment energy-use rate over time [kW]
%
% X-axis:
%   real time labels starting at 10:00 (or data.start_hour if available)
%
% Y-axis:
%   (1) cumulative consumed energy / elapsed time
%   (2) segment energy / segment travel time
% ================================================================

%% ------------------------------------------------
% 1. Fetch results from workspace
% ------------------------------------------------
use_results_list = false;

if exist('results_list','var') && ~isempty(results_list) && numel(results_list) >= 2 ...
        && ~isempty(results_list{2})
    use_results_list = true;
end

if use_results_list
    res = results_list{2};   % fixed dataset

    sol_c = res.sol_cost;
    sol_t = res.sol_time;
    sol_e = res.sol_energy;
    sol_d = res.sol_dist;

    route_c = res.route_cost;
    route_t = res.route_time;
    route_e = res.route_energy;
    route_d = res.route_dist;

    if exist('data_fixed','var')
        data = data_fixed;
    else
        error('data_fixed not found in workspace. Run the main script first.');
    end

else
    requiredVars = {'sol_cost','sol_time','sol_energy','sol_distance','data_fixed'};
    for i = 1:length(requiredVars)
        if ~exist(requiredVars{i},'var')
            error(['Missing variable: ', requiredVars{i}, '. Run main script first.']);
        end
    end

    sol_c = sol_cost;
    sol_t = sol_time;
    sol_e = sol_energy;
    sol_d = sol_distance;
    data  = data_fixed;

    if ~isfield(sol_c,'route') || ~isfield(sol_t,'route') || ~isfield(sol_e,'route') || ~isfield(sol_d,'route')
        error('Route field missing in one or more solution structs.');
    end

    route_c = sol_c.route;
    route_t = sol_t.route;
    route_e = sol_e.route;
    route_d = sol_d.route;
end

%% ------------------------------------------------
% 2. Start hour
% ------------------------------------------------
if isfield(data,'start_hour')
    start_hour = data.start_hour;
else
    start_hour = 10;   % fallback requested by user
end

%% ------------------------------------------------
% 3. Build profiles for each optimization result
% ------------------------------------------------
prof_c = build_energy_rate_profile(sol_c, route_c, data, false);
prof_t = build_energy_rate_profile(sol_t, route_t, data, false);
prof_e = build_energy_rate_profile(sol_e, route_e, data, false);
prof_d = build_energy_rate_profile(sol_d, route_d, data, true);   % no HVAC

max_end_time = max([prof_c.t_end, prof_t.t_end, prof_e.t_end, prof_d.t_end]);

%% ------------------------------------------------
% 4. IEEE single-column style settings
% ------------------------------------------------
fig_w = 3.5;   % inches
fig_h = 2.55;  % compact single-column height

fs_axis  = 7;
fs_title = 8;
lw_main  = 1.4;

clr_cost   = [0.85 0.33 0.10];
clr_time   = [0.00 0.45 0.74];
clr_energy = [0.47 0.67 0.19];
clr_dist   = [0.20 0.20 0.20];

%% ------------------------------------------------
% 5. Figure 1 - Cumulative average energy-use rate
% ------------------------------------------------
f1 = figure('Color','w', ...
            'Units','inches', ...
            'Position',[1 1 fig_w fig_h], ...
            'PaperUnits','inches');

ax1 = axes('Parent',f1, 'Position',[0.16 0.18 0.78 0.72]);
hold(ax1,'on');
grid(ax1,'on');
box(ax1,'on');

plot(ax1, prof_c.t_curve, prof_c.y_cum, 'LineWidth', lw_main, 'Color', clr_cost);
plot(ax1, prof_t.t_curve, prof_t.y_cum, 'LineWidth', lw_main, 'Color', clr_time);
plot(ax1, prof_e.t_curve, prof_e.y_cum, 'LineWidth', lw_main, 'Color', clr_energy);
plot(ax1, prof_d.t_curve, prof_d.y_cum, 'LineWidth', lw_main, 'Color', clr_dist, 'LineStyle','--');

xlabel(ax1, 'Time', 'FontSize', fs_axis);
ylabel(ax1, 'Cumulative Energy/Time (kW)', 'FontSize', fs_axis);
title(ax1, 'Cumulative Average Energy-Use Rate', 'FontSize', fs_title, 'FontWeight','bold');

ax1.FontSize = fs_axis;
ax1.LineWidth = 0.8;
xlim(ax1, [0 max_end_time*1.02]);

apply_real_time_ticks(ax1, start_hour, max_end_time);

legend(ax1, {'Cost Opt','Time Opt','Energy Opt','Dist Opt'}, ...
       'Location','northeast', 'FontSize', 6, 'Box','on');

set(f1,'PaperPositionMode','auto');
print(f1, 'cumulative_energy_rate_ieee.png', '-dpng', '-r300');

%% ------------------------------------------------
% 6. Figure 2 - Instantaneous segment energy-use rate
% ------------------------------------------------
f2 = figure('Color','w', ...
            'Units','inches', ...
            'Position',[1 1 fig_w fig_h], ...
            'PaperUnits','inches');

ax2 = axes('Parent',f2, 'Position',[0.16 0.18 0.78 0.72]);
hold(ax2,'on');
grid(ax2,'on');
box(ax2,'on');

stairs(ax2, prof_c.t_inst, prof_c.y_inst, 'LineWidth', lw_main, 'Color', clr_cost);
stairs(ax2, prof_t.t_inst, prof_t.y_inst, 'LineWidth', lw_main, 'Color', clr_time);
stairs(ax2, prof_e.t_inst, prof_e.y_inst, 'LineWidth', lw_main, 'Color', clr_energy);
stairs(ax2, prof_d.t_inst, prof_d.y_inst, 'LineWidth', lw_main, 'Color', clr_dist, 'LineStyle','--');

xlabel(ax2, 'Time', 'FontSize', fs_axis);
ylabel(ax2, 'Instantaneous Energy/Time (kW)', 'FontSize', fs_axis);
title(ax2, 'Instantaneous Segment Energy-Use Rate', 'FontSize', fs_title, 'FontWeight','bold');

ax2.FontSize = fs_axis;
ax2.LineWidth = 0.8;
xlim(ax2, [0 max_end_time*1.02]);

apply_real_time_ticks(ax2, start_hour, max_end_time);

legend(ax2, {'Cost Opt','Time Opt','Energy Opt','Dist Opt'}, ...
       'Location','northeast', 'FontSize', 6, 'Box','on');

set(f2,'PaperPositionMode','auto');
print(f2, 'instantaneous_energy_rate_ieee.png', '-dpng', '-r300');

disp('Saved:')
disp(' - cumulative_energy_rate_ieee.png')
disp(' - instantaneous_energy_rate_ieee.png')

%% ================================================================
% HELPER: build energy-rate profile
% ================================================================
function prof = build_energy_rate_profile(sol, route, data, use_static_E0_for_all_segments)

    if isempty(route) || numel(route) < 2
        error('Route is empty or too short.');
    end

    % curves
    t_curve = 0;
    y_cum   = 0;

    t_inst = [];
    y_inst = [];

    cum_energy = 0;

    for m = 1:(numel(route)-1)
        i = route(m);
        j = route(m+1);

        t_arr_i = sol.t_arr(i);
        t_ch_i  = sol.t_ch(i);
        t_dep_i = t_arr_i + t_ch_i;
        t_arr_j = sol.t_arr(j);

        seg_time = t_arr_j - t_dep_i;
        if seg_time <= 1e-10
            continue;
        end

        % arrival slot at j
        k_arr = floor(t_arr_j / data.dt_h) + 1;
        k_arr = max(1, min(data.Tslots, k_arr));

        if use_static_E0_for_all_segments
            seg_energy = data.E0(i,j);
        else
            seg_energy = data.E_dynamic(i,j,k_arr);
        end

        cum_energy = cum_energy + seg_energy;

        % cumulative average at segment end
        t_curve(end+1) = t_arr_j; %#ok<AGROW>
        y_cum(end+1)   = cum_energy / t_arr_j; %#ok<AGROW>

        % instantaneous step profile over the driving interval
        inst_rate = seg_energy / seg_time;

        if isempty(t_inst)
            t_inst = [t_dep_i, t_arr_j];
            y_inst = [inst_rate, inst_rate];
        else
            % break then new plateau
            t_inst = [t_inst, t_dep_i, t_dep_i, t_arr_j]; %#ok<AGROW>
            y_inst = [y_inst, y_inst(end), inst_rate, inst_rate]; %#ok<AGROW>
        end
    end

    % if still empty
    if isempty(t_inst)
        t_inst = [0 0];
        y_inst = [0 0];
    end

    prof.t_curve = t_curve;
    prof.y_cum   = y_cum;
    prof.t_inst  = t_inst;
    prof.y_inst  = y_inst;
    prof.t_end   = max(sol.t_arr(route));
end

%% ------------------------------------------------
% 8. EXTRA FIGURE - Instantaneous energy rate as TRUE LINE PLOT
%    using segment midpoints (alternative approach)
% ------------------------------------------------

% Segment-midpoint based profiles
[mid_c_t, mid_c_y] = build_midpoint_profile(sol_c, route_c, data, false);
[mid_t_t, mid_t_y] = build_midpoint_profile(sol_t, route_t, data, false);
[mid_e_t, mid_e_y] = build_midpoint_profile(sol_e, route_e, data, false);
[mid_d_t, mid_d_y] = build_midpoint_profile(sol_d, route_d, data, true);   % Dist Opt -> no HVAC

f4 = figure('Color','w', ...
            'Units','inches', ...
            'Position',[1 1 fig_w fig_h], ...
            'PaperUnits','inches');

ax4 = axes('Parent',f4, 'Position',[0.16 0.18 0.78 0.72]);
hold(ax4,'on');
grid(ax4,'on');
box(ax4,'on');

plot(ax4, mid_c_t, mid_c_y, '-o', 'LineWidth', lw_main, 'Color', clr_cost, ...
    'MarkerSize', 3.5, 'MarkerFaceColor', clr_cost);
plot(ax4, mid_t_t, mid_t_y, '-o', 'LineWidth', lw_main, 'Color', clr_time, ...
    'MarkerSize', 3.5, 'MarkerFaceColor', clr_time);
plot(ax4, mid_e_t, mid_e_y, '-o', 'LineWidth', lw_main, 'Color', clr_energy, ...
    'MarkerSize', 3.5, 'MarkerFaceColor', clr_energy);
plot(ax4, mid_d_t, mid_d_y, '--o', 'LineWidth', lw_main, 'Color', clr_dist, ...
    'MarkerSize', 3.5, 'MarkerFaceColor', clr_dist);

xlabel(ax4, 'Time', 'FontSize', fs_axis);
ylabel(ax4, 'Instantaneous Energy/Time (kW)', 'FontSize', fs_axis);
title(ax4, 'Instantaneous Segment Energy-Use Rate', 'FontSize', fs_title, 'FontWeight','bold');

ax4.FontSize = fs_axis;
ax4.LineWidth = 0.8;
xlim(ax4, [0 max_end_time*1.02]);

apply_real_time_ticks(ax4, start_hour, max_end_time);

legend(ax4, {'Cost Opt','Time Opt','Energy Opt','Dist Opt'}, ...
       'Location','northeast', 'FontSize', 6, 'Box','on');

set(f4,'PaperPositionMode','auto');
print(f4, 'Instantaneous_energy_rate_line.png', '-dpng', '-r300');

disp('Saved:')
disp(' - instantaneous_energy_rate_midpoint_line_ieee.png')

%% ================================================================
% HELPER: apply real-time tick labels
% ================================================================
function apply_real_time_ticks(ax, start_hour, max_end_time)

    % choose 4-hour ticks like dashboard style
    tick_step = 4;

    tmax_ceil = ceil(max_end_time);
    tick_vals = 0:tick_step:tmax_ceil;

    if isempty(tick_vals) || tick_vals(end) < max_end_time
        tick_vals = [tick_vals, max_end_time];
    end

    tick_labels = cell(size(tick_vals));
    for ii = 1:numel(tick_vals)
        real_hour = mod(start_hour + tick_vals(ii), 24);
        hh = floor(real_hour);
        mm = round((real_hour - hh)*60);

        if mm == 60
            hh = mod(hh + 1, 24);
            mm = 0;
        end

        tick_labels{ii} = sprintf('%02d:%02d', hh, mm);
    end

    set(ax, 'XTick', tick_vals, 'XTickLabel', tick_labels);
end
%% ================================================================
% HELPER: midpoint-based instantaneous profile
% ================================================================
function [t_mid, y_mid] = build_midpoint_profile(sol, route, data, use_static_E0_for_all_segments)

    if isempty(route) || numel(route) < 2
        error('Route is empty or too short.');
    end

    t_mid = [];
    y_mid = [];

    for m = 1:(numel(route)-1)
        i = route(m);
        j = route(m+1);

        t_arr_i = sol.t_arr(i);
        t_ch_i  = sol.t_ch(i);
        t_dep_i = t_arr_i + t_ch_i;
        t_arr_j = sol.t_arr(j);

        seg_time = t_arr_j - t_dep_i;
        if seg_time <= 1e-10
            continue;
        end

        % segment midpoint time
        t_center = 0.5 * (t_dep_i + t_arr_j);

        % arrival slot at j
        k_arr = floor(t_arr_j / data.dt_h) + 1;
        k_arr = max(1, min(data.Tslots, k_arr));

        if use_static_E0_for_all_segments
            seg_energy = data.E0(i,j);
        else
            seg_energy = data.E_dynamic(i,j,k_arr);
        end

        inst_rate = seg_energy / seg_time;

        t_mid(end+1) = t_center; %#ok<AGROW>
        y_mid(end+1) = inst_rate; %#ok<AGROW>
    end
end