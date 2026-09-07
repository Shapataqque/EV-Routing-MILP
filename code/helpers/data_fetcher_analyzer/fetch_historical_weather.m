% =========================================================================
% SCRIPT: fetch_historical_weather.m
% DESCRIPTION: 
%   1. "Analiz_Sonuclari_Final.xlsx" dosyasını okur (Senin kodunla aynı mantıkta).
%   2. Gerçek GPS koordinatlarını (Lat/Lon) çıkarır.
%   3. Open-Meteo ARŞİVİNDEN 15 Temmuz 2024 (Geçmiş) verisini çeker.
%   4. Sonuçları "Fixed_Weather_Data_15July.xlsx" dosyasına kaydeder.
% =========================================================================
clear; clc;

% --- 1. KOORDİNATLARI EXCEL'DEN ÇEKME (SENİN KODUNUN AYNISI) ---
fprintf('Koordinatlar Excel dosyasından okunuyor...\n');

N = 15; % Toplam düğüm sayısı
filename = 'Analiz_Sonuclari_Final.xlsx';

if ~isfile(filename)
    error('HATA: "%s" dosyası bulunamadı. Lütfen dosyanın bu klasörde olduğundan emin olun.', filename);
end

% Excel Okuma Ayarları
opts = detectImportOptions(filename);
opts.VariableNamingRule = 'preserve';
routeData = readtable(filename, opts);

% Koordinat Dönüştürücü Fonksiyon (DMS -> Decimal)
dms2dec = @(s) sum(str2double(regexp(string(s), '\d+(\.\d+)?', 'match')) .* [1, 1/60, 1/3600]); 

real_coords = zeros(N, 2); % [Latitude, Longitude]

% Döngü ile koordinatları doldur
for k = 1:height(routeData)
    s = routeData.Start(k); 
    e = routeData.End(k);
    
    % Başlangıç Noktası (Eğer henüz atanmadıysa)
    if real_coords(s, 1) == 0
        real_coords(s,1) = dms2dec(routeData.StartLat(k)); 
        real_coords(s,2) = dms2dec(routeData.StartLon(k)); 
    end
    
    % Bitiş Noktası (Eğer henüz atanmadıysa)
    if real_coords(e, 1) == 0
        real_coords(e,1) = dms2dec(routeData.EndLat(k)); 
        real_coords(e,2) = dms2dec(routeData.EndLon(k)); 
    end
end

% Kontrol: Koordinatlar dolu mu?
if any(real_coords(:) == 0)
    warning('Bazı koordinatlar 0 kaldı. Excel dosyasındaki node numaralarını kontrol edin.');
end

fprintf('Koordinatlar başarıyla yüklendi.\n');

% --- 2. HAVA DURUMU API (GEÇMİŞ VERİ - 15 TEMMUZ 2024) ---
target_date = '2024-07-15'; 
fprintf('--- Veri Çekme İşlemi Başlıyor: %s ---\n', target_date);

% Sonuç Matrisi (15 Node x 24 Saat)
weather_matrix = zeros(N, 24);
node_names = cell(N, 1);

for i = 1:N
    lat = real_coords(i, 1);
    lon = real_coords(i, 2);
    
    % Open-Meteo ARCHIVE API
    url = sprintf('https://archive-api.open-meteo.com/v1/archive?latitude=%.4f&longitude=%.4f&start_date=%s&end_date=%s&hourly=temperature_2m', ...
                  lat, lon, target_date, target_date);
    
    try
        fprintf('Node %d (%.4f, %.4f) verisi indiriliyor... ', i, lat, lon);
        data = webread(url);
        
        % İlk 24 saati al
        temps = data.hourly.temperature_2m(1:24);
        weather_matrix(i, :) = temps';
        
        node_names{i} = sprintf('Node_%d', i);
        fprintf('OK (Ort: %.1f C)\n', mean(temps));
        
    catch ME
        fprintf('HATA! API yanıt vermedi. (%s)\n', ME.message);
    end
    
    pause(0.5); % API rate limit yememek için bekleme
end

% --- 3. EXCEL'E KAYDETME ---
T = array2table(weather_matrix);
T.Properties.RowNames = node_names;
T.Properties.VariableNames = "Hour_" + (0:23);

output_filename = 'Fixed_Weather_Data_15July.xlsx';
writetable(T, output_filename, 'WriteRowNames', true);

fprintf('\n>>> İŞLEM TAMAMLANDI. Dosya kaydedildi: %s <<<\n', output_filename);