T = readtable('LMP_PJM_Data_Altered.xlsx', 'VariableNamingRule', 'preserve');

K = 96;
startH = 10;
LMP = zeros(15, K);

for i = 1:15
    rows = T(T.("Node Karşılığı") == i, :);
    rows = sortrows(rows, 'datetime_beginning_ept');
    p24  = rows.total_lmp_rt / 1000;        % $/MWh -> $/kWh

    % Circular shift
    psh = circshift(p24, -startH);

    % Zero-order hold
    for k = 1:K
        hour_idx = floor((k-1) * 24 / K) + 1;
        hour_idx = min(hour_idx, 24);
        LMP(i, k) = psh(hour_idx);
    end
end

% --- X axis ticks ---
tick_slots = 1:8:96;
tick_labels = arrayfun(@(k) ...
    sprintf('%02d:00', mod(floor((k-1)*24/K) + startH, 24)), ...
    tick_slots, 'UniformOutput', false);

% =========================================================
% IEEE SINGLE COLUMN FIGURE SETTINGS
% =========================================================
fig = figure('Units','inches','Position',[1 1 3.5 2.6]); % 3.5 inch width

imagesc(LMP);
colormap(parula);

cb = colorbar;
cb.Label.String = 'LMP ($/kWh)';
cb.FontSize = 8;

yticks(1:15);
yticklabels(string(1:15));

xticks(tick_slots);
xticklabels(tick_labels);
xtickangle(45);

xlabel('Clock time (departure at 10:00)');
ylabel('Node');

set(gca,...
    'FontSize',8,...
    'LineWidth',0.75,...
    'Box','on');

% =========================================================
% EXPORT HIGH QUALITY PNG
% =========================================================
exportgraphics(fig,'Figure_LMP_Heatmap.png',...
    'Resolution',300);