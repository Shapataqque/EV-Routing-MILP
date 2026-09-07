%% ================================================================
% FILE: HVAC_Ratio_Figure.m
% PURPOSE:
%   Plot HVAC cost ratio and HVAC time ratio
%   HVAC Cost / Total Trip Cost
%   HVAC Charging Time / Total Trip Time
%   Add HVAC absolute cost on secondary Y-axis as a line
%   IEEE-friendly white background export
% ================================================================

%% ------------------------------------------------
% 1. Same workspace extraction (UNCHANGED)
% ------------------------------------------------
use_results_list = false;

if exist('results_list','var') && ~isempty(results_list) && numel(results_list) >= 2 ...
        && ~isempty(results_list{2})
    use_results_list = true;
end

if use_results_list
    res = results_list{2};

    sol_c = res.sol_cost;
    sol_t = res.sol_time;
    sol_e = res.sol_energy;

    route_c = res.route_cost;
    route_t = res.route_time;
    route_e = res.route_energy;

    data = data_fixed;

else
    sol_c = sol_cost;
    sol_t = sol_time;
    sol_e = sol_energy;

    route_c = sol_c.route;
    route_t = sol_t.route;
    route_e = sol_e.route;

    data = data_fixed;
end

%% ------------------------------------------------
% 2. HVAC energy
% ------------------------------------------------
traction_from_route = @(rt) sum(diag(data.E0(rt(1:end-1), rt(2:end))));

traction_c = traction_from_route(route_c);
traction_t = traction_from_route(route_t);
traction_e = traction_from_route(route_e);

hvac_c = sol_c.total_energy - traction_c;
hvac_t = sol_t.total_energy - traction_t;
hvac_e = sol_e.total_energy - traction_e;

%% ------------------------------------------------
% 3. HVAC cost and HVAC time
% ------------------------------------------------
avg_lmp = mean(data.LMP(:));
avg_P_candidates = data.P_charge_kW(data.P_charge_kW > 0);

if isempty(avg_P_candidates)
    error('No positive charging power values found in data.P_charge_kW.');
end

avg_P = mean(avg_P_candidates);

hvac_cost = [hvac_c hvac_t hvac_e] * avg_lmp;   % [$]
hvac_time = [hvac_c hvac_t hvac_e] / avg_P;     % [h]

%% ------------------------------------------------
% 4. TOTAL trip cost & time
% ------------------------------------------------
total_cost = [sol_c.total_cost sol_t.total_cost sol_e.total_cost];

total_time = [
    sol_c.t_arr(route_c(end))
    sol_t.t_arr(route_t(end))
    sol_e.t_arr(route_e(end))
];

%% ------------------------------------------------
% 5. Ratios
% ------------------------------------------------
cost_ratio = 100 * (hvac_cost ./ total_cost);
time_ratio = 100 * (hvac_time ./ total_time');

plot_data = [cost_ratio(:), time_ratio(:)];

labels = {'Cost Opt','Time Opt','Energy Opt'};
x = 1:3;

%% ------------------------------------------------
% 6. IEEE Figure settings
% ------------------------------------------------
fig_w = 3.5;
fig_h = 2.6;

% Explicit colors for publication-quality consistency
bar_color_1 = [0.20 0.55 0.85];   % HVAC Cost Ratio
bar_color_2 = [0.70 0.85 0.98];   % HVAC Time Ratio
line_color  = [0.90 0.40 0.10];   % HVAC Cost ($)
text_color  = [0.10 0.10 0.10];

fig = figure('Color','w', ...
    'Units','inches', ...
    'Position',[1 1 fig_w fig_h], ...
    'InvertHardcopy','off');

ax = axes(fig);
hold(ax,'on');
box(ax,'on');
grid(ax,'on');

% Force white plot area as well
ax.Color = 'w';
ax.FontSize = 7;
ax.LineWidth = 0.8;
ax.XColor = 'k';
ax.YColor = 'k';
ax.GridColor = [0.85 0.85 0.85];
ax.GridAlpha = 0.6;
ax.Layer = 'top';

%% ------------------------------------------------
% 7. Left axis: ratios as grouped bars
% ------------------------------------------------
yyaxis left

b = bar(x, plot_data, 'grouped', 'BarWidth', 0.72);
b(1).FaceColor = bar_color_1;
b(1).EdgeColor = [0.35 0.35 0.35];
b(1).LineWidth = 0.6;

b(2).FaceColor = bar_color_2;
b(2).EdgeColor = [0.35 0.35 0.35];
b(2).LineWidth = 0.6;

ylabel('Ratio (%)')
ax.YAxis(1).Color = [0 0 0];

ymax_left = max(plot_data(:));
if ymax_left <= 0
    ymax_left = 1;
end
ylim([0, ymax_left * 1.35])

set(ax,'XTick',x,'XTickLabel',labels)
xtickangle(25)
xlim([0.45 3.55])

%% ------------------------------------------------
% 8. Right axis: HVAC cost as line
% ------------------------------------------------
yyaxis right

p = plot(x, hvac_cost, '-o', ...
    'Color', line_color, ...
    'LineWidth', 1.6, ...
    'MarkerSize', 5.5, ...
    'MarkerFaceColor', 'w', ...
    'MarkerEdgeColor', line_color);

ylabel('HVAC Cost ($)')
ax.YAxis(2).Color = line_color;

ymin_right = min(hvac_cost);
ymax_right = max(hvac_cost);

if abs(ymax_right - ymin_right) < 1e-6
    pad = max(0.1, 0.1*ymax_right);
else
    pad = 0.15 * (ymax_right - ymin_right);
end
ylim([ymin_right - pad, ymax_right + pad])

%% ------------------------------------------------
% 9. Title / legend
% ------------------------------------------------
title('Relative Impact of HVAC Energy Consumption', 'FontWeight','bold')

lgd = legend([b(1), b(2), p], ...
    {'HVAC Cost Ratio','HVAC Time Ratio','HVAC Cost ($)'}, ...
    'Location','northwest');
lgd.Box = 'on';
lgd.Color = 'w';
lgd.EdgeColor = [0.4 0.4 0.4];

%% ------------------------------------------------
% 10. Value labels
% ------------------------------------------------
% Ratio labels
yyaxis left
for i = 1:numel(x)
    text(x(i)-0.15, cost_ratio(i) + 0.6, sprintf('%.1f%%', cost_ratio(i)), ...
        'HorizontalAlignment','center', ...
        'VerticalAlignment','bottom', ...
        'FontSize',7, ...
        'Color',text_color, ...
        'Clipping','off');

    text(x(i)+0.15, time_ratio(i) + 0.6, sprintf('%.1f%%', time_ratio(i)), ...
        'HorizontalAlignment','center', ...
        'VerticalAlignment','bottom', ...
        'FontSize',7, ...
        'Color',text_color, ...
        'Clipping','off');
end

% HVAC cost labels
yyaxis right
for i = 1:numel(x)
    text(x(i), hvac_cost(i) + 0.04*(max(hvac_cost)-min(hvac_cost)+eps), ...
        sprintf('$%.2f', hvac_cost(i)), ...
        'HorizontalAlignment','center', ...
        'VerticalAlignment','bottom', ...
        'FontSize',7, ...
        'Color',line_color, ...
        'FontWeight','bold', ...
        'Clipping','off');
end

%% ------------------------------------------------
% 11. Final cleanup
% ------------------------------------------------
set(gca,'LooseInset',max(get(gca,'TightInset'), 0.02))

%% ------------------------------------------------
% 12. Export IEEE PNG
% ------------------------------------------------
set(gcf,'PaperPositionMode','auto')
print(fig,'HVAC_ratio_figure.png','-dpng','-r300')

%% ================================================================
% EXPORT DATA FOR PYTHON / COLAB
% ================================================================

labels_export = {'Cost Opt'; 'Time Opt'; 'Energy Opt'};

HVAC_Cost_Ratio_Percent = cost_ratio(:);
HVAC_Time_Ratio_Percent = time_ratio(:);
HVAC_Cost_USD = hvac_cost(:);

T_export = table( ...
    labels_export, ...
    HVAC_Cost_Ratio_Percent, ...
    HVAC_Time_Ratio_Percent, ...
    HVAC_Cost_USD, ...
    'VariableNames', { ...
    'Label', ...
    'HVAC_Cost_Ratio_Percent', ...
    'HVAC_Time_Ratio_Percent', ...
    'HVAC_Cost_USD'} ...
);

writetable(T_export,'hvac_ratio_export.csv');

disp("Export completed: hvac_ratio_export.csv");