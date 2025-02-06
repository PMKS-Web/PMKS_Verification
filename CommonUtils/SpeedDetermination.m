classdef SpeedDetermination
    methods(Static)
        % function [input_speed_str, fileToSpeedMap] = determineSpeeds(witMotionPath, sensorMap)
        %     % Determine speeds for all data files in the WitMotion directory
        %     % Args:
        %     % - witMotionPath: Path to the WitMotion directory
        %     % - sensorMap: Map of sensor identifiers to their IDs
        %     % Returns:
        %     % - input_speed_str: Array of determined speeds
        % 
        %     % Initialize an array for storing speeds
        %     input_speed_str = [];
        %     fileToSpeedMap = containers.Map; % Map for file-to-speed correlation
        % 
        %     % Iterate over CSV files in the WitMotion directory
        %     files = dir(fullfile(witMotionPath, '*.csv'));
        %     for i = 1:length(files)
        %         filepath = fullfile(witMotionPath, files(i).name);
        %         filename = files(i).name; % Get the filename (without path)
        % 
        % 
        %         % Load raw data with proper CSV handling
        %         rawData = SpeedDetermination.readCSV(filepath);
        % 
        %         % Calculate speed for the file
        %         try
        %             if contains(filepath, 'WitMotion')
        %                 speed = SpeedDetermination.calculateWitMotionSpeed(rawData, sensorMap);
        %             elseif contains(filepath, 'PythonGraph')
        %                 speed = SpeedDetermination.calculatePythonGraphSpeed(rawData, sensorMap);
        %             else
        %                 error('Filepath does not contain the expected substrings.');
        %             end
        %             input_speed_str = [input_speed_str, speed]; % Append speed to the array
        %             fileToSpeedMap(filename) = speed; % Map the filename to its speed
        %         catch ME
        %             warning('Failed to determine speed for file %s: %s', filepath, ME.message);
        %         end
        %     end
        % end

        function [input_speed_str, fileToSpeedMap] = determineSpeeds(witMotionPath, sensorMap)
            % Determine speeds for all data files in the specified directory
            % Args:
            % - witMotionPath: Path to the directory containing data files
            % - sensorMap: Map of sensor identifiers to their IDs
            % Returns:
            % - input_speed_str: Array of determined speeds
            % - fileToSpeedMap: Map of filenames to their corresponding speeds
        
            % Initialize an array for storing speeds
            input_speed_str = [];
            fileToSpeedMap = containers.Map; % Map for file-to-speed correlation
        
            % Get a list of all files in the directory
            files = dir(witMotionPath);
        
            % Iterate over the files
            for i = 1:length(files)
                % Skip directories
                if files(i).isdir
                    continue;
                end
        
                % Get the full file path
                filepath = fullfile(witMotionPath, files(i).name);
                filename = files(i).name; % Get the filename (without path)
        
                % Extract the file extension
                [~, ~, ext] = fileparts(filename);
        
                % Load raw data based on file extension
                try
                    switch lower(ext)
                        case '.csv'
                            rawData = SpeedDetermination.readCSV(filepath);
                        case '.xlsx'
                            rawData = SpeedDetermination.readExcel(filepath);
                        otherwise
                            warning('Unsupported file extension for file %s. Skipping.', filename);
                            continue;
                    end
        
                    % Calculate speed for the file
                    if contains(filepath, 'WitMotion', 'IgnoreCase', true)
                        speed = SpeedDetermination.calculateWitMotionSpeed(rawData, sensorMap);
                    elseif contains(filepath, 'PythonGraph', 'IgnoreCase', true)
                        speed = SpeedDetermination.calculatePythonGraphSpeed(rawData, sensorMap);
                    else
                        error('Filepath does not contain the expected substrings.');
                    end
        
                    input_speed_str = [input_speed_str, speed]; % Append speed to the array
                    fileToSpeedMap(filename) = speed; % Map the filename to its speed
                catch ME
                    warning('Failed to determine speed for file %s: %s', filepath, ME.message);
                end
            end
        end

        function rawData = readCSV(csvPath)
            % Read CSV file with proper handling of headers and data lines
            % Args:
            % - csvPath: Full path to the CSV file
            % Returns:
            % - rawData: Table containing the data

            % Check if the file exists
            if isfile(csvPath)
                opts = detectImportOptions(csvPath);
                opts.Delimiter = ',';  % Set the delimiter
                opts.PreserveVariableNames = true; % Preserve variable names from the file
                opts.VariableNamesLine = 1; % First row contains variable names (headers)
                opts.DataLine = 2; % Data starts on the second line

                % Read the table using the specified options
                rawData = readtable(csvPath, opts);
            else
                error('CSV file not found: %s', csvPath);
            end
        end

        function rawData = readExcel(excelPath)
            % Read Excel file with proper handling of headers and data lines
            % Args:
            % - excelPath: Full path to the Excel file
            % - sheetName: (Optional) Name or index of the sheet to read from
            % Returns:
            % - rawData: Table containing the data
        
            % Check if the file exists
            if isfile(excelPath)
                % Set import options
                opts = detectImportOptions(excelPath);
                opts.PreserveVariableNames = true; % Preserve variable names from the file
                % opts.VariableNamesLine = 1; % First row contains variable names (headers)
                % opts.DataLine = 2; % Data starts on the second line
        
                % If a specific sheet is provided, set the Sheet option
                % if nargin > 1 && ~isempty(sheetName)
                %     opts.Sheet = sheetName;
                % end
        
                % Read the table using the specified options
                rawData = readtable(excelPath, opts);
            else
                error('Excel file not found: %s', excelPath);
            end
        end


        function speed = calculateWitMotionSpeed(rawData, inputLinkID)
            % Calculate the speed of the mechanism based on input link zero crossings
            % Args:
            % - rawData: Table containing raw experimental data
            % - sensorMap: Map of sensor identifiers to their IDs
            % Returns:
            % - speed: Speed in revolutions per minute (RPM)

            columnHeaders = rawData.Properties.VariableNames;

            % Constants for column indices based on data type
            TIME_COL = 1; % Time column index
            SENSOR_ID_COL = 2; % Sensor ID column index
            Angle_Z_COL = find(contains(columnHeaders, 'Angle Z')); % Column index for Angle Z

            % Automatically determine input link ID using sensorMap
%             inputLinkID = sensorMap('E'); % Adjust logic if other criteria define the input link

            % Filter data for the input link to find zero crossings
            inputLinkData = rawData(contains(rawData{:, SENSOR_ID_COL}, inputLinkID), :);
            zeroCrossings = find(diff(sign(table2array(inputLinkData(:, Angle_Z_COL)))) > 0) + 1;

            if length(zeroCrossings) < 3
                error('Not enough zero crossings found for input link.');
            end

            % Use interpolation to refine start and end times
            timeData = table2array(inputLinkData(:, TIME_COL));
            angleData = table2array(inputLinkData(:, Angle_Z_COL));

            % Interpolate to find precise times for zero degrees
%             interpStartTime = interp1(angleData(zeroCrossings(1)-1:zeroCrossings(1)+1), ...
%                                       timeData(zeroCrossings(1)-1:zeroCrossings(1)+1), ...
%                                       0, 'linear', 'extrap');
% 
%             interpEndTime = interp1(angleData(zeroCrossings(3)-1:zeroCrossings(3)+1), ...
%                                     timeData(zeroCrossings(3)-1:zeroCrossings(3)+1), ...
%                                     0, 'linear', 'extrap');
%             startTime = 
            % Calculate total time for 2 revolutions
%             totalTime = seconds(interpEndTime - interpStartTime); % Time in seconds
%             startTime = timeData(1); % First time point
%             endTime = timeData(end); % Last time point
            startTime = timeData(zeroCrossings(1)); % Time at the 2nd zero crossing
            endTime = timeData(zeroCrossings(2) - 1); % Time at the 3rd zero crossing

            totalTime = seconds(endTime - startTime); % Time in seconds


            % Convert to RPM (Revolutions Per Minute)
%             speed = round((2 / totalTime) * 60, 2);
            speed = round((60 / totalTime), 2);
            % Strip trailing zeros
%             speed = num2str(speed); % Convert to string
        end
        function speed = calculatePythonGraphSpeed(rawData, inputLinkID)
            % Calculate the speed of the mechanism based on input link zero crossings
            % Args:
            % - rawData: Table containing raw experimental data
            % - inputLinkID: Identifier for the input link
            % Returns:
            % - speed: Speed value extracted from the data
        
            % Constants for column indices based on data type
            SPEED_COL = 3; % Column index for speed data
        
            % Extract the data from the specified column
            speedData = rawData{:, SPEED_COL};
        
            % Find unique values in the order they appear
            uniqueSpeeds = unique(speedData, 'stable');
        
            % Check if there are at least two unique values
            if numel(uniqueSpeeds) >= 2
                % Assign the second unique value to speed
                speed = uniqueSpeeds(2);
            else
                error('Not enough unique values in the specified column to determine the second unique speed.');
            end
        end
    end
end
