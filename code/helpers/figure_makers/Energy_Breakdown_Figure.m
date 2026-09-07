%% ================================================================
% FILE: energy_breakdown_figure_ieee.m
% PURPOSE:
%   Energy Breakdown (Traction + HVAC)
%   Includes Dist Opt (no HVAC)
%   IEEE single-column PNG (300 DPI)
% ================================================================

%% ------------------------------------------------
% 1. Get results
% ------------------------------------------------
use_results_list = false;

if exist('results_list','var') && numel(results_list) >= 2 && ~isempty(results_list{2})
    use_results_list = true;
end

if use_results_list
    res = results_list{3};

    sol_c = res.sol_cost;
    sol_t = res.sol_time;
    sol_e = res.sol_energy;
    sol_d = res.sol_dist;

    route_c = res.route_cost;
    route_t = res.route_time;
    route_e = res.route_energy;
    route_d = res.route_dist;

    data = data_fixed;

else
    sol_c = sol_cost;
    sol_t = sol_time;
    sol_e = sol_energy;
    sol_d = sol_distance;

    data = data_fixed;

    route_c = sol_c.route;
    route_t = sol_t.route;
    route_e = sol_e.route;
    route_d = sol_d.route;
end

%% ------------------------------------------------
% 2. Compute energies
% ------------------------------------------------
traction_from_route = @(rt) sum(diag(data.E0(rt(1:end-1), rt(2:end))));

traction_c = traction_from_route(route_c);
traction_t = traction_from_route(route_t);
traction_e = traction_from_route(route_e);
traction_d = traction_from_route(route_d);

hvac_c = sol_c.total_energy - traction_c;
hvac_t = sol_t.total_energy - traction_t;
hvac_e = sol_e.total_energy - traction_e;
hvac_d = 0;   % distance objective ignores HVAC

labels = {'Cost Opt','Time Opt','Energy Opt','Dist Opt'};

traction_vals = [traction_c traction_t traction_e traction_d];
hvac_vals     = [hvac_c hvac_t hvac_e hvac_d];
total_vals    = traction_vals + hvac_vals;

stacked_data = [traction_vals(:) hvac_vals(:)];

%% ------------------------------------------------
% 3. Figure
% ------------------------------------------------
fig_w = 3.5;
fig_h = 2.65;   % slightly shorter to reduce visual emptiness

f = figure( ...
    'Color','w', ...
    'Units','inches', ...
    'Position',[1 1 fig_w fig_h], ...
    'PaperPositionMode','auto');

tl = tiledlayout(f,1,1,'Padding','compact','TileSpacing','compact');
ax = nexttile(tl);

b = bar(ax, stacked_data, 'stacked', 'LineWidth', 0.8);
hold(ax,'on')
grid(ax,'on')
box(ax,'on')

% Colors
b(1).FaceColor = [0.90 0.50 0.10];   % Traction
b(2).FaceColor = [0.20 0.45 0.85];   % HVAC
b(1).EdgeColor = [0.15 0.15 0.15];
b(2).EdgeColor = [0.15 0.15 0.15];

ax.FontSize = 7;
ax.LineWidth = 0.8;
ax.Color = 'w';

ax.XTick = 1:4;
ax.XTickLabel = labels;
xtickangle(ax,0)   % removes extra bottom whitespace caused by rotated labels

ylabel(ax,'Energy (kWh)')
title(ax,'Contribution of HVAC and Traction Energy','FontSize',8.5,'FontWeight','bold')

legend(ax, {'Traction','HVAC'}, ...
    'Location','northeast', ...
    'FontSize',6.5, ...
    'Box','on')

xlim(ax,[0.5 4.5])

ymax = max(total_vals);
ylim(ax,[0 1.18*ymax])

% Tighten outer whitespace further
ax.LooseInset = max(ax.TightInset, [0.02 0.02 0.02 0.02]);

%% ------------------------------------------------
% 4. Value labels
% ------------------------------------------------
for i = 1:length(total_vals)

    % traction label inside lower bar
    text(ax, i, traction_vals(i)*0.55, ...
        sprintf('%.2f', traction_vals(i)), ...
        'HorizontalAlignment','center', ...
        'VerticalAlignment','middle', ...
        'FontSize',6.5, ...
        'Color','w', ...
        'FontWeight','bold');

    % total label above stack
    text(ax, i, total_vals(i) + 0.02*ymax, ...
        sprintf('%.2f', total_vals(i)), ...
        'HorizontalAlignment','center', ...
        'VerticalAlignment','bottom', ...
        'FontSize',6.5, ...
        'Color','k');
end

%% ------------------------------------------------
% 5. Export
% ------------------------------------------------
exportgraphics(f, 'Energy_breakdown.png', 'Resolution', 300);

disp("Saved: Energy_breakdown.png")