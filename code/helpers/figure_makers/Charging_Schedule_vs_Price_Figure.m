%% ================================================================
% FILE: Charging_Schedule_vs_Price_Figure_IEEE.m
% PURPOSE:
%   Generate 3 separate IEEE-style single-column figures:
%   1) Cost Objective
%   2) Time Objective
%   3) Energy Objective
%
%   Line : Electricity price
%   Bars : Charging activity
%
%   X-axis limited to 20:00
%   Each figure is exported as 300 DPI PNG
% ================================================================

%% ------------------------------------------------
% 1. Get results from workspace
% ------------------------------------------------
if ~exist('results_list','var') || numel(results_list) < 2 || isempty(results_list{2})
    error('results_list{2} not found. Run the main script first.');
end

if ~exist('data_fixed','var')
    error('data_fixed not found. Run the main script first.');
end

res  = results_list{2};   % Fixed dataset results
data = data_fixed;

sol_cost   = res.sol_cost;
sol_time   = res.sol_time;
sol_energy = res.sol_energy;

%% ------------------------------------------------
% 2. Time settings
% ------------------------------------------------
K  = data.Tslots;
dt = data.dt_h;

% Simulation time axis in hours from start
t_hours = (0:K-1) * dt;

% Real clock time corresponding to each slot
real_clock = mod(data.start_hour + t_hours, 24);

% Keep plot until first slot reaching/exceeding 20:00
idx_end = find(real_clock >= 20, 1, 'first');

if isempty(idx_end)
    idx_end = length(t_hours);
end

t_plot = t_hours(1:idx_end);

% Average price across all nodes for each slot
price_curve = mean(data.LMP, 1);
price_plot  = price_curve(1:idx_end);

%% ------------------------------------------------
% 3. Plot separate figures
% ------------------------------------------------
plot_one_objective(sol_cost, data, t_plot, price_plot, idx_end, ...
    'Temporal Alignment of Charging Activity with Electricity Price (Cost Objective)', ...
    'Charging_Schedule_vs_Price_Cost_Objective');

plot_one_objective(sol_time, data, t_plot, price_plot, idx_end, ...
    'Temporal Alignment of Charging Activity with Electricity Price (Time Objective)', ...
    'Charging_Schedule_vs_Price_Time_Objective');

plot_one_objective(sol_energy, data, t_plot, price_plot, idx_end, ...
    'Temporal Alignment of Charging Activity with Electricity Price (Energy Objective)', ...
    'Charging_Schedule_vs_Price_Energy_Objective');

%% ================================================================
% LOCAL FUNCTION
% ================================================================
function plot_one_objective(solution, data, t_plot, price_plot, idx_end, figTitle, figName)

    dt = data.dt_h;

    if ~isfield(solution, 'Eik') || isempty(solution.Eik)
        error('solution.Eik missing for figure: %s', figName);
    end

    %% ------------------------------------------------
    % IEEE Figure settings
    % ------------------------------------------------
    fig_w = 3.5;   % inches, IEEE single-column width
    fig_h = 2.6;   % compact height

    fs_axis   = 7;
    fs_title  = 8;
    fs_legend = 6;

    f = figure('Name', figName, ...
               'Color', 'w', ...
               'Units', 'inches', ...
               'Position', [1 1 fig_w fig_h], ...
               'PaperUnits', 'inches');

    %% ------------------------------------------------
    % Charging activity from solution
    % ------------------------------------------------
    % Eik(i,k): charged energy at node i during slot k
    charging_energy_per_slot = sum(solution.Eik, 1);   % kWh per slot
    charging_energy_per_slot = charging_energy_per_slot(1:idx_end);

    % Convert to kW-equivalent activity for visualization
    charging_power_equiv = charging_energy_per_slot / dt;

    %% ------------------------------------------------
    % X ticks every 2 hours + final endpoint
    % ------------------------------------------------
    x_tick_vals = 0:2:t_plot(end);
    if isempty(x_tick_vals) || x_tick_vals(end) ~= t_plot(end)
        x_tick_vals = unique([x_tick_vals, t_plot(end)]);
    end

    x_tick_labels = strings(size(x_tick_vals));
    for k = 1:length(x_tick_vals)
        real_h = mod(data.start_hour + x_tick_vals(k), 24);
        x_tick_labels(k) = sprintf('%02d:00', floor(real_h));
    end

    %% ------------------------------------------------
    % Plot
    % ------------------------------------------------
    % Draw bars first so line stays on top
    yyaxis right
    b = bar(t_plot, charging_power_equiv, 1.0, ...
        'FaceColor', [0.2 0.55 0.85], ...
        'EdgeColor', 'none');
    b.FaceAlpha = 0.35;
    ylabel('Charging Activity (kW)', 'FontSize', fs_axis);
    hold on

    % Draw price line second
    yyaxis left
    p = plot(t_plot, price_plot, 'k-', 'LineWidth', 1.6);
    ylabel('Electricity Price ($/kWh)', 'FontSize', fs_axis);

    xlabel('Time', 'FontSize', fs_axis);
    title(figTitle, 'FontSize', fs_title, 'FontWeight', 'bold');

    xlim([t_plot(1), t_plot(end)]);
    xticks(x_tick_vals);
    xticklabels(x_tick_labels);
    xtickangle(30);

    set(gca, 'FontSize', fs_axis, 'LineWidth', 0.8);

    grid on
    box on

    legend([p b], {'Electricity Price','Charging Activity'}, ...
        'Location', 'northwest', ...
        'FontSize', fs_legend, ...
        'Box', 'on');

    %% ------------------------------------------------
    % Export IEEE PNG (300 DPI)
    % ------------------------------------------------
    set(f, 'PaperPositionMode', 'auto');
    print(f, [figName '.png'], '-dpng', '-r300');
end