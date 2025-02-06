function Mechanism = RMSE(Mechanism, fileToSpeedMap, sensorDataTypes, sensorSourceMap, sensorInputMap, sensorDataFlipMap, pullColumnDataMap)
% TODO: Make sure to insert the processFunctions in as an argument and
% utilize this within code
Mechanism = RMSEUtils.RMSESolver(Mechanism, fileToSpeedMap, sensorDataTypes, sensorSourceMap, sensorInputMap, sensorDataFlipMap, pullColumnDataMap, @calculateRMSE, @determineAdjustment, @determineOffset, @determineMap);
end

function rmse = calculateRMSE(expDataSet, theoDataSet, sensor, sensorSourceMap, sensorInputMap, sensorDataFlipMap, pullColumnDataMap, determineMap, fileToSpeedMap, dataType, file, determineAdjustment, determineOffset)
% Calculate RMSE for a specific sensor, data type, and speed
    % Args:
    % - expDataSet, theoDataSet: Experimental and theoretical data sets
    % - sensor, dataType, speed: Sensor name, data type, and speed

    % Retrieve data
    expData = RMSEUtils.retrieveExpData(expDataSet, sensor, sensorSourceMap, sensorInputMap, sensorDataFlipMap, pullColumnDataMap, determineMap, dataType, file);
    theoData = RMSEUtils.retrieveTheoData(theoDataSet, expData, sensor, dataType, file, determineAdjustment, determineOffset, fileToSpeedMap);

    % Validate data
    if isempty(expData) || isempty(theoData)
        error('Missing experimental or theoretical data');
    end

    % Interpolate theoretical data to experimental timestamps
    timestamps = expData.Time;
    interpolatedTheoData = interp1(theoData.Time, theoData.Values, timestamps, 'linear', 'extrap');

    % Remove outliers
    [filteredExpData, filteredTheoData] = RMSEUtils.removeOutliers(expData.Values, interpolatedTheoData);

    % Compute RMSE
    if isempty(filteredExpData)
        error('All data points were considered outliers');
    end
    rmse = sqrt(mean((filteredExpData - filteredTheoData).^2));

    % Generate and save the figure
    RMSEUtils.generateAndSaveFigure(timestamps, expData.Values, theoData.Time, theoData.Values, interpolatedTheoData, sensor, dataType, file, fileToSpeedMap);
end

function [selectedMap, letterMap] = determineMap(rawData, SENSOR_ID_COL)
end

function adjustment = determineAdjustment(sensor, theoData, actualData)
end

function offset = determineOffset(sensor, theoDataArray, adjustmentVal)
end
