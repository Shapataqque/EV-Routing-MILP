% ------------------------------------------------------------------------------
% SECTION X: ROUTE VISUALIZATION (IEEE SINGLE COLUMN - 300 DPI)
% ------------------------------------------------------------------------------

scenario_idx = 2;   % 1: Real-time, 2: Summer, 3: Winter

res  = results_list{scenario_idx};
data = dataset_list{scenario_idx};

route_cost     = res.route_cost;
route_time     = res.route_time;
route_energy   = res.route_energy;
route_distance = res.route_dist;

figure('Units','inches','Position',[1 1 3.5 2.8]);  % IEEE single column width
hold on; grid on;

% --- Coordinates
x = data.coords(:,1);
y = data.coords(:,2);

% --- Plot nodes
scatter(x, y, 25, 'k', 'filled');

% --- Label nodes (slightly offset)
for i = 1:length(x)
    text(x(i)+1, y(i)+1, num2str(i), ...
        'FontSize',6,'FontWeight','bold');
end

% --- Plot routes
plot(x(route_cost),     y(route_cost),     'r',  'LineWidth',1.5);
plot(x(route_time),     y(route_time),     'b',  'LineWidth',1.5);
plot(x(route_energy),   y(route_energy),   'g',  'LineWidth',1.5);
plot(x(route_distance), y(route_distance), 'k--','LineWidth',1.5);

% --- Legend (compact IEEE style)
legend({'Nodes','Cost','Time','Energy','Distance'}, ...
       'Location','best','FontSize',6);

% --- Title
title(['Routing Comparison'], 'FontSize',7);

% --- Axis settings
axis equal
set(gca,'FontSize',6)

% --- Tight margins
set(gca,'LooseInset',get(gca,'TightInset'))

% --- Export (IEEE quality)
set(gcf,'PaperPositionMode','auto')

print(gcf,'route_comparison_ieee','-dpng','-r300')   % PNG 300 DPI