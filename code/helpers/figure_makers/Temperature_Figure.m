T = readtable('Fixed_Weather_Data_15July.xlsx','ReadRowNames',true);
M = table2array(T);                        % 15x24
M_sh = circshift(M, -10, 2);              % shift by -10h

orig = 0:23;
tgt  = linspace(0, 23, 96);

nodes = [1, 7, 15];
names = {'Ankara (node 1)', 'Konya (node 7)', 'Antalya (node 15)'};
clrs  = {[0.33 0.29 0.72], [0.73 0.46 0.09], [0.85 0.35 0.19]};

xt    = 0:8:88;
xlbls = arrayfun(@(h) sprintf('%02d:00', mod(h/4+10,24)), xt, 'UniformOutput', false);

% =========================================================
% IEEE SINGLE-COLUMN FIGURE SETTINGS
% =========================================================
fig = figure('Units','inches','Position',[1 1 3.5 2.8]);
hold on; box on;

% Comfort band
patch([0 95 95 0], [20 20 24 24], [0.18 0.62 0.46], ...
    'FaceAlpha', 0.12, ...
    'EdgeColor', [0.06 0.43 0.33], ...
    'LineStyle', '--', ...
    'LineWidth', 0.8, ...
    'DisplayName', 'Comfort band [20--24^\circC]');

% Temperature curves
for k = 1:3
    hi = interp1(orig, M_sh(nodes(k),:), tgt, 'pchip');
    plot(0:95, hi, ...
        'Color', clrs{k}, ...
        'LineWidth', 1.5, ...
        'DisplayName', names{k});
end

xticks(xt);
xticklabels(xlbls);
xtickangle(45);

xlabel('Clock time (departure at 10:00)');
ylabel('Ambient temperature (^ \circC)');

ylim([12 44]);
xlim([0 95]);

grid on;
set(gca, ...
    'FontSize', 8, ...
    'LineWidth', 0.75, ...
    'Box', 'on');

lgd = legend('Location','best');
lgd.FontSize = 7;
lgd.Box = 'off';

% =========================================================
% EXPORT HIGH-QUALITY PNG
% =========================================================
exportgraphics(fig, 'Figure_Temperature_Profile.png', 'Resolution', 300);