%% ==============================================================
%  HELPER: Get 24-Hour Temperature Forecast (API)
%  ==============================================================
function temp_24h = get_weather_forecast_24h(lat, lon)
    % Fetches hourly temperature forecast for the next 24 hours via Open-Meteo.
    % Inputs:
    %   lat, lon: Latitude and Longitude (Decimal degrees)
    % Output:
    %   temp_24h: 1x24 double vector (Celsius)

    % API URL: Request hourly temperature for 1 forecast day
    apiUrl = sprintf('https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f&hourly=temperature_2m&forecast_days=1', lat, lon);
    
    options = weboptions('Timeout', 15);
    
    try
        % Send Request
        data = webread(apiUrl, options);
        
        % Extract hourly data
        if isfield(data, 'hourly') && isfield(data.hourly, 'temperature_2m')
            raw_temp = data.hourly.temperature_2m;
            
            % Ensure we get exactly 24 hours (API might return 24 or 48 depending on time)
            if length(raw_temp) >= 24
                temp_24h = raw_temp(1:24)'; % Transpose to row vector
            else
                % Pad with NaNs if API returns insufficient data
                temp_24h = [raw_temp', nan(1, 24-length(raw_temp))];
            end
        else
            error('JSON structure mismatch: "hourly" field missing.');
        end
        
    catch 
        % Fallback mechanism in case of connection error
        warning('Weather API Error for location [%.2f, %.2f]. Using default profile.', lat, lon);
        % Return a default curve (e.g., 15C night, 25C day)
        temp_24h = [15,15,14,14,13,13,14,16,18,20,22,24,25,25,24,23,21,20,19,18,17,16,16,15];
    end
end