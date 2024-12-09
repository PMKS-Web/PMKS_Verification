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


% TODO: Put the logic here for pulling the respective column for
% WitMotion/CoolTerm/PythonGraphs

% function coolTermData = processCoolTermData(rawData, sensorType, dataType)
% % Define sensor columns for angles and angular velocities
% sensorColumnsMap = containers.Map(...
%     {'G', 'F', 'E'}, ...
%     {struct('AngVel', 4, 'Angle', 5:7), ...
%     struct('Angle', 8:10, 'AngVel', 11:13), ...
%     struct('Angle', 14:16, 'AngVel', 17:19)});
% columns = sensorColumnsMap(sensorType).(dataType);
% 
% binarySignal = rawData.Var3;  % Adjust 'Var3' to the correct variable name if different
% 
% % Identify valid data segments based on binary signals
% zeroIndices = find(binarySignal == 0);
% validSegments = find(diff(zeroIndices) > 1);  % Find non-consecutive ones
% 
% if isempty(validSegments) || length(validSegments) < 2
%     error('Valid data segments not found.');
% end
% 
% % TODO: Make sure to utilize the correct zeroIndex
% 
% % Define the range for valid data based on identified segments
% validStartIndex = zeroIndices(validSegments(1));
% validEndIndex = zeroIndices(validSegments(2));
% 
% % Extract the valid data range
% validData = rawData(validStartIndex+1:validEndIndex, :);
% 
% % Compare extracted data with theoretical data for further refinement
% % comparisonResults = compareData(validData(:, columns), theoData);
% % refinedDataIndices = find(comparisonResults);  % Rows closely matching theoretical data
% % TODO: Get the column that closely match the theoretical data
% % refinedDataIndices = validData(:,columns(1));
% 
% % Define map for selecting the correct Y column index based on sensor and dataType
% yColumnMap = containers.Map(...
%     {'GAngVel', 'GAngle', 'FAngle', 'FAngVel', 'EAngle', 'EAngVel', }, ...
%     {1, 2, 3, 1, 3, 1});
% % {1, 2, 1, 3, 1, 3});
% 
% % Get the correct Y column index using the map
% yColumnIndex = columns(yColumnMap([sensorType dataType]));
% 
% YData = validData(:, yColumnIndex);
% XData = validData(:, 2);
% % Refine data by ensuring continuity and removing spikes (maybe do later)
% % refinedData = validData(refinedDataIndices, :);
% % continuousData = removeSpikes(refinedData, columns);
% 
% % witMotionData = struct();
% witMotionData.Time = table2array(XData);
% % Determine the actual start time by utilizing interpolation to find
% % the starting theoretical where the input link is 0
% 
% x = [rawData{validStartIndex,10}, rawData{validStartIndex+1,10}];  % Example angles in degrees
% 
% % Define the corresponding y values (times) as duration type
% y = [rawData{validStartIndex,2}, rawData{validStartIndex+1,2}];  % Example times
% 
% % Define the x value at which you want to interpolate
% xq = 0;  % Instance where input link starts at 0 degree angle 
% 
% % Perform interpolation using interp1 function
% witMotionStartingTime = interp1(x, y, xq, 'linear'); 
% 
% timestamps = witMotionData.Time - witMotionStartingTime;
% % %%
% 
% 
% % Store processed data for output
% % coolTermData.Time = table2array(XData);  % Time column
% % 
% % 
% % timestamps = coolTermData.Time - coolTermData.Time(1,1);
% timestamps = timestamps / 1000;
% coolTermData.Time = timestamps;
% coolTermData.Values = table2array(YData);  % Extracted values based on dataType and sensor
% if (contains([sensorType dataType], 'EAngVel') || contains([sensorType dataType], 'FAngVel'))
%     coolTermData.Values = coolTermData.Values * -1;
% end
% end
% 
% function pythonGraphData = processPythonGraphData(rawData, sensorType, dataType)
% 
% end
% 
% function witMotionData = processWitMotionData(rawData, sensorType, dataType)
% columnHeaders = rawData.Properties.VariableNames;
% % Constants for column indices based on data type
% TIME_COL = 1; % Time column index
% SENSOR_ID_COL = 2; % Sensor ID column index
% ANGLE_Y_COL = find(contains(columnHeaders, 'Angle Y')); % Column index for Angle Y
% 
% % Mapping sensor types to their corresponding sensor ID
% sensorMap = containers.Map(...
%     {'H', 'I'}, ...
%     {'d2:5a:50:4a:21:12', 'ef:e4:2c:bf:73:a9'});
% letterMap = containers.Map(...
%     {'d2:5a:50:4a:21:12', 'ef:e4:2c:bf:73:a9', }, ...
%     {'H', 'I'});
% inputLinkID = sensorMap('H');  % Always use sensor 'H' for zero crossing reference
% 
% % Filter data for the input link to find zero crossings
% inputLinkData = rawData(contains(rawData{:, SENSOR_ID_COL}, inputLinkID), :);
% zeroCrossings = find(diff(sign(table2array(inputLinkData(:, ANGLE_Y_COL)))) > 0) + 1;
% if length(zeroCrossings) < 2
%     error('Not enough zero crossings found for input link.');
% end
% 
% % Determine start and end times for valid data using input link zero crossings
% validStartTime = duration(table2array(inputLinkData(zeroCrossings(1), TIME_COL)));
% validEndTime = duration(table2array(inputLinkData(zeroCrossings(2), TIME_COL)));
% 
% % Filter data for the current sensor type
% sensorID = sensorMap(sensorType);
% sensorData = rawData(contains(rawData{:, SENSOR_ID_COL}, sensorID), :);
% 
% % Find indices in sensorData that are within the valid time range determined by the input link
% validIndices = sensorData{:, TIME_COL} >= validStartTime & sensorData{:, TIME_COL} <= validEndTime;
% if sum(validIndices) == 0
%     error('No data found for the current sensor within the valid time range.');
% end
% 
% % Extract data slice based on the valid time indices
% validData = sensorData(validIndices, :);
% 
% % Further refinement based on dataType to extract only relevant data
% % dataColumns = RMSEUtils.getDataColumns(dataType);
% if (strcmp(dataType, 'Angle'))
%     startColumn = find(contains(validData.Properties.VariableNames, "Angle X"));
% elseif (strcmp(dataType, 'AngVel'))
%     startColumn = find(contains(validData.Properties.VariableNames, "Angular velocity X"));
% else
%     disp("ERROR: DATATYPE NOT 'Angle' NOR 'AngVel'");
% end
% % startColumn = find(contains(validData.Properties.VariableNames, "Angle X"));
% 
% % Define the range from the start column to the next two columns
% if ~isempty(startColumn)  % Ensure that a match was found
%     dataColumns = startColumn:(startColumn + 2);  % Create the range of three columns
% else
%     dataColumns = [];  % Handle the case where no match is found
%     disp("ERROR: DATACOLUMN NOT SET UP CORRECTLY");
% end
% 
% % dataColumns = find(contains(validData(:, "Angle X")));
% refinedData = validData(:, dataColumns);
% 
% % Prepare output structure
% witMotionData = struct();
% witMotionData.Time = table2array(validData(:, TIME_COL));
% % Determine the actual start time by utilizing interpolation to find
% % the starting theoretical where the input link is 0
% x = [inputLinkData{zeroCrossings(1,1), ANGLE_Y_COL}, inputLinkData{zeroCrossings(1,1)-1, ANGLE_Y_COL}];  % Example angles in degrees
% 
% % Define the corresponding y values (times) as duration type
% y = [inputLinkData{zeroCrossings(1,1), TIME_COL}, inputLinkData{zeroCrossings(1,1)-1, TIME_COL}];  % Example times
% 
% % Define the x value at which you want to interpolate
% xq = 0;  % Instance where input link starts at 0 degree angle 
% 
% % Perform interpolation using interp1 function
% witMotionStartingTime = interp1(x, y, xq, 'linear'); 
% 
% witMotionData.Time = seconds(witMotionData.Time - witMotionStartingTime);
% % TODO: Update this accordingly
% if (contains([letterMap(sensorID) dataType], 'HAngVel'))
%     witMotionData.Values = table2array(refinedData(:,2));
%     witMotionData.Values = witMotionData.Values * pi / 180; % CONVERT FROM deg/s to rad/s
%     % witMotionData.Values = witMotionData.Values * (2 * pi) / 60; % CONVERSION FROM RPM TO RAD/S
%     % witMotionData.Values = witMotionData.Values * -1;
% elseif (contains([letterMap(sensorID) dataType], 'IAngVel'))
%     witMotionData.Values = table2array(refinedData(:,2));
%     witMotionData.Values = witMotionData.Values * pi / 180; % CONVERT FROM deg/s to rad/s
%     % witMotionData.Values = witMotionData.Values * -1;
%     % witMotionData.Values = witMotionData.Values * -1 * (2 * pi) / 60; % CONVERSION FROM RPM TO RAD/S
% 
% elseif (contains([letterMap(sensorID) dataType], 'HAngle'))
%     witMotionData.Values = table2array(refinedData(:,2));
%     % witMotionData.Values = witMotionData.Values * -1;
% elseif (contains([letterMap(sensorID) dataType], 'IAngle'))
%     witMotionData.Values = table2array(refinedData(:,2));
%     % witMotionData.Values = witMotionData.Values * -1;
% else
%     witMotionData.Values = table2array(refinedData(:,1));
% end
% % witMotionData.Values = refinedData;
% witMotionData.SensorID = sensorID;  % Include sensor ID in the output for reference
% end

function [selectedMap, letterMap] = determineMap(rawData, SENSOR_ID_COL)
    % Define potential maps
    sensorMap1 = containers.Map(...
    {'H', 'I'}, ...
    {'d2:5a:50:4a:21:12', 'ef:e4:2c:bf:73:a9'}); 
    
    sensorMap2 = containers.Map(...
        {'E', 'F', 'G'}, ...
        {'COM16', 'COM14', 'COM13'});
    
    % Get unique device names from rawData
    uniqueDeviceNames = unique(rawData{:, SENSOR_ID_COL});
    
    % Determine which map to use based on presence of known keys
    if all(ismember(values(sensorMap1), uniqueDeviceNames))
        selectedMap = sensorMap1;
    elseif all(ismember(values(sensorMap2), uniqueDeviceNames))
        selectedMap = sensorMap2;
    else
        % Raise an error if no suitable map can be determined
        error('Please add the corresponding device name within determineMap function within RMSE function');
    end
    % Create the reverse map (letterMap) dynamically
    letterMap = containers.Map(values(selectedMap), keys(selectedMap));
end

function adjustment = determineAdjustment(sensor, theoData, actualData)
     switch sensor
        case {'E', 'F', 'H', 'I'}
            adjustment = theoData - 90 - actualData;
        case 'G'
            adjustment = 180 - theoData - actualData;
        otherwise
            error('Invalid sensor type.');
    end
end

function offset = determineOffset(sensor, theoDataArray, adjustmentVal)
   % Extract the Time field from the theoData struct
    % timeData = theoData.Time; % 361x1 double array

    % Initialize offset to be the same size as timeData
    offset = zeros(size(theoDataArray));
    
    % Determine the offset based on the sensor type
    switch sensor
        case {'E', 'F', 'H', 'I'}
            offset = theoDataArray - 90 - adjustmentVal; % Apply the formula to each element
        case 'G'
            offset = 180 - theoDataArray - adjustmentVal; % Apply the formula to each element
        otherwise
            error('Invalid sensor type.');
    end
end
