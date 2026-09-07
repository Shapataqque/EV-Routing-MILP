%% ================================================================
% FILE: seasonal_route_comparison_temperature_heatmap_ieee.m
%
% PURPOSE:
%   Compare Energy-Optimal routes:
%   Summer vs Winter
%
%   Background:
%       Spatial ambient-temperature field
%       Blue = colder
%       Red  = warmer
%
%   Route:
%       Energy-optimal route superimposed on temperature field
%
% REQUIREMENT:
%   Run the main model first so that:
%
%       data_fixed
%       data_winter
%
%   exist in the workspace.
%
% OUTPUT:
%   fig_Seasonal_Routes_Temperature_Heatmap.png
%   fig_Seasonal_Routes_Temperature_Heatmap.pdf
%
% ================================================================

clc;
close all;


%% ------------------------------------------------
% 1. CHECK DATA
% ------------------------------------------------

if ~exist('data_fixed','var') || ...
        ~isfield(data_fixed,'coords') || ...
        ~isfield(data_fixed,'Tseg')

    error(['data_fixed.coords or data_fixed.Tseg was not found. ' ...
        'Run the main EV-routing model first.']);

end

if ~exist('data_winter','var') || ...
        ~isfield(data_winter,'Tseg')

    error(['data_winter.Tseg was not found. ' ...
        'Run the main EV-routing model first.']);

end


coords = data_fixed.coords;

N = size(coords,1);


%% ------------------------------------------------
% 2. SEASONAL ENERGY-OPTIMAL ROUTES
% ------------------------------------------------

route_summer = [1 2 11 14 15];

route_winter = [1 2 6 12 15];


%% ------------------------------------------------
% 3. CALCULATE ONE REPRESENTATIVE TEMPERATURE
%    FOR EACH NODE
% ------------------------------------------------
%
% Tseg(i,j,k) contains the temperature associated with
% an existing arc i->j at time slot k.
%
% For the spatial heatmap, calculate the mean temperature
% associated with each destination node over all:
%
%       incoming existing arcs
%       time slots
%
% This creates one representative 24-h mean temperature
% for each node.
%
% ------------------------------------------------

T_summer_node = ...
    calculate_node_mean_temperature( ...
        data_fixed);

T_winter_node = ...
    calculate_node_mean_temperature( ...
        data_winter);


%% ------------------------------------------------
% 4. PRINT NODE TEMPERATURES
% ------------------------------------------------

fprintf('\n====================================================\n');
fprintf('MEAN NODE TEMPERATURES\n');
fprintf('====================================================\n');

fprintf('\nNode     Summer (C)     Winter (C)\n');

for n = 1:N

    fprintf( ...
        '%2d       %8.2f       %8.2f\n', ...
        n, ...
        T_summer_node(n), ...
        T_winter_node(n));

end


%% ------------------------------------------------
% 5. COMMON SPATIAL LIMITS
% ------------------------------------------------

all_x = coords(:,1);
all_y = coords(:,2);

xmin = min(all_x) - 5;
xmax = max(all_x) + 5;

ymin = min(all_y) - 5;
ymax = max(all_y) + 5;


%% ------------------------------------------------
% 6. INTERPOLATION GRID
% ------------------------------------------------

grid_resolution = 250;

x_grid_vector = ...
    linspace(xmin, xmax, grid_resolution);

y_grid_vector = ...
    linspace(ymin, ymax, grid_resolution);

[Xq, Yq] = meshgrid( ...
    x_grid_vector, ...
    y_grid_vector);


%% ------------------------------------------------
% 7. BUILD SUMMER TEMPERATURE FIELD
% ------------------------------------------------

F_summer = scatteredInterpolant( ...
    coords(:,1), ...
    coords(:,2), ...
    T_summer_node, ...
    'natural', ...
    'nearest');

Tq_summer = ...
    F_summer(Xq, Yq);


%% ------------------------------------------------
% 8. BUILD WINTER TEMPERATURE FIELD
% ------------------------------------------------

F_winter = scatteredInterpolant( ...
    coords(:,1), ...
    coords(:,2), ...
    T_winter_node, ...
    'natural', ...
    'nearest');

Tq_winter = ...
    F_winter(Xq, Yq);


%% ------------------------------------------------
% 9. COMMON COLOR SCALE
% ------------------------------------------------
%
% IMPORTANT:
%
% Both panels use the SAME temperature-color relationship.
% Otherwise red in winter and red in summer could represent
% completely different temperatures.
%
% ------------------------------------------------

all_temperatures = [ ...
    T_summer_node(:); ...
    T_winter_node(:)];

color_min = floor(min(all_temperatures));
color_max = ceil(max(all_temperatures));

fprintf('\nCommon color scale: %.1f C to %.1f C\n', ...
    color_min, color_max);


%% ------------------------------------------------
% 10. FIGURE SETTINGS
% ------------------------------------------------

fig_w = 7.16;       % IEEE double-column width [inch]
fig_h = 3.25;

f = figure( ...
    'Color','w', ...
    'Units','inches', ...
    'Position',[1 1 fig_w fig_h], ...
    'PaperPositionMode','auto');


tl = tiledlayout( ...
    f, ...
    1,2, ...
    'Padding','compact', ...
    'TileSpacing','compact');


%% ------------------------------------------------
% 11. SUMMER PANEL
% ------------------------------------------------

ax1 = nexttile(tl);

plot_route_temperature_panel( ...
    ax1, ...
    coords, ...
    route_summer, ...
    N, ...
    Xq, ...
    Yq, ...
    Tq_summer, ...
    T_summer_node, ...
    [color_min color_max], ...
    'Summer -- July 15, 2025');


%% ------------------------------------------------
% 12. WINTER PANEL
% ------------------------------------------------

ax2 = nexttile(tl);

plot_route_temperature_panel( ...
    ax2, ...
    coords, ...
    route_winter, ...
    N, ...
    Xq, ...
    Yq, ...
    Tq_winter, ...
    T_winter_node, ...
    [color_min color_max], ...
    'Winter -- January 15, 2025');


%% ------------------------------------------------
% 13. KEEP PANELS IDENTICAL
% ------------------------------------------------

xlim(ax1,[xmin xmax]);
xlim(ax2,[xmin xmax]);

ylim(ax1,[ymin ymax]);
ylim(ax2,[ymin ymax]);

axis(ax1,'equal');
axis(ax2,'equal');


%% ------------------------------------------------
% 14. BLUE -> RED COLORMAP
% ------------------------------------------------
%
% Custom scientific blue-white-red colormap.
%
% Cold:
%       blue
%
% Middle:
%       near-white
%
% Hot:
%       red
%
% ------------------------------------------------

n_colors = 256;

blue = [ ...
    0.00, ...
    0.25, ...
    0.80];

white = [ ...
    0.96, ...
    0.96, ...
    0.96];

red = [ ...
    0.85, ...
    0.10, ...
    0.05];


half_n = floor(n_colors / 2);


blue_to_white = [ ...
    linspace(blue(1), white(1), half_n)', ...
    linspace(blue(2), white(2), half_n)', ...
    linspace(blue(3), white(3), half_n)'];


white_to_red = [ ...
    linspace(white(1), red(1), n_colors-half_n)', ...
    linspace(white(2), red(2), n_colors-half_n)', ...
    linspace(white(3), red(3), n_colors-half_n)'];


temperature_colormap = [ ...
    blue_to_white; ...
    white_to_red];


colormap(f, temperature_colormap);


%% ------------------------------------------------
% 15. COMMON COLORBAR
% ------------------------------------------------

cb = colorbar(ax2);

cb.Layout.Tile = 'east';

cb.Label.String = ...
    'Mean Ambient Temperature (°C)';

cb.Label.FontSize = 7;

cb.FontSize = 7;


%% ------------------------------------------------
% 16. EXPORT
% ------------------------------------------------

png_file = ...
    'fig_Seasonal_Routes_Temperature_Heatmap.png';

pdf_file = ...
    'fig_Seasonal_Routes_Temperature_Heatmap.pdf';


exportgraphics( ...
    f, ...
    png_file, ...
    'Resolution',300);


exportgraphics( ...
    f, ...
    pdf_file, ...
    'ContentType','vector');


disp(['Saved: ' png_file]);
disp(['Saved: ' pdf_file]);


fprintf('\nSeasonal Energy-Optimal Routes\n');

fprintf('Summer : ');
fprintf('%d ',route_summer);
fprintf('\n');

fprintf('Winter : ');
fprintf('%d ',route_winter);
fprintf('\n');


%% ================================================================
% LOCAL FUNCTION:
% CALCULATE MEAN TEMPERATURE PER NODE
% ================================================================

function node_temperature = ...
    calculate_node_mean_temperature(data)

    N = data.N;
    K = data.Tslots;

    node_temperature = ...
        NaN(N,1);


    for j = 1:N

        temperature_values = [];


        %% Find incoming existing arcs i -> j
        for i = 1:N

            if data.A(i,j) == 1

                values = squeeze( ...
                    data.Tseg(i,j,1:K));

                values = values( ...
                    isfinite(values));

                temperature_values = [ ...
                    temperature_values; ...
                    values(:)]; %#ok<AGROW>

            end

        end


        %% --------------------------------------------------------
        % Origin normally has no incoming route arc.
        %
        % If no incoming temperature exists, use temperatures
        % associated with outgoing arcs instead.
        %% --------------------------------------------------------

        if isempty(temperature_values)

            for m = 1:N

                if data.A(j,m) == 1

                    values = squeeze( ...
                        data.Tseg(j,m,1:K));

                    values = values( ...
                        isfinite(values));

                    temperature_values = [ ...
                        temperature_values; ...
                        values(:)]; %#ok<AGROW>

                end

            end

        end


        %% Mean representative node temperature
        if ~isempty(temperature_values)

            node_temperature(j) = ...
                mean(temperature_values);

        end

    end


    %% Safety check
    if any(~isfinite(node_temperature))

        error([ ...
            'A representative temperature could not be ' ...
            'calculated for every node.']);

    end

end


%% ================================================================
% LOCAL FUNCTION:
% PLOT ROUTE + TEMPERATURE FIELD
% ================================================================

function plot_route_temperature_panel( ...
    ax, ...
    coords, ...
    route, ...
    N, ...
    Xq, ...
    Yq, ...
    temperature_field, ...
    node_temperatures, ...
    color_limits, ...
    panel_title)


    hold(ax,'on');


    %% ------------------------------------------------------------
    % 1. TEMPERATURE FIELD
    % ------------------------------------------------------------

    h_temp = imagesc( ...
        ax, ...
        Xq(1,:), ...
        Yq(:,1), ...
        temperature_field);


    %% Correct Y direction after imagesc
    set(ax, ...
        'YDir','normal');


    %% Slight transparency
    h_temp.AlphaData = 0.72;


    %% Same color limits
    clim(ax, color_limits);


    %% ------------------------------------------------------------
    % 2. NETWORK NODES
    % ------------------------------------------------------------

    scatter( ...
        ax, ...
        coords(:,1), ...
        coords(:,2), ...
        25, ...
        'k', ...
        'filled');


    %% ------------------------------------------------------------
    % 3. ENERGY-OPTIMAL ROUTE
    % ------------------------------------------------------------

    plot( ...
        ax, ...
        coords(route,1), ...
        coords(route,2), ...
        '-o', ...
        'LineWidth',2.0, ...
        'MarkerSize',5, ...
        'MarkerFaceColor','w', ...
        'Color',[0.95 0.45 0.05]);


    %% ------------------------------------------------------------
    % 4. NODE NUMBERS
    % ------------------------------------------------------------

    for n = 1:N

        text( ...
            ax, ...
            coords(n,1)+1.0, ...
            coords(n,2)+1.0, ...
            sprintf('%d',n), ...
            'FontSize',6.5, ...
            'FontWeight','bold', ...
            'HorizontalAlignment','left', ...
            'VerticalAlignment','bottom', ...
            'Color','k');

    end


    %% ------------------------------------------------------------
    % 5. OPTIONAL NODE TEMPERATURE VALUES
    % ------------------------------------------------------------
    %
    % Comment this block if the figure becomes too crowded.
    %
    % ------------------------------------------------------------

    for n = 1:N

        text( ...
            ax, ...
            coords(n,1)+1.0, ...
            coords(n,2)-2.0, ...
            sprintf('%.1f°', ...
                node_temperatures(n)), ...
            'FontSize',5.5, ...
            'HorizontalAlignment','left', ...
            'VerticalAlignment','top', ...
            'Color',[0.15 0.15 0.15]);

    end


    %% ------------------------------------------------------------
    % 6. ORIGIN AND DESTINATION
    % ------------------------------------------------------------

    scatter( ...
        ax, ...
        coords(route(1),1), ...
        coords(route(1),2), ...
        45, ...
        'k', ...
        'filled');


    scatter( ...
        ax, ...
        coords(route(end),1), ...
        coords(route(end),2), ...
        45, ...
        'k', ...
        'filled');


    %% ------------------------------------------------------------
    % 7. FORMATTING
    % ------------------------------------------------------------

    grid(ax,'on');
    box(ax,'on');

    title( ...
        ax, ...
        panel_title, ...
        'FontSize',8, ...
        'FontWeight','bold');

    xlabel(ax,'');
    ylabel(ax,'');

    ax.FontSize = 7;
    ax.LineWidth = 0.7;

    ax.GridAlpha = 0.20;

end