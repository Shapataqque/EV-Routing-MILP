function [totalGain, totalLoss, elevations] = getRouteElevation(lat1, lon1, lat2, lon2, numSamples)
    % lat1, lon1: Başlangıç koordinatları
    % lat2, lon2: Bitiş koordinatları
    % numSamples: Yol boyunca kaç noktadan örnek alınacağı (Örn: 20-50 arası idealdir)

    % 1. Yol Boyunca Örnek Koordinatlar Oluştur (Interpolation)
    lats = linspace(lat1, lat2, numSamples);
    lons = linspace(lon1, lon2, numSamples);
    
    % 2. API Sorgu Formatını Hazırla (Open Topo Data - Mapzen veri seti)
    % Format: https://api.opentopodata.org/v1/mapzen?locations=lat1,lon1|lat2,lon2|...
    coords_str = "";
    for i = 1:numSamples
        coords_str = coords_str + sprintf("%.6f,%.6f", lats(i), lons(i));
        if i < numSamples, coords_str = coords_str + "|"; end
    end
    
    apiUrl = "https://api.opentopodata.org/v1/mapzen?locations=" + coords_str;
    
    % 3. Veriyi İnternetten Çek
    try
        options = weboptions('Timeout', 15);
        response = webread(apiUrl, options);
        elevations = [response.results.elevation];
        
        % 4. Tırmanış ve İnişleri Hesapla
        diffs = diff(elevations); % Ardışık noktalar arası fark
        totalGain = sum(diffs(diffs > 0)); % Pozitif farkların toplamı
        totalLoss = abs(sum(diffs(diffs < 0))); % Negatif farkların toplamı
        
    catch ME
        fprintf('Hata: Veri çekilemedi. İnternet bağlantısını veya API limitini kontrol edin.\n');
        totalGain = 0; totalLoss = 0; elevations = [];
    end
end
