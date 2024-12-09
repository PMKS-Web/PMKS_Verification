classdef SpeedDetermination
    methods(Static)
        function [input_speed_str, fileToSpeedMap] = determineSpeeds(witMotionPath, sensorMap)
            % Determine speeds for all data files in the WitMotion directory
            % Args:
            % - witMotionPath: Path to the WitMotion directory
            % - sensorMap: Map of sensor identifiers to their IDs
            % Returns:
            % - input_speed_str: Array of determined speeds

            % Initialize an array for storing speeds
            input_speed_str = [];
            fileToSpeedMap = containers.Map; % Map for file-to-speed correlation

            % Iterate over CSV files in the WitMotion directory
            files = dir(fullfile(witMotionPath, '*.csv'));
            for i = 1:length(files)
                filepath = fullfile(witMotionPath, files(i).name);
                filename = files(i).name; % Get the filename (without path)


                % Load raw data with proper CSV handling
                rawData = SpeedDetermination.readCSV(filepath);

                % Calculate speed for the file
                try
                    speed = SpeedDetermination.calculateSpeed(rawData, sensorMap);
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

        function speed = calculateSpeed(rawData, inputLinkID)
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
            endTime = timeData(zeroCrossings(3) - 1); % Time at the 3rd zero crossing

            totalTime = seconds(endTime - startTime); % Time in seconds


            % Convert to RPM (Revolutions Per Minute)
%             speed = round((2 / totalTime) * 60, 2);
            speed = round((60 / totalTime), 2);
            % Strip trailing zeros
%             speed = num2str(speed); % Convert to string
        end
    end
end
