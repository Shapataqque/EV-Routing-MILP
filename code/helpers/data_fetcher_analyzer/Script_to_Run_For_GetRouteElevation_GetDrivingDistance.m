%% 1. Veri Yükleme ve Ayarlar
excelFile = 'Topography_API_Routes.xlsx'; 
data = readtable(excelFile, 'VariableNamingRule', 'preserve');

% Parametreler
numSamples = 50; 
base_rate = 0.18;      
climb_penalty = 0.008; 
descent_bonus = 0.004; 

% Kolonları NaN (Boş) olarak başlat
data.Distance_km = NaN(height(data), 1);
data.TravelTime_min = NaN(height(data), 1); % Yeni eklenen sütun
data.TotalGain = NaN(height(data), 1);
data.TotalLoss = NaN(height(data), 1);
data.CalculatedE0 = NaN(height(data), 1);

fprintf('Analiz başlatıldı. Toplam %d rota işlenecek...\n', height(data));

%% 2. Döngü İçinde Veri İşleme
for i = 1:height(data)
    try
        % Excel sütun isimlerine göre veriyi al
        sLat = string(data{i, 'StartLat'});
        sLon = string(data{i, 'StartLon'});
        eLat = string(data{i, 'EndLat'});
        eLon = string(data{i, 'EndLon'}); 
        
        % Metin koordinatları ondalık sayıya çevir
        lat1 = robustDMS2Dec(sLat);
        lon1 = robustDMS2Dec(sLon);
        lat2 = robustDMS2Dec(eLat);
        lon2 = robustDMS2Dec(eLon);
        
        fprintf('Rota %d (%d -> %d): ', i, data.Start(i), data.End(i));
        
        % --- ADIM A: Mesafe ve Süre Çekme ---
        % Güncellediğin fonksiyon hem dist_km hem duration_min döner
        [dist_km, duration_min] = GetDrivingDistance(lat1, lon1, lat2, lon2);
        
        % Verileri tabloya işle (Hata varsa zaten NaN gelecek)
        data.Distance_km(i) = dist_km;
        data.TravelTime_min(i) = duration_min;
        
        % --- ADIM B: Rakım Çekme ---
        % Not: Dosya isminin 'GetRouteElevation.m' olduğundan emin ol
        [gain, loss, ~] = GetRouteElevation(lat1, lon1, lat2, lon2, numSamples);
        data.TotalGain(i) = gain;
        data.TotalLoss(i) = loss;
        
        % --- ADIM C: Enerji Hesabı ---
        % MATLAB'de herhangi bir sayı NaN ile toplanırsa sonuç NaN olur.
        % Bu yüzden ekstra if-else kontrolüne gerek kalmadan, veri eksikse E0 otomatik NaN olur.
        E0 = (dist_km * base_rate) + (gain * climb_penalty) - (loss * descent_bonus);
        data.CalculatedE0(i) = E0;
        
        % Konsola Bilgi Yazdır
        if ~isnan(E0)
            fprintf('BAŞARILI (%.1f km, %.1f dk, E0: %.2f kWh)\n', dist_km, duration_min, E0);
        else
            fprintf('VERİ EKSİK (NaN atandı)\n');
        end
        
    catch ME
        fprintf('KRİTİK HATA! (%s)\n', ME.message);
    end
    
    pause(1.5); % API limitlerini aşmamak için güvenli bekleme
end

%% 3. Kaydetme
writetable(data, 'Analiz_Sonuclari_Final.xlsx');
fprintf('\nİşlem bitti. "Analiz_Sonuclari_Final.xlsx" dosyasını kontrol ediniz.\n');

%% --- YARDIMCI FONKSİYON: DMS -> DECIMAL ---
function decDeg = robustDMS2Dec(dmsStr)
    % Metindeki rakamları ayıkla
    nums = double(regexp(dmsStr, '\d+', 'match'));
    
    if length(nums) >= 3
        D = nums(1);
        M = nums(2);
        S = nums(3);
        decDeg = D + (M/60) + (S/3600);
        
        % Yön kontrolü (Güney veya Batı ise negatif yap)
        if contains(upper(dmsStr), 'S') || contains(upper(dmsStr), 'W')
            decDeg = -decDeg;
        end
    else
        error('Koordinat verisi (DMS) tam okunamadı.');
    end
end