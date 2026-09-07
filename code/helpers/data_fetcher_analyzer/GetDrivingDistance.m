function [dist_km, duration_min] = GetDrivingDistance(lat1, lon1, lat2, lon2)
    % OSRM API: Hem mesafe hem süre çeker
    % OSRM Koordinat sırası: Longitude, Latitude
    
    apiUrl = sprintf('http://router.project-osrm.org/route/v1/driving/%.6f,%.6f;%.6f,%.6f?overview=false', ...
                     lon1, lat1, lon2, lat2);

    options = weboptions('Timeout', 15);
    
    try
        response = webread(apiUrl, options);
        
        if isfield(response, 'routes') && ~isempty(response.routes)
            % Mesafe: Metre -> Kilometre
            dist_km = response.routes(1).distance / 1000;
            
            % Süre: Saniye -> Dakika (API saniye cinsinden verir)
            duration_min = response.routes(1).duration / 60;
        else
            error('Rota bulunamadı.');
        end
        
    catch
        % Hata durumunda NaN (Boş) döndür
        dist_km = NaN;
        duration_min = NaN;
    end
end