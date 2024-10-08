classdef RMSEUtils
    methods(Static)
        function Mechanism = RMSESolver(Mechanism, sensorDataTypes, sensorSourceMap, processCoolTermData, processPythonGraphData, processWitMotionData, determineAdjustment, determineOffset)
            TheoreticalPath = 'CSVOutput';

            % Define the base paths for experimental data
            ExperimentalPath = 'Experimental';

            % Define speeds (e.g. {'f10RPM', 'f20RPM', 'f30RPM'})
            speeds = formatSpeeds(Mechanism.input_speed_str);

            % Raw data
            expData = RMSEUtils.readExperimentalData(ExperimentalPath, sensorSourceMap, speeds);
            theoData = RMSEUtils.readTheoreticalData(TheoreticalPath);

            % Calculate RMSE for all sensors according to specified data types in the map
            rmseResults = struct();  % Initialize an empty struct to hold all results

            for sensor = keys(sensorDataTypes)
                currentSensor = sensor{1};
                dataTypes = sensorDataTypes(currentSensor);  % Retrieve data types for current sensor
                % Compute RMSE for the current sensor across its specified data types
                rmseResults.(currentSensor) = RMSEUtils.calculateRMSEForSensor(expData, theoData, currentSensor, sensorSourceMap, dataTypes, speeds, processCoolTermData, processPythonGraphData, processWitMotionData, determineAdjustment, determineOffset);
            end

            % Save results to CSV
            resultsFilename = 'RMSE_Results';
            % Verify this logic later and make sure this function works
            RMSEUtils.saveResultsToCSV(rmseResults, resultsFilename);
        end

        function dataStruct = readTheoreticalData(basePath)
            % Define mappings of categories to their relevant subcategories
            categoryMap = containers.Map({'Acc', 'Vel', 'Pos'}, ...
                {{'AngAcc', 'LinAcc'}, {'AngVel', 'LinVel'}, {'Angle', 'Point'}});  % No subcategories for Pos

            dataStruct = struct(); % Initialize the main data structure

            % Iterate over each category like Acc, Vel, Pos
            for k = categoryMap.keys
                category = k{1};
                subCategories = categoryMap(category);
                categoryPath = fullfile(basePath, category);

                % Process each subcategory appropriately

                for subCategory = subCategories
                    subCategoryPath = fullfile(categoryPath, subCategory{1});
                    if strcmp(subCategory{1}, 'LinAcc') || strcmp(subCategory{1}, 'LinVel') || strcmp(subCategory{1}, 'Point')  || strcmp(subCategory{1}, 'Angle')
                        dataStruct = RMSEUtils.processNestedDirectories(subCategoryPath, dataStruct, category, subCategory{1});
                    else
                        dataStruct = RMSEUtils.processSpeedDirectories(subCategoryPath, dataStruct, category, subCategory{1}, '');
                    end
                end
            end
        end

        function dataStruct = processNestedDirectories(path, dataStruct, category, subCategory)
            % Process directories for LinAcc, LinVel that have nested Joint/LinkCoM directories
            subDirs = {'Joint', 'LinkCoM'};
            for subDir = subDirs
                nestedPath = fullfile(path, subDir{1});
                if isfolder(nestedPath)
                    dataStruct = RMSEUtils.processSpeedDirectories(nestedPath, dataStruct, category, subCategory, subDir{1});
                end
            end
        end

        function dataStruct = processSpeedDirectories(path, dataStruct, category, subCategory, nestedDir)
            % Process directories that include different speeds or default data
            speeds = dir(path);
            for speed = speeds'
                if speed.isdir && ~ismember(speed.name, {'.', '..'})
                    speedPath = fullfile(path, speed.name);
                    dataStruct = RMSEUtils.readDataFromDirectory(speedPath, dataStruct, category, subCategory, nestedDir);
                else
                    dataStruct = RMSEUtils.readDataFromDirectory(path, dataStruct, category, subCategory, nestedDir);
                end
            end
        end

        function dataStruct = readDataFromDirectory(path, dataStruct, category, subCategory, nestedDir)
            csvFiles = dir(fullfile(path, '*.csv'));
            for file = csvFiles'
                % Handle optional speed tag in file name
                tokens = regexp(file.name, '^(.+?)\.csv$', 'tokens');
                if isempty(tokens) || isempty(tokens{1})
                    continue;
                end

                itemName = tokens{1}{1};
                speedTag = RMSEUtils.getSpeedTagFromPath(path);

                dataTable = readtable(fullfile(file.folder, file.name));
                dataStruct = RMSEUtils.updateDataStruct(dataStruct, category, subCategory, nestedDir, itemName, speedTag, dataTable);
            end
        end

        function speedTag = getSpeedTagFromPath(path)
            [~, lastDir] = fileparts(path); % Extracts the last directory name
            if contains(lastDir, 'RPM')
                speedTag = lastDir; % Use the directory name as the speed tag if it contains 'RPM'
            else
                speedTag = ''; % Set speed tag as empty if 'RPM' is not found
            end
        end

        function dataStruct = updateDataStruct(dataStruct, category, subCategory, nestedDir, itemName, speedTag, dataTable)
            if ~isfield(dataStruct, category)
                dataStruct.(category) = struct();
            end

            subCategoryField = subCategory;

            if ~isfield(dataStruct.(category), subCategoryField)
                dataStruct.(category).(subCategoryField) = struct();
            end

            finalTarget = dataStruct.(category).(subCategoryField);
            if ~isempty(nestedDir)
                if ~isfield(finalTarget, nestedDir)
                    finalTarget.(nestedDir) = struct();
                end
                finalTarget = finalTarget.(nestedDir);
            end

            if ~isfield(finalTarget, itemName)
                finalTarget.(itemName) = struct();
            end

            if ~isempty(speedTag)
                finalTarget.(itemName).(speedTag) = dataTable;
            else
                finalTarget.(itemName) = dataTable;
            end

            if isempty(nestedDir)
                dataStruct.(category).(subCategoryField) = finalTarget;
            else
                dataStruct.(category).(subCategoryField).(nestedDir) = finalTarget;
            end
        end


        function expData = readExperimentalData(baseExperimentalPath, sensorSourceMap, speeds)
            expData = struct(); % Initialize
            % subFolders = {'CoolTerm', 'WitMotion'}; % Subdirectories to iterate through
            % filenames = {'10RPM', '20RPM', '30RPM'}; % RPM filenames
            subFolders = mapValuesToUniqueArray(sensorSourceMap);
            filenames = speeds;

            for i = 1:length(subFolders)
                % Initialize sub-structures for each subfolder
                expData.(subFolders{i}) = struct();
                currentPath = fullfile(baseExperimentalPath, subFolders{i}); % Path to current subdirectory

                for j = 1:length(filenames)
                    safeFieldName = filenames{j};

                    % Construct file path
                    if strcmp(subFolders{i}, 'CoolTerm') % For 'CoolTerm', read XLSX files
                        xlsxPath = fullfile(currentPath, filenames{j} + ".xlsx");
                        % Check and read XLSX file
                        if isfile(xlsxPath)
                            expData.(subFolders{i}).(safeFieldName) = readtable(xlsxPath);
                            % expData.(subFolders{i}).(safeFieldName) = readtable(xlsxPath, 'Range', 'A1'); % Adjust 'Range' if necessary
                        end
                    elseif strcmp(subFolders{i}, 'WitMotion') % For 'WitMotion', read CSV files
                        csvPath = fullfile(currentPath, filenames{j} + ".csv");
                        % Check and read CSV file, including headers
                        if isfile(csvPath)
                            opts = detectImportOptions(csvPath);
                            opts.Delimiter = ',';  % Set the delimiter

                            % Ensure the variable names (headers) are preserved as they are in the file
                            opts.PreserveVariableNames = true;

                            % Specify that the first row contains the headers
                            opts.VariableNamesLine = 1;  % This tells MATLAB that the first line contains variable names (headers)

                            % Ensure data starts reading from the line after the headers
                            opts.DataLine = 2;  % Start reading data from the second line, assuming the first line is the header

                            % Read the table using the specified options
                            expData.(subFolders{i}).(safeFieldName) = readtable(csvPath, opts);
                        end
                    elseif strcmp(subFolders{i}, 'PythonGraph') % For 'PythonGraph', read XLSX files
                        xlsxPath = fullfile(currentPath, filenames{j} + ".xlsx");
                        % Check and read XLSX file
                        if isfile(xlsxPath)
                            expData.(subFolders{i}).(safeFieldName) = readtable(xlsxPath);
                            % If needed, you can specify 'Range' and other options in 'readtable'
                        end
                    else
                        % Handle other cases or give a warning/error
                        warning('Unknown subfolder type: %s', subFolders{i});
                    end
                end
            end
        end

        % Function to calculate RMSE for a given sensor and its data types
        function results = calculateRMSEForSensor(expData, theoData, sensor, sensorSourceMap, dataTypes, speeds, processCoolTermData, processPythonGraphData, processWitMotionData, determineAdjustment, determineOffset)
            results = struct();
            for dataType = dataTypes
                % results.(dataType{1}) = struct();  % Initialize a struct for each data type
                for speed = speeds
                    % Calculate RMSE using a hypothetical function, for a given dataType and speed
                    rmseValue = RMSEUtils.calculateRMSE(expData, theoData, sensor, sensorSourceMap, dataType{1}, speed{1}, processCoolTermData, processPythonGraphData, processWitMotionData, determineAdjustment, determineOffset);
                    % Store RMSE value in the struct under its corresponding speed
                    results.(dataType{1}).(speed{1}) = rmseValue;
                end
            end
        end

        % Retriev the desired experimental data
        function expData = retrieveExpData(dataSet, sensor, sensorSourceMap, dataType, speed, processCoolTermData, processPythonGraphData, processWitMotionData)
            % Map sensors to their respective data sources (CoolTerm or WitMotion)
            source = sensorSourceMap(sensor);
            % Check if the required data is available
            if isfield(dataSet, source) && isfield(dataSet.(source), speed)
                rawData = dataSet.(source).(speed); % nxm table of data
                % expData = processData(rawData, sensor, dataType);
                if (strcmp(source, 'CoolTerm'))
                    expData = feval(processCoolTermData, rawData, sensor, dataType);
                elseif (strcmp(source, 'WitMotion'))
                    expData = feval(processWitMotionData, rawData, sensor, dataType);
                elseif (strcmp(source, 'PythonGraph'))
                    expData = feval(processPythonGraphData, rawData, sensor, dataType);
                else
                    warming('Application utilized to analyze data is unknown');
                    expData = [];
                end
            else
                expData = []; % Return empty if not found
            end
        end

        % For CoolTerm Data Processing
        % function coolTermData = processCoolTermData(rawData, sensorID, dataType)
        %     % Define sensor columns for angles and angular velocities
        %     sensorColumnsMap = containers.Map(...
        %         {'F', 'E', 'G'}, ...
        %         {struct('Angle', 5:7, 'AngVel', 4), ...
        %         struct('Angle', 8:10, 'AngVel', 11:13), ...
        %         struct('Angle', 14:16, 'AngVel', 17:19)});
        %     columns = sensorColumnsMap(sensorID).(dataType);
        %
        %     binarySignal = rawData.Var3;  % Adjust 'Var3' to the correct variable name if different
        %
        %     % Identify valid data segments based on binary signals
        %     oneIndices = find(binarySignal == 1);
        %     validSegments = find(diff(oneIndices) > 1);  % Find non-consecutive ones
        %
        %     if isempty(validSegments) || length(validSegments) < 2
        %         error('Valid data segments not found.');
        %     end
        %
        %     if isempty(validSegments) || length(validSegments) < 2
        %         error('Valid data segments not found.');
        %     end
        %
        %     % Define the range for valid data based on identified segments
        %     validStartIndex = oneIndices(validSegments(1));
        %     validEndIndex = oneIndices(validSegments(2));
        %
        %     % Extract the valid data range
        %     validData = rawData(validStartIndex:validEndIndex, :);
        %
        %     % Compare extracted data with theoretical data for further refinement
        %     % comparisonResults = compareData(validData(:, columns), theoData);
        %     % refinedDataIndices = find(comparisonResults);  % Rows closely matching theoretical data
        %     % TODO: Get the column that closely match the theoretical data
        %     % refinedDataIndices = validData(:,columns(1));
        %
        %     % Define map for selecting the correct Y column index based on sensor and dataType
        %     yColumnMap = containers.Map(...
        %         {'FAngVel', 'FAngle', 'EAngVel', 'EAngle', 'GAngVel', 'GAngle'}, ...
        %         {1, 2, 1, 3, 1, 3});
        %
        %     % Get the correct Y column index using the map
        %     yColumnIndex = columns(yColumnMap([sensorID dataType]));
        %
        %     YData = validData(:, yColumnIndex);
        %     XData = validData(:, 2);
        %     % Refine data by ensuring continuity and removing spikes (maybe do later)
        %     % refinedData = validData(refinedDataIndices, :);
        %     % continuousData = removeSpikes(refinedData, columns);
        %
        %     % Store processed data for output
        %     coolTermData.Time = XData;  % Time column
        %     coolTermData.Values = YData;  % Extracted values based on dataType and sensor
        % end

        function isClose = compareData(experimental, theoretical)
            % Define a simple threshold-based comparison for data matching
            isClose = sum(abs(experimental - theoretical), 2) < someThreshold;  % Adjust threshold as needed
        end

        function cleanData = removeSpikes(data, columns)
            % Remove spikes using median and median absolute deviation (MAD)
            for col = columns
                medianVal = median(data(:, col));
                madVal = mad(data(:, col), 1);
                spikeIndices = abs(data(:, col) - medianVal) > 3 * madVal;
                data(spikeIndices, col) = NaN;  % Replace spikes with NaNs
            end
            cleanData = data(all(~isnan(data), 2), :);  % Discard any rows with NaNs
        end


        % function witMotionData = processWitMotionData(rawData, sensorType, dataType)
        %     % Constants for column indices based on data type
        %     TIME_COL = 1; % Time column index
        %     SENSOR_ID_COL = 2; % Sensor ID column index
        %     ANGLE_Y_COL = 11; % Column index for Angle Y
        %
        %     % Mapping sensor types to their corresponding sensor ID
        %     sensorMap = containers.Map(...
        %         {'H', 'I'}, ...
        %         {'WT901BLE68(ef:e4:2c:bf:73:a9)', 'WT901BLE68(d2:5a:50:4a:21:12)'});
        %     inputLinkID = sensorMap('H');  % Always use sensor 'H' for zero crossing reference
        %
        %     % Filter data for the input link to find zero crossings
        %     inputLinkData = rawData(strcmp(rawData{:, SENSOR_ID_COL}, inputLinkID), :);
        %     zeroCrossings = find(diff(sign(table2array(inputLinkData(:, ANGLE_Y_COL)))) > 0) + 1;
        %     if length(zeroCrossings) < 2
        %         error('Not enough zero crossings found for input link.');
        %     end
        %
        %     % Determine start and end times for valid data using input link zero crossings
        %     validStartTime = duration(table2array(inputLinkData(zeroCrossings(1), TIME_COL)));
        %     validEndTime = duration(table2array(inputLinkData(zeroCrossings(2), TIME_COL)));
        %
        %     % Filter data for the current sensor type
        %     sensorID = sensorMap(sensorType);
        %     sensorData = rawData(strcmp(rawData{:, SENSOR_ID_COL}, sensorID), :);
        %
        %     % Find indices in sensorData that are within the valid time range determined by the input link
        %     validIndices = sensorData{:, TIME_COL} >= validStartTime & sensorData{:, TIME_COL} <= validEndTime;
        %     if sum(validIndices) == 0
        %         error('No data found for the current sensor within the valid time range.');
        %     end
        %
        %     % Extract data slice based on the valid time indices
        %     validData = sensorData(validIndices, :);
        %
        %     % Further refinement based on dataType to extract only relevant data
        %     dataColumns = RMSEUtils.getDataColumns(dataType);
        %     refinedData = validData(:, dataColumns);
        %
        %     % Prepare output structure
        %     witMotionData = struct();
        %     witMotionData.Time = validData(:, TIME_COL);
        %     % TODO: Update this accordingly
        %     witMotionData.Values = refinedData(:,1);
        %     % witMotionData.Values = refinedData;
        %     witMotionData.SensorID = sensorID;  % Include sensor ID in the output for reference
        % end

        % function pythonGraphData = processPythonGraphData(rawData, sensor, dataType)
        %     % Constants for column indices
        %     HALL_SENSOR_COL = 1;
        %     EST_RPM_COL = 2;
        %     PISTON_DISP_COL = 3;
        %     ADXL_PISTON_LIN_ACC_COL = 4;
        %     BNO_ORIENTATION_START_COL = 5; % X, Y, Z orientation start from this column
        %     BNO_ORIENTATION_END_COL = 7; % X, Y, Z orientation end at this column
        %     BNO_ANG_VEL_COL = 8;
        %
        %     binarySignal = rawData.HallSensor;  % Adjust 'Var3' to the correct variable name if different
        %
        %     % Identify valid data segments based on binary signals
        %     oneIndices = find(binarySignal == 1);
        %     validSegments = find(diff(oneIndices) > 1);  % Find non-consecutive ones
        %
        %     if isempty(validSegments) || length(validSegments) < 2
        %         error('Valid data segments not found.');
        %     end
        %
        %     if isempty(validSegments) || length(validSegments) < 2
        %         error('Valid data segments not found.');
        %     end
        %
        %     % Define the range for valid data based on identified segments
        %     validStartIndex = oneIndices(validSegments(1));
        %     validEndIndex = oneIndices(validSegments(2));
        %
        %     % Extract data within the valid range
        %     validData = rawData(validStartIndex:validEndIndex, :);
        %
        %     % Determine columns based on dataType
        %     switch dataType
        %         case 'Angle'
        %             columns = BNO_ORIENTATION_START_COL:BNO_ORIENTATION_END_COL;
        %         case 'AngVel'
        %             columns = BNO_ANG_VEL_COL;
        %         case 'LinAcc'
        %             columns = ADXL_PISTON_LIN_ACC_COL;
        %         otherwise
        %             error('Unknown dataType specified');
        %     end
        %
        %     % Insert a time step column based on estimated RPM (convert to radians per second first)
        %     estRpm = rawData{validStartIndex, EST_RPM_COL};
        %     omega = estRpm * (2 * pi / 60); % Convert RPM to radians per second
        %     timesteps = (0 : height(validData) - 1)' / omega; % Create a timestep array
        %     validData.Timestep = seconds(timesteps); % Insert as duration in seconds
        %
        %     % Select and store the desired data based on dataType and sensor
        %     pythonGraphData = struct();
        %     % pythonGraphData.Time = validData.Timestep; % Use the new Timestep column
        %     % pythonGraphData.Values = validData(:, columns); % Data of interest
        %     % pythonGraphData.SensorID = sensor; % Include sensor ID for reference
        %
        %     yColumnMap = containers.Map(...
        %         {'EAngle', 'EAngVel', 'FLinAcc'}, ...
        %         {2, 1, 1});
        %
        %     % Get the correct Y column index using the map
        %     % sensorID = sensorMap(sensorType);
        %     % sensorID =
        %
        %     yColumnIndex = columns(yColumnMap([sensor dataType]));
        %
        %     YData = table2array(validData(:, yColumnIndex));
        %     XData = timesteps;
        %     % Refine data by ensuring continuity and removing spikes (maybe do later)
        %     % refinedData = validData(refinedDataIndices, :);
        %     % continuousData = removeSpikes(refinedData, columns);
        %
        %     % Store processed data for output
        %     pythonGraphData.Time = XData;  % Time column
        %     pythonGraphData.Values = YData;  % Extracted values based on dataType and sensor
        % end


        function cols = getDataColumns(dataType)
            % Define data columns for different data types
            switch dataType
                case 'LinAcc'
                    cols = 4:6; % Columns for acceleration data
                case 'AngVel'
                    cols = 7:9; % Columns for angular velocity data
                case 'Angle'
                    cols = 10:12; % Columns for angle data
                otherwise
                    cols = [];
            end
        end

        % Retriev the desired theoretical data
        % function theoData = retrieveTheoData(dataSet, expData, sensor, dataType, speed)
        %     % Determine the main category based on dataType
        %     switch dataType
        %         case {'LinVel', 'AngVel'}
        %             mainCategory = 'Vel';
        %         case {'LinAcc', 'AngAcc'}
        %             mainCategory = 'Acc';
        %         case {'Angle', 'Point'}
        %             mainCategory = 'Pos';
        %         otherwise
        %             mainCategory = '?';
        %     end
        %
        %     % Determine the sub-category (Joint or LinkCoM or directly under the category)
        %     if any(strcmp(dataType, {'LinVel', 'LinAcc', 'Point'}))  % These involve Joint or LinkCoM
        %         if length(sensor) == 1  % Assuming sensor names for Joints are single characters
        %             subCategory = 'Joint';
        %             % subCategory = 'TracerPoint';
        %         else
        %             subCategory = 'LinkCoM';
        %         end
        %     else  % For angular data types or position, the sensor directly maps to data
        %         subCategory = '';
        %     end
        %
        %     % Access the appropriate dataset
        %     try
        %         if isempty(subCategory)
        %             % Directly under main category for angular data types
        %             dataField = dataSet.(mainCategory).(dataType);
        %         else
        %             % Nested under Joint or LinkCoM
        %             dataField = dataSet.(mainCategory).(dataType).(subCategory);
        %         end
        %
        %         % Dynamically find the appropriate sensor field that contains the sensor ID
        %         theoDataArray = [];
        %         if ~isempty(dataField)
        %             sensorFields = fieldnames(dataField);
        %             for i = 1:length(sensorFields)
        %                 if contains(sensorFields{i}, sensor)
        %                     % Handle cases with and without speed specification
        %                     if ~isempty(speed) && isfield(dataField.(sensorFields{i}), speed)
        %                         % theoData = table2array(dataField.(sensorFields{i}).(speed)(:,1));
        %                         theoDataArray = table2array(dataField.(sensorFields{i}).(speed)(:,3));
        %                     else
        %                         % Assuming expData and theoData are columns of
        %                         theoDataArray = double(dataField.(sensorFields{i}){:, 3});
        %                         % TODO: MAKE SURE expData.Values(1,1) AND theoData(1,1) have the same timestep. The adjustment is off because they do not have the same timestep
        %                         % adjustedTheorData = theoDataArray(1,1);
        %                         % adjustment = expData.Values(1,1) - adjustedTheorData;
        %                         % theoDataArray = theoDataArray + adjustment;
        %                         % Interpolate theoDataArray to find the value at the first timestep of expData.Values
        %                         % Assuming theoDataArray has time in theoDataArray.Time and corresponding values in theoDataArray.Values
        %                         interpolatedTheoData = interp1(theoDataArray.Time, theoDataArray.Values, expTimeStart, 'linear');
        %
        %                         % Calculate the adjustment using the interpolated value at the first timestep
        %                         adjustment = expData.Values(1) - interpolatedTheoData;
        %
        %                         % Apply the adjustment to the entire theoretical data array
        %                         adjustedTheoDataArray = theoDataArray.Values + adjustment;
        %
        %                         % Updating theoDataArray with the adjusted values
        %                         theoDataArray.Values = adjustedTheoDataArray;
        %                         %% This is another band-aid solution and make sure to accomondate for this accordingly
        %                         if strcmp(dataType, 'Angle')
        %                             if strcmp(sensor, 'H') || strcmp(sensor, 'I')
        %                             % Step 1: Convert negative values to their positive complements
        %                                 data = mod(theoData, 360);  % This ensures all values are in the range [0, 360)
        %
        %                                 % Step 2: Map values to the new range [-90, 90]
        %                                 % adjustedData = zeros(size(data));  % Initialize the adjusted data array
        %
        %                                 for i = 1:length(data)
        %                                     if data(i) <= 90
        %                                         % Values between 0 and 90 remain the same
        %                                         theoDataArray(i) = data(i);
        %                                     elseif data(i) > 90 && data(i) <= 180
        %                                         % Values between 90 and 180 are mapped from 90 to 0
        %                                         theoDataArray(i) = 180 - data(i);
        %                                     elseif data(i) > 180 && data(i) <= 270
        %                                         % Values between 180 and 270 are mapped from 0 to -90
        %                                         theoDataArray(i) = -(data(i) - 180);
        %                                     else
        %                                         % Values between 270 and 360 are mapped from -90 to 0
        %                                         theoDataArray(i) = -(360 - data(i));
        %                                     end
        %                                 end
        %                             end
        %                         end
        %                         %% This is a band-aid... Make sure to accomodate for this accordingly (I believe adjusting the sensor in real life)
        %                         if strcmp(sensor, 'F')
        %                             theoDataArray = -1 * theoDataArray + (2 * theoDataArray(1,1));
        %                         end
        %                         % theoData = dataField.(sensorFields{i});  % Get the entire data if no speed is involved
        %                     end
        %                 end
        %             end
        %         end
        %         if isempty(theoDataArray)  % If no matching sensor field is found
        %             theoDataArray = [];  % Return empty if not found
        %         end
        %     catch
        %         theoDataArray = [];  % Return empty if any field is not found or any error occurs
        %     end
        %     theoData.Values = theoDataArray;
        %
        %     % Now, determine timestep
        %     rpmValue = str2double(strrep(regexp(speed, '\d+_\d+|\d+', 'match'), '_', '.'));
        %     % rpmValue = str2double(regexp(speed, '\d+', 'match'));  % Extract numerical part from speed string like 'f10RPM'
        %     timePerRevolution = 60 / rpmValue;  % Calculate the time for one full revolution (in seconds)
        %     numDataPoints = size(theoData.Values, 1);  % Number of data points in the theoretical data
        %     theoreticalTime = linspace(0, timePerRevolution, numDataPoints);  % Create a linearly spaced time array
        %     theoreticalTime = theoreticalTime.';
        %     theoData.Time = theoreticalTime;
        % end

        function theoData = retrieveTheoData(dataSet, expData, sensor, dataType, speed, determineAdjustment, determineOffset)
            % Determine the main category based on dataType
            switch dataType
                case {'LinVel', 'AngVel'}
                    mainCategory = 'Vel';
                case {'LinAcc', 'AngAcc'}
                    mainCategory = 'Acc';
                case {'Angle', 'Point'}
                    mainCategory = 'Pos';
                otherwise
                    mainCategory = '?';
            end

            % Determine the sub-category (Joint or LinkCoM or directly under the category)
            if any(strcmp(dataType, {'LinVel', 'LinAcc', 'Point', 'Angle'}))
                if length(sensor) == 1  % Assuming sensor names for Joints are single characters
                    subCategory = 'Joint';
                else
                    subCategory = 'LinkCoM';
                end
            else
                subCategory = '';  % For angular data types or position, the sensor directly maps to data
            end

            % Access the appropriate dataset
            try
                if isempty(subCategory)
                    % Directly under main category for angular data types
                    dataField = dataSet.(mainCategory).(dataType);
                else
                    % Nested under Joint or LinkCoM
                    dataField = dataSet.(mainCategory).(dataType).(subCategory);
                end

                % Initialize theoDataArray
                theoDataArray = [];

                % Dynamically find the appropriate sensor field that contains the sensor ID
                if ~isempty(dataField)
                    sensorFields = fieldnames(dataField);
                    for i = 1:length(sensorFields)
                        if contains(sensorFields{i}, sensor)
                        % if strcmp(sensorFields{i}, sensor)
                            % Handle cases with and without speed specification
                            if ~isempty(speed) && isfield(dataField.(sensorFields{i}), speed)
                                theoDataArray = table2array(dataField.(sensorFields{i}).(speed)(:,3));
                                % Calculate Time Before Adjustment
                                rpmValue = str2double(strrep(regexp(speed, '\d+_\d+|\d+', 'match'), '_', '.'));
                                timePerRevolution = 60 / rpmValue;  % Time for one full revolution (in seconds)
                                numDataPoints = size(theoDataArray, 1);  % Number of data points in the theoretical data
                                theoreticalTime = linspace(0, timePerRevolution, numDataPoints).';  % Linearly spaced time array
                                theoData.Time = theoreticalTime;  % Set the time for theoData
                            else
                                theoDataArray = double(dataField.(sensorFields{i}){:, 3});

                                % Calculate Time Before Adjustment
                                rpmValue = str2double(strrep(regexp(speed, '\d+_\d+|\d+', 'match'), '_', '.'));
                                timePerRevolution = 60 / rpmValue;  % Time for one full revolution (in seconds)
                                numDataPoints = size(theoDataArray, 1);  % Number of data points in the theoretical data
                                theoreticalTime = linspace(0, timePerRevolution, numDataPoints).';  % Linearly spaced time array
                                theoData.Time = theoreticalTime;  % Set the time for theoData

                                % Perform Interpolation and Adjustments After Time Calculation
                                expTimeStart = expData.Time(1);  % Get the first timestep from expData
                                interpolatedTheoData = interp1(theoData.Time, theoDataArray, expTimeStart, 'linear');  % Interpolate to match first expData timestep
                                
                                % Utilize the passed in adjustment function and make the adjustment accordingly
                                adjustment = feval(determineAdjustment, sensor, interpolatedTheoData, expData.Values(1));
                           
                                % Pass the adjusted value into offset function 
                                theoDataArray = feval(determineOffset, sensor, theoDataArray, adjustment);

                                % adjustment = expData.Values(1) - interpolatedTheoData;  % Calculate adjustment
                                % theoDataArray = theoDataArray + adjustment;  % Apply adjustment

                                % Additional Adjustments for Specific Data Types or Sensors
                                if strcmp(dataType, 'Angle')
                                    if strcmp(sensor, 'H') || strcmp(sensor, 'I')
                                        theoDataArray = adjustAngleRange(theoDataArray);
                                    end
                                end
                                % 
                                % if strcmp(sensor, 'F')
                                %     theoDataArray = -1 * theoDataArray + (2 * theoDataArray(1,1));
                                % end
                            end
                        end
                    end
                end

                if isempty(theoDataArray)  % If no matching sensor field is found
                    theoDataArray = [];  % Return empty if not found
                end
            catch
                theoDataArray = [];  % Return empty if any field is not found or any error occurs
            end

            % Set the adjusted values back to theoData
            theoData.Values = theoDataArray;
        end

        function rmseResults = calculateRMSE(expDataSet, theoDataSet, sensor, sensorSourceMap, dataType, speed, processCoolTermData, processPythonGraphData, processWitMotionData, determineAdjustment, determineOffset)
            % rmseResults = struct(); % Initialize results structure

            % Retrieve experimental and theoretical data for the given sensor, dataType, and speed
            expData = RMSEUtils.retrieveExpData(expDataSet, sensor, sensorSourceMap, dataType, speed, processCoolTermData, processPythonGraphData, processWitMotionData);
            theoData = RMSEUtils.retrieveTheoData(theoDataSet, expData, sensor, dataType, speed, determineAdjustment, determineOffset);

            % Calculate RMSE if both experimental and theoretical data are available
            if ~isempty(expData) && ~isempty(theoData)
                % Extract the numerical part from speed string like 'f10_2RPM'
                % rpmValue = str2double(strrep(regexp(speed, '\d+_\d+|\d+', 'match'), '_', '.'));
                % % rpmValue = str2double(regexp(speed, '\d+', 'match'));  % Extract numerical part from speed string like 'f10RPM'
                % timePerRevolution = 60 / rpmValue;  % Calculate the time for one full revolution (in seconds)
                % numDataPoints = size(theoData, 1);  % Number of data points in the theoretical data
                % theoreticalTime = linspace(0, timePerRevolution, numDataPoints);  % Create a linearly spaced time array
                % theoreticalTime = theoreticalTime.';

                % Calculate RMSE if both experimental and theoretical data are available
                timestamps = expData.Time;

                % interpolatedTheoData = interp1(theoreticalTime, theoData, seconds(timestamps), 'linear', 'extrap');
                % interpolatedTheoData = interp1(theoreticalTime, theoData, timestamps, 'linear', 'extrap');
                % rmse = sqrt(mean((expData.Values - interpolatedTheoData).^2));
                interpolatedTheoData = interp1(theoData.Time, theoData.Values, timestamps, 'linear', 'extrap');
                rmse = sqrt(mean((expData.Values - interpolatedTheoData).^2));

                % Store RMSE in the results structure
                rmseResults = rmse;

                % Generate plot for verification
                fig = figure('Visible', 'off');
                hold on;
                plot(timestamps, expData.Values, 'b', 'DisplayName', 'Experimental Data');
                plot(theoData.Time, theoData.Values, 'g', 'DisplayName', 'Theoretical Data');
                plot(timestamps, interpolatedTheoData, 'r--', 'DisplayName', 'Interpolated Theoretical Data');
                legend show;
                xlabel('Time (s)');
                ylabel('Data Value');
                title(['RMSE Analysis for ' sensor ' - ' dataType ' - ' speed]);
                hold off;

                % Define directory path for saving
                resultDir = fullfile('RMSE_Results', sensor, dataType, speed);

                % Ensure the directory exists
                if ~exist(resultDir, 'dir')
                    mkdir(resultDir);
                end

                % Save plot
                savefig(fig, fullfile(resultDir, 'graph.fig'));
                saveas(fig, fullfile(resultDir, 'graph.png'));

                % Close the figure
                close(fig);
            else
                warning('Missing data for sensor %s, data type %s, speed %s', sensor, dataType, speed);
                rmseResults = NaN; % Assign NaN to indicate missing data calculation
            end

            return;
        end
        % Function to save RMSE results to CSV
        function saveResultsToCSV(rmseResults, baseFolder)
            % Ensure the base RMSE folder exists
            if ~exist(baseFolder, 'dir')
                mkdir(baseFolder);
            end

            % Iterate over all sensors
            for sensor = fieldnames(rmseResults)'
                sensorPath = fullfile(baseFolder, sensor{1});
                if ~exist(sensorPath, 'dir')
                    mkdir(sensorPath);
                end

                % Iterate over all data types
                for dataType = fieldnames(rmseResults.(sensor{1}))'
                    dataTypePath = fullfile(sensorPath, dataType{1});
                    if ~exist(dataTypePath, 'dir')
                        mkdir(dataTypePath);
                    end

                    % Iterate over all speeds
                    for speed = fieldnames(rmseResults.(sensor{1}).(dataType{1}))'
                        speedPath = fullfile(dataTypePath, speed{1});
                        if ~exist(speedPath, 'dir')
                            mkdir(speedPath);
                        end

                        % Retrieve the RMSE value
                        rmseValue = rmseResults.(sensor{1}).(dataType{1}).(speed{1});

                        % Define the filename for the Excel file
                        filename = fullfile(speedPath, 'RMSE.xlsx');

                        % Write RMSE value to an Excel file
                        xlswrite(filename, rmseValue, 'Sheet1', 'A1');
                    end
                end
            end
        end
    end
end

function speeds = formatSpeeds(input_speed_str)
% Initialize the cell array to store formatted speeds
speeds = cell(1, length(input_speed_str));

% Loop through each speed and format it
for i = 1:length(input_speed_str)
    % Format the string with 'f' at the start and 'RPM' at the end
    % speeds{i} = ['f' num2str(input_speed_str(i)) 'RPM'];
    speedStrTemp = strrep(num2str(input_speed_str(i)), '.', '_');  % Replace '.' with '_'
    speeds{i} = ['f' speedStrTemp 'RPM'];  % Construct the new name

end
end

function subFolders = mapValuesToUniqueArray(sensorSourceMap)
% Get all values from the map as a cell array
allValues = values(sensorSourceMap);

% Ensure all values are in a cell array of strings
if iscell(allValues{1})
    % Flatten the cell array in case it's nested
    allValues = [allValues{:}];
else
    % If the single value is not in a cell, wrap it
    allValues = allValues;
end

% Find unique values to avoid duplicates
uniqueValues = unique(allValues, 'stable');  % 'stable' keeps the original order

% Return the unique values as a cell array
subFolders = uniqueValues;
end

% Helper function to adjust angle data
function adjustedData = adjustAngleRange(data)
% Convert negative values to their positive complements
data = mod(data, 360);  % Ensure all values are in the range [0, 360)
adjustedData = zeros(size(data));  % Initialize the adjusted data array

for i = 1:length(data)
    if data(i) <= 90
        adjustedData(i) = data(i);
    elseif data(i) > 90 && data(i) <= 180
        adjustedData(i) = 180 - data(i);
    elseif data(i) > 180 && data(i) <= 270
        adjustedData(i) = -(data(i) - 180);
    else
        adjustedData(i) = -(360 - data(i));
    end
end
end



