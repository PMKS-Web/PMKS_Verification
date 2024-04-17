clear; close all; clc;

% Define the base paths for theoretical data
baseTheoreticalVelPath = 'CSVOutput/Vel/AngVel/';

TheoreticalPath = 'CSVOutput';

% Define the base paths for experimental data
ExperimentalPath = 'Experimental';
CoolTermExperimentalPath = 'Experimental/CoolTerm';
WitMotionExperimentalPath = 'Experimental/WitMotion';

% Define sensors and their corresponding links
sensors = {'E', 'F', 'G', 'H', 'I'};
sensorToLinkMap = containers.Map({'E', 'F', 'G', 'H', 'I'}, {'ABEH', 'BCFG', 'BCFG', 'ABEH', 'CDI'});

% Define speeds
speeds = {'f10RPM', 'f20RPM', 'f30RPM'};

expData = readExperimentalData(ExperimentalPath);
theoData = readTheoreticalData(TheoreticalPath);

% Define a map from sensors to their respective data types
sensorDataTypes = containers.Map(...
    {'E', 'F', 'G', 'H', 'I'}, ...
    {...
    {'Angle', 'AngVel'}, ...  % Data types for sensor E
    {'Angle', 'AngVel'}, ... % Data types for sensor F
    {'Angle', 'AngVel'}, ... % Data types for sensor G
    {'Angle', 'AngVel', 'LinAcc'}, ...  % Data types for sensor H
    {'Angle', 'AngVel', 'LinAcc'}  ... % Data types for sensor I
    }...
    );

% Calculate RMSE for all sensors according to specified data types in the map
rmseResults = struct();  % Initialize an empty struct to hold all results

for sensor = keys(sensorDataTypes)
    currentSensor = sensor{1};
    dataTypes = sensorDataTypes(currentSensor);  % Retrieve data types for current sensor
    % Compute RMSE for the current sensor across its specified data types
    rmseResults.(currentSensor) = calculateRMSEForSensor(expData, theoData, currentSensor, dataTypes, speeds);
end

% Save results to CSV
resultsFilename = 'RMSE_Results.csv';
% Verify this logic later and make sure this function works
saveResultsToCSV(rmseResults, resultsFilename);

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
        if strcmp(subCategory{1}, 'LinAcc') || strcmp(subCategory{1}, 'LinVel') || strcmp(subCategory{1}, 'Point')
            dataStruct = processNestedDirectories(subCategoryPath, dataStruct, category, subCategory{1});
        else
            dataStruct = processSpeedDirectories(subCategoryPath, dataStruct, category, subCategory{1}, '');
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
        dataStruct = processSpeedDirectories(nestedPath, dataStruct, category, subCategory, subDir{1});
    end
end
end

function dataStruct = processSpeedDirectories(path, dataStruct, category, subCategory, nestedDir)
% Process directories that include different speeds or default data
speeds = dir(path);
for speed = speeds'
    if speed.isdir && ~ismember(speed.name, {'.', '..'})
        speedPath = fullfile(path, speed.name);
        dataStruct = readDataFromDirectory(speedPath, dataStruct, category, subCategory, nestedDir);
    else
        dataStruct = readDataFromDirectory(path, dataStruct, category, subCategory, nestedDir);
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
    speedTag = getSpeedTagFromPath(path);

    dataTable = readtable(fullfile(file.folder, file.name));
    dataStruct = updateDataStruct(dataStruct, category, subCategory, nestedDir, itemName, speedTag, dataTable);
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


function expData = readExperimentalData(baseExperimentalPath)
expData = struct(); % Initialize
subFolders = {'CoolTerm', 'WitMotion'}; % Subdirectories to iterate through
filenames = {'10RPM', '20RPM', '30RPM'}; % RPM filenames

for i = 1:length(subFolders)
    % Initialize sub-structures for each subfolder
    expData.(subFolders{i}) = struct();
    currentPath = fullfile(baseExperimentalPath, subFolders{i}); % Path to current subdirectory

    for j = 1:length(filenames)
        safeFieldName = ['f' filenames{j}]; % Prepend 'f' to ensure the name starts with a letter

        % Construct file path
        if i == 1  % For 'CoolTerm', read XLSX files
            xlsxPath = fullfile(currentPath, filenames{j} + ".xlsx");
            % Check and read XLSX file
            if isfile(xlsxPath)
                expData.(subFolders{i}).(safeFieldName) = readtable(xlsxPath);
                % expData.(subFolders{i}).(safeFieldName) = readtable(xlsxPath, 'Range', 'A1'); % Adjust 'Range' if necessary
            end
        else  % For 'WitMotion', read CSV files
            csvPath = fullfile(currentPath, filenames{j} + ".csv");
            % Check and read CSV file, including headers
            if isfile(csvPath)
                opts = detectImportOptions(csvPath);
                opts.Delimiter = ','; % Set the delimiter
                % Retain all header lines, modify if there's a different number of header rows
                opts.PreserveVariableNames = true;
                expData.(subFolders{i}).(safeFieldName) = readtable(csvPath, opts);
            end
        end
    end
end
end

% Function to calculate RMSE for a given sensor and its data types
function results = calculateRMSEForSensor(expData, theoData, sensor, dataTypes, speeds)
results = struct();
for dataType = dataTypes
    % results.(dataType{1}) = struct();  % Initialize a struct for each data type
    for speed = speeds
        % Calculate RMSE using a hypothetical function, for a given dataType and speed
        rmseValue = calculateRMSE(expData, theoData, sensor, dataType{1}, speed{1});
        % Store RMSE value in the struct under its corresponding speed
        results.(dataType{1}).(speed{1}) = rmseValue;
    end
end
end

% Retriev the desired experimental data
function expData = retrieveExpData(dataSet, sensor, dataType, speed)
% Map sensors to their respective data sources (CoolTerm or WitMotion)
sensorSourceMap = containers.Map({'E', 'F', 'G', 'H', 'I'}, ...
    {'CoolTerm', 'CoolTerm', 'CoolTerm', 'WitMotion', 'WitMotion'});
source = sensorSourceMap(sensor);

% Check if the required data is available
if isfield(dataSet, source) && isfield(dataSet.(source), speed)
    rawData = dataSet.(source).(speed); % nxm table of data
    % expData = processData(rawData, sensor, dataType);
    if (strcmp(source, 'CoolTerm'))
        expData = processCoolTermData(rawData, sensor, dataType);
    else
        expData = processWitMotionData(rawData, sensor, dataType);
    end
else
    expData = []; % Return empty if not found
end
end

% For CoolTerm Data Processing
function coolTermData = processCoolTermData(rawData, sensorID, dataType)
% Define sensor columns for angles and angular velocities
sensorColumnsMap = containers.Map(...
    {'F', 'E', 'G'}, ...
    {struct('Angle', 5:7, 'AngVel', 4), ...
    struct('Angle', 8:10, 'AngVel', 11:13), ...
    struct('Angle', 14:16, 'AngVel', 17:19)});
columns = sensorColumnsMap(sensorID).(dataType);

binarySignal = rawData.Var3;  % Adjust 'Var3' to the correct variable name if different

% Identify valid data segments based on binary signals
oneIndices = find(binarySignal == 1);
validSegments = find(diff(oneIndices) > 1);  % Find non-consecutive ones

if isempty(validSegments) || length(validSegments) < 2
    error('Valid data segments not found.');
end

if isempty(validSegments) || length(validSegments) < 2
    error('Valid data segments not found.');
end

% Define the range for valid data based on identified segments
validStartIndex = oneIndices(validSegments(1));
validEndIndex = oneIndices(validSegments(2));

% Extract the valid data range
validData = rawData(validStartIndex:validEndIndex, :);

% Compare extracted data with theoretical data for further refinement
% comparisonResults = compareData(validData(:, columns), theoData);
% refinedDataIndices = find(comparisonResults);  % Rows closely matching theoretical data
% TODO: Get the column that closely match the theoretical data
% refinedDataIndices = validData(:,columns(1));

% Define map for selecting the correct Y column index based on sensor and dataType
yColumnMap = containers.Map(...
    {'FAngVel', 'FAngle', 'EAngVel', 'EAngle', 'GAngVel', 'GAngle'}, ...
    {1, 2, 1, 3, 1, 3});

% Get the correct Y column index using the map
yColumnIndex = columns(yColumnMap([sensorID dataType]));

YData = validData(:, yColumnIndex);
XData = validData(:, 2);
% Refine data by ensuring continuity and removing spikes (maybe do later)
% refinedData = validData(refinedDataIndices, :);
% continuousData = removeSpikes(refinedData, columns);

% Store processed data for output
coolTermData.Time = XData;  % Time column
coolTermData.Values = YData;  % Extracted values based on dataType and sensor
end

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


function witMotionData = processWitMotionData(rawData, sensorType, dataType)
    % Constants for column indices based on data type
    TIME_COL = 1; % Time column index
    SENSOR_ID_COL = 2; % Sensor ID column index
    ANGLE_Y_COL = 11; % Column index for Angle Y

    % Mapping sensor types to their corresponding sensor ID
    sensorMap = containers.Map(...
        {'H', 'I'}, ...
        {'WT901BLE68(ef:e4:2c:bf:73:a9)', 'WT901BLE68(d2:5a:50:4a:21:12)'});
    inputLinkID = sensorMap('H');  % Always use sensor 'H' for zero crossing reference

    % Filter data for the input link to find zero crossings
    inputLinkData = rawData(strcmp(rawData{:, SENSOR_ID_COL}, inputLinkID), :);
    zeroCrossings = find(diff(sign(table2array(inputLinkData(:, ANGLE_Y_COL)))) > 0) + 1;
    if length(zeroCrossings) < 2
        error('Not enough zero crossings found for input link.');
    end

    % Determine start and end times for valid data using input link zero crossings
    validStartTime = duration(table2array(inputLinkData(zeroCrossings(1), TIME_COL)));
    validEndTime = duration(table2array(inputLinkData(zeroCrossings(2), TIME_COL)));

    % Filter data for the current sensor type
    sensorID = sensorMap(sensorType);
    sensorData = rawData(strcmp(rawData{:, SENSOR_ID_COL}, sensorID), :);

    % Find indices in sensorData that are within the valid time range determined by the input link
    validIndices = sensorData{:, TIME_COL} >= validStartTime & sensorData{:, TIME_COL} <= validEndTime;
    if sum(validIndices) == 0
        error('No data found for the current sensor within the valid time range.');
    end

    % Extract data slice based on the valid time indices
    validData = sensorData(validIndices, :);

    % Further refinement based on dataType to extract only relevant data
    dataColumns = getDataColumns(dataType);
    refinedData = validData(:, dataColumns);

    % Prepare output structure
    witMotionData = struct();
    witMotionData.Time = validData(:, TIME_COL);
    % TODO: Update this accordingly
    witMotionData.Values = refinedData(:,1);
    % witMotionData.Values = refinedData;
    witMotionData.SensorID = sensorID;  % Include sensor ID in the output for reference
end

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
function theoData = retrieveTheoData(dataSet, expData, sensor, dataType, speed)
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
if any(strcmp(dataType, {'LinVel', 'LinAcc', 'Point'}))  % These involve Joint or LinkCoM
    if length(sensor) == 1  % Assuming sensor names for Joints are single characters
        subCategory = 'Joint';
    else
        subCategory = 'LinkCoM';
    end
else  % For angular data types or position, the sensor directly maps to data
    subCategory = '';
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

    % Dynamically find the appropriate sensor field that contains the sensor ID
    theoData = [];
    if ~isempty(dataField)
        sensorFields = fieldnames(dataField);
        for i = 1:length(sensorFields)
            if contains(sensorFields{i}, sensor)
                % Handle cases with and without speed specification
                if ~isempty(speed) && isfield(dataField.(sensorFields{i}), speed)
                    theoData = table2array(dataField.(sensorFields{i}).(speed)(:,3));
                else
                    % Assuming expData and theoData are columns of
                    % angles. TODO: There may be condition that this is
                    % a joint position... Adjust accordingly if
                    % desired...
                    theoData = double(dataField.(sensorFields{i}){:, 3});
                    % TODO: Make sure I have table2array in appropriate
                    % places so I don't have to call it here
                    adjustment = table2array(expData.Values(1,1)) - theoData(1,1);
                    theoData = theoData + adjustment;
                    % theoData = dataField.(sensorFields{i});  % Get the entire data if no speed is involved
                end
            end
        end
    end
    if isempty(theoData)  % If no matching sensor field is found
        theoData = [];  % Return empty if not found
    end
catch
    theoData = [];  % Return empty if any field is not found or any error occurs
end
end


function rmseResults = calculateRMSE(expDataSet, theoDataSet, sensor, dataType, speed)
% rmseResults = struct(); % Initialize results structure

% Retrieve experimental and theoretical data for the given sensor, dataType, and speed
expData = retrieveExpData(expDataSet, sensor, dataType, speed);
theoData = retrieveTheoData(theoDataSet, expData, sensor, dataType, speed);

% Calculate RMSE if both experimental and theoretical data are available
if ~isempty(expData) && ~isempty(theoData)
    rpmValue = str2double(regexp(speed, '\d+', 'match'));  % Extract numerical part from speed string like 'f10RPM'
    timePerRevolution = 60 / rpmValue;  % Calculate the time for one full revolution (in seconds)
    numDataPoints = size(theoData, 1);  % Number of data points in the theoretical data
    theoreticalTime = linspace(0, timePerRevolution, numDataPoints);  % Create a linearly spaced time array
    theoreticalTime = theoreticalTime.';

    % Calculate RMSE if both experimental and theoretical data are available
    timestampsRaw = expData.Time;
    timestamps = timestampsRaw - timestampsRaw(1,1);
    timestamps = table2array(timestamps) / 1000;

    interpolatedTheoData = interp1(theoreticalTime, theoData, timestamps, 'linear', 'extrap');
    rmse = sqrt(mean((expData.Values - interpolatedTheoData).^2));

    % Store RMSE in the results structure
    rmseResults = table2array(rmse);
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

