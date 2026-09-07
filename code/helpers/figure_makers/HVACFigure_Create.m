T = 10:0.1:35;
P = zeros(size(T));

Tset  = 22;
Ttol  = 2;
Pbase = 0.3;
ah    = 0.12;
ac    = 0.08;
Phmax = 5.0;
Pcmax = 3.0;

for k = 1:length(T)
    if T(k) < Tset - Ttol
        dT = (Tset - Ttol) - T(k);
        P(k) = min(ah*dT^2 + Pbase, Phmax);
    elseif T(k) > Tset + Ttol
        dT = T(k) - (Tset + Ttol);
        P(k) = min(ac*dT^2 + Pbase, Pcmax);
    else
        P(k) = Pbase;
    end
end

% ---------------------------
% IEEE single-column settings
% ---------------------------
figW = 3.5;   % inches (IEEE single column width)
figH = 2.6;   % inches

f = figure('Units','inches', ...
           'Position',[1 1 figW figH], ...
           'Color','w');

ax = axes(f);
hold(ax, 'on');

% Comfort band shading
patch(ax, ...
    [Tset-Ttol Tset+Ttol Tset+Ttol Tset-Ttol], ...
    [0 0 6 6], ...
    [0.85 0.95 0.85], ...
    'EdgeColor','none', ...
    'FaceAlpha',0.45);

% Main curve
plot(ax, T, P, 'k-', 'LineWidth', 1.6);

% Capacity lines
yline(ax, Phmax, '--', 'Heating cap: 5.0 kW', ...
    'Color', [0.75 0.30 0.10], ...
    'LineWidth', 1.0, ...
    'FontSize', 7, ...
    'LabelHorizontalAlignment','left');

yline(ax, Pcmax, '--', 'Cooling cap: 3.0 kW', ...
    'Color', [0.20 0.45 0.75], ...
    'LineWidth', 1.0, ...
    'FontSize', 7, ...
    'LabelHorizontalAlignment','left');

% Tolerance boundaries
xline(ax, Tset-Ttol, '--', 'Color', [0.10 0.55 0.35], 'LineWidth', 1.0);
xline(ax, Tset+Ttol, '--', 'Color', [0.10 0.55 0.35], 'LineWidth', 1.0);

% Labels
xlabel(ax, 'Ambient temperature (^oC)', 'FontSize', 8, 'FontName', 'Times New Roman');
ylabel(ax, 'HVAC power demand (kW)', 'FontSize', 8, 'FontName', 'Times New Roman');

% Axes formatting
xlim(ax, [10 35]);
ylim(ax, [0 6]);
grid(ax, 'on');
box(ax, 'on');

set(ax, ...
    'FontName', 'Times New Roman', ...
    'FontSize', 8, ...
    'LineWidth', 0.8, ...
    'TickDir', 'out', ...
    'Layer', 'top');

% Reduce extra whitespace
ax.Position = [0.16 0.18 0.78 0.75];

% ---------------------------
% Export as 300 DPI PNG
% ---------------------------
exportgraphics(f, 'hvac_power_ieee_singlecolumn_300dpi.png', ...
    'Resolution', 300, ...
    'BackgroundColor', 'white');