%% SICAKLIK VERİSİ GÜNCELLEME SCRIPTİ (Open-Meteo)
excelFile = 'Analiz_Sonuclari_Final.xlsx'; 

% Dosyayı oku
try
    data = readtable(excelFile, 'VariableNamingRule', 'preserve');
catch
    error('Excel dosyası bulunamadı!');
end

% Yeni kolon oluştur (Eğer yoksa)
if ~ismember('Tseg_C', data.Properties.VariableNames)
    data.Tseg_C = NaN(height(data), 1);
end

fprintf('Sıcaklık verileri güncelleniyor (%d Rota)...\n', height(data));

for i = 1:height(data)
    try
        % Koordinatları Sayıya Çevir (DMS veya Decimal kontrolü)
        if iscell(data.StartLat) || isstring(data.StartLat)
            lat1 = robustDMS2Dec(string(data{i, 'StartLat'}));
            lon1 = robustDMS2Dec(string(data{i, 'StartLon'}));
            lat2 = robustDMS2Dec(string(data{i, 'EndLat'}));
            lon2 = robustDMS2Dec(string(data{i, 'EndLon'}));
        else
            lat1 = data.StartLat(i); lon1 = data.StartLon(i);
            lat2 = data.EndLat(i);   lon2 = data.EndLon(i);
        end
        
        % --- ORTA NOKTA HESABI ---
        % Yolun ortasındaki hava durumu, tüm segmenti daha iyi temsil eder.
        midLat = (lat1 + lat2) / 2;
        midLon = (lon1 + lon2) / 2;
        
        % API'den Sıcaklığı Çek
        temp = GetCurrentTemperature(midLat, midLon);
        
        % Kaydet
        data.Tseg_C(i) = temp;
        
        fprintf('Rota %d: Orta Nokta (%.2f, %.2f) -> Sıcaklık: %.1f °C\n', i, midLat, midLon, temp);
        
    catch ME
        fprintf('Rota %d HATA: %s\n', i, ME.message);
    end
    
    pause(0.2); % API'ye yüklenmemek için kısa bekleme
end

% Dosyayı kaydet
writetable(data, 'Analiz_Sonuclari_Final_WithWeather.xlsx');
fprintf('İşlem tamam! Yeni dosya: Analiz_Sonuclari_Final_WithWeather.xlsx\n');

%% --- YARDIMCI FONKSİYON (Daha öncekinin aynısı) ---
function decDeg = robustDMS2Dec(dmsStr)
    nums = double(regexp(dmsStr, '\d+', 'match'));
    if length(nums) >= 3
        D = nums(1); M = nums(2); S = nums(3);
        decDeg = D + (M/60) + (S/3600);
        if contains(upper(dmsStr), 'S') || contains(upper(dmsStr), 'W'), decDeg = -decDeg; end
    else
        % Eğer zaten sayıysa (string olarak gelmiş sayı)
        val = str2double(dmsStr);
        if ~isnan(val), decDeg = val; else, error('Format Hatası'); end
    end
end