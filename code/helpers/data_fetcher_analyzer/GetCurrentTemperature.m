function temp_C = GetCurrentTemperature(lat, lon)
    % Open-Meteo API kullanarak anlık sıcaklığı (2 metre yükseklikte) çeker.
    % API Key gerektirmez.
    
    % URL Oluşturma
    apiUrl = sprintf('https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f&current=temperature_2m', lat, lon);
    
    options = weboptions('Timeout', 15);
    
    try
        % Veriyi çek
        data = webread(apiUrl, options);
        
        % JSON yapısından sıcaklığı al
        if isfield(data, 'current') && isfield(data.current, 'temperature_2m')
            temp_C = data.current.temperature_2m;
        else
            error('Sıcaklık verisi bulunamadı.');
        end
        
    catch
        % Hata durumunda NaN döndür
        temp_C = NaN;
    end