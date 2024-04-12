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
speeds = {'speed1', 'speed2', 'speed3'};

% Preallocate structure for RMSE results
rmseResults = struct();

expData = readExperimentalData(ExperimentalPath);
theoreticalData = readTheoreticalData(TheoreticalPath);

% Iterate through all sensors
for sensorIdx = 1:length(sensors)
    sensor = sensors{sensorIdx};
    link = sensorToLinkMap(sensor);

    % Depending on the sensor, choose the correct experimental path
    if any(strcmp(sensor, {'E', 'F', 'G'})) % CoolTerm sensors
        experimentalPath = CoolTermExperimentalPath;
    else % WitMotion sensors
        experimentalPath = WitMotionExperimentalPath;
    end

    % Read experimental data
    expData = readExperimentalData(experimentalPath);

    % Iterate through all speeds
    for speedIdx = 1:length(speeds)
        speed = speeds{speedIdx};

        % Check if both experimental and theoretical data are available for this sensor at this speed
        if isfield(expData, sensor) && isfield(theoreticalAngVelData, link) && isfield(theoreticalAngVelData.(link), speed)
            % Access the experimental data
            expAngVel = expData.(sensor).AngVel; % Placeholder: adjust according to your data structure
            timestamps = expData.(sensor).Time; % Placeholder: adjust according to your data structure

            % Access the theoretical data
            theoAngVel = theoreticalAngVelData.(link).(speed).AngVel; % Placeholder: adjust according to your data structure
            theoTimestamps = theoreticalAngVelData.(link).(speed).Time; % Placeholder: adjust according to your data structure

            % Interpolate theoretical data to match experimental timestamps
            interpolatedTheoAngVel = interp1(theoTimestamps, theoAngVel, timestamps, 'linear', 'extrap');

            % Compute RMSE between experimental and interpolated theoretical angular velocities
            rmse = sqrt(mean((expAngVel - interpolatedTheoAngVel).^2));

            % Store the RMSE result
            rmseResults.(sensor).(speed) = rmse;
        else
            warning('Data missing for sensor %s at speed %s', sensor, speed);
        end
    end
end

% function linkData = readExperimentalLinkData(basePath)
%     files = dir(fullfile(basePath, '*.csv')); % List all CSV files in the directory
%     linkData = struct('linkName', {}, 'data', {}); % Initialize empty struct array
%
%     for i = 1:length(files)
%         linkName = files(i).name(1:end-4); % Remove '.csv' from filename to get link name
%         filePath = fullfile(files(i).folder, files(i).name);
%         linkData(i).linkName = linkName;
%         linkData(i).data = readtable(filePath); % Read CSV file into table
%     end
% end
function jointData = readTheoreticalJointData(basePath)
speeds = {'speed1', 'speed2', 'speed3'}; % Define the different speeds
jointData = struct(); % Initialize an empty struct for storing data

files = dir(fullfile(basePath, '*.csv')); % List all CSV files in the directory
for i = 1:length(files)
    fileName = files(i).name;
    filePath = fullfile(files(i).folder, fileName);

    Extract the joint name and speed from the file name
    [jointName, speedTag] = strtok(fileName, '_');
    speedTag = erase(speedTag, ['.csv', '_']); % Remove extra characters to isolate the speed tag

    Check if the speed tag is one of the defined speeds
    if any(strcmp(speeds, speedTag))
        Read CSV file into table
        data = readtable(filePath);

        Store data in struct using dynamic field names for joint and speed
        if isfield(jointData, jointName)
            jointData.(jointName).(speedTag) = data;
        else
            jointData.(jointName) = struct(speedTag, data);
        end
    end
end
end

function linkAngVelData = readTheoreticalLinkData(basePath)
linkNames = {'ABEH', 'BCFG', 'CDI'}; % Define the links you're interested in
speeds = {'speed1', 'speed2', 'speed3'}; % Speed variants
linkAngVelData = struct(); % Initialize empty struct

for linkIdx = 1:length(linkNames)
    for speedIdx = 1:length(speeds)
        fileName = sprintf('%s.csv_%s.csv', linkNames{linkIdx}, speeds{speedIdx});
        fullPath = fullfile(basePath, fileName);

        if isfile(fullPath)
            data = readtable(fullPath);
            if ~isfield(linkAngVelData, linkNames{linkIdx})
                linkAngVelData.(linkNames{linkIdx}) = struct();
            end
            linkAngVelData.(linkNames{linkIdx}).(speeds{speedIdx}) = data;
        else
            warning('File does not exist: %s', fullPath);
        end
    end
end
end

function adjustedAngles = determineAngles(jointData)
% Assuming jointData is a structure or table with fields 'jointID' and 'angle'
% Initialize an array to store adjusted angles with the same size as the input
if ~isempty(jointData) && isfield(jointData(1), 'data')
    % Assuming all 'data' fields have the same number of rows (361 in your case)
    numberOfRows = 5;
    % Adjusted initialization of adjustedAngles based on dynamic size
    adjustedAngles = zeros(numberOfRows, length(jointData)); % Flipped to match 361x6
else
    % Handle the case where jointData might be empty or not properly structured
    adjustedAngles = []; % Or any other fallback initialization
end

% Create a map from 'jointData'
jointIndexMap = containers.Map('KeyType', 'char', 'ValueType', 'int32');

for i = 1:length(jointData)
    jointIndexMap(jointData(i).jointName) = i;
end

for theta_iterator = 1:size(jointData(1))
    for rowNum = 1:5
        % Determine the offset based on jointID. Example adjustments:
        if theta_iterator == 1 % For joint A with respect to another joint
            % Pull the appropriate joint values
            A = table2array(jointData(jointIndexMap('A')).data(theta_iterator,:));
            B = table2array(jointData(jointIndexMap('B')).data(theta_iterator,:));
            angle = atan2(B(2) - A(2), B(1) - A(1));
            % TODO: Do this process for all desired joint positions
            adjustedAngles(rowNum, theta_iterator) = 180 - angle;
        elseif theta_iterator == 2 % For joint B
            A = table2array(jointData(jointIndexMap('A')).data(theta_iterator,:));
            B = table2array(jointData(jointIndexMap('B')).data(theta_iterator,:));
            angle = atan2(B(2) - A(2), B(1) - A(1));
            %CHECK ON THIS PART
            your_offset_AB = 180-angle;

            adjustedAngles(theta_iterator) = theta + your_offset_AB;
        elseif theta_iterator == 3 % For joint C
            % Adjust angle based on your criteria for joint B
            adjustedAngles(theta_iterator) = theta + your_offset_AB;
        elseif theta_iterator == 4 % For joint D
            % Adjust angle based on your criteria for joint B
            adjustedAngles(theta_iterator) = theta + your_offset_AB;
        elseif theta_iterator == 5 % For joint E
            % Adjust angle based on your criteria for joint B
            adjustedAngles(theta_iterator) = theta + your_offset_AB;
        elseif theta_iterator == 6 % For joint F
            % Default case if no specific offset criteria are met
            adjustedAngles(theta_iterator) = theta; % No adjustment
        end
        % Add more conditions as needed for other joints
    end
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
                expData.(subFolders{i}).(safeFieldName) = readtable(xlsxPath, 'Range', 'A1'); % Adjust 'Range' if necessary
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

function data =  readExperimentalCoolTermData(CoolTermExperimentalPath)
% Directory and filenames setup
dirPath = fullfile(CoolTermExperimentalPath); % Adjust base path as necessary
filenames = {'10RPM.xlsx', '20RPM.xlsx', '30RPM.xlsx'};

% Initialize an empty table for concatenated results
concatenatedData = [];

% Loop to Process Each File
for i = 1:length(filenames)
    fullPath = fullfile(dirPath, filenames{i});

    % Check if the file exists before attempting to read
    if isfile(fullPath)
        % Detect import options based on the current file and sheet
        opts = detectImportOptions(fullPath, 'NumHeaderLines', 3);
        % Read the data into a table
        tempData = readtable(fullPath, opts);

        % Concatenate the new data table to the existing data
        if isempty(concatenatedData)
            concatenatedData = tempData;
        else
            concatenatedData = [concatenatedData; tempData]; % Assuming the data structure is the same across files
        end
    else
        warning('File does not exist: %s', fullPath);
    end
end


% Process concatenated data to find specific sensor values
% Note: The following processing assumes 'concatenatedData' structure is consistent across files

% Adjust column name as per your actual data structure
hallSensorColumn = concatenatedData.Var3;
oneIndices = find(hallSensorColumn == 1);

if length(oneIndices) < 2
    disp('Not enough data points where Hall sensor equals 1.');
    return; % Exit if not enough data points
end

% Find the correct indices as per your logic
secondOneIndex = oneIndices(2);
nextOneIndexArray = oneIndices(oneIndices > secondOneIndex + 1);

x = length(oneIndices);
i=1;
while (i < x)
    indexDifference = oneIndices(i+1) - oneIndices(i);
    if (indexDifference ==1)
        oneIndices = [oneIndices(1:i); oneIndices(i+2:end)];
    end
    x = length(oneIndices);
    i = i + 1;
end

if isempty(nextOneIndexArray)
    disp('No subsequent non-consecutive 1 found after the second occurrence.');
    return; % Exit if no subsequent non-consecutive 1 found
else
    nextOneIndex = nextOneIndexArray(1);
end

% Assuming 'OrientationX', 'OrientationY', 'OrientationZ', and 'GyroY' are column names
% Extract and store required data from concatenatedData based on identified indices

data.timestep = concatenatedData.Var2(secondOneIndex:nextOneIndex);
data.MPUOrientationX = concatenatedData.Var5(secondOneIndex:nextOneIndex);
data.MPUOrientationY = concatenatedData.Var6(secondOneIndex:nextOneIndex);
data.MPUOrientationZ = concatenatedData.Var7(secondOneIndex:nextOneIndex);
data.MPUGyroY = concatenatedData.Var4(secondOneIndex:nextOneIndex);

data.BNOCouplerOrientationX = concatenatedData.Var8(secondOneIndex:nextOneIndex);
data.BNOCouplerOrientationY = concatenatedData.Var9(secondOneIndex:nextOneIndex);
data.BNOCouplerOrientationZ = concatenatedData.Var10(secondOneIndex:nextOneIndex);
data.BNOCouplerGyroX = concatenatedData.Var11(secondOneIndex:nextOneIndex);
data.BNOCouplerGyroY = concatenatedData.Var12(secondOneIndex:nextOneIndex);
data.BNOCouplerGyroZ = concatenatedData.Var13(secondOneIndex:nextOneIndex);

data.BNORockerOrientationX = concatenatedData.Var14(secondOneIndex:nextOneIndex);
data.BNORockerOrientationY = concatenatedData.Var15(secondOneIndex:nextOneIndex);
data.BNORockerOrientationZ = concatenatedData.Var16(secondOneIndex:nextOneIndex);
data.BNORockerGyroX = concatenatedData.Var17(secondOneIndex:nextOneIndex);
data.BNORockerGyroY = concatenatedData.Var18(secondOneIndex:nextOneIndex);
data.BNORockerGyroZ = concatenatedData.Var19(secondOneIndex:nextOneIndex);

end

function WMdata = readExperimentalWitMotionData(WitMotionExperimentalPath)
dirPath = fullfile(WitMotionExperimentalPath); % Adjust base path as necessary
filenames = {'10RPM.csv', '20RPM.csv', '30RPM.csv'};

% Initialize an empty table for concatenated results
concatenatedData = [];

% Loop to Process Each File
for i = 1:length(filenames)
    fullPath = fullfile(dirPath, filenames{i});

    % Check if the file exists before attempting to read
    if isfile(fullPath)
        % Detect import options based on the current file and sheet
        opts = detectImportOptions(fullPath, 'NumHeaderLines', 1);
        % Read the data into a table
        tempData = readtable(fullPath, opts);

        % Concatenate the new data table to the existing data
        if isempty(concatenatedData)
            concatenatedData = tempData;
        else
            concatenatedData = [concatenatedData; tempData]; % Assuming the data structure is the same across files
        end
    else
        warning('File does not exist: %s', fullPath);
    end
end
deviceNames = concatenatedData.Var2;
% Find unique strings and their first occurrence index
[uniqueStrings, ia, ~] = unique(deviceNames, 'stable');

% Find indices of each unique string in the original list
indicesForEachUniqueString = cell(length(uniqueStrings), 1);
for i = 1:length(uniqueStrings)
    indicesForEachUniqueString{i} = find(ismember(deviceNames, uniqueStrings(i)));
end

table2 = indicesForEachUniqueString{2,1};
table1 = indicesForEachUniqueString{1,1};

a9concatenatedData = concatenatedData(table2, :);
twelveconcatenatedData = concatenatedData(table1, :);

for i  = 1:size(table2)
    a9Index = table2(i);
    a9data(i,:) = concatenatedData.Var11(a9Index);

end
%
% for i = 1:size(table1)
%     twelveIndex = table1(i);
%     twelvedata(i, :) = concatenatedData(twelveIndex);
% end

% Once this is pulled, then we want to determine the time range. Time
% range will be defined from the first instance that the YAngle goes
% from negative to positive to the next instance.
oneIndex = -1;
secondOneIndex = -1;
for i=1:length(a9data)
    a9current = a9data(i);
    a9next = a9data(i+1);

    if a9current <0 && a9next > 0
        if oneIndex == -1
            oneIndex = i+1;
        elseif secondOneIndex ==-1
            secondOneIndex = i+1;
            break
        end
    end

end
cat = 390482;
% Afterward, we will cut the index values that are not needed. We know
% what is not needed if the row values precede or exceed the time
% range.

% Lastly, We store the desired angle and angular velocity of the sensor
%
% Assuming 'OrientationX', 'OrientationY', 'OrientationZ', and 'GyroY' are column names
% Extract and store required data from concatenatedData based on identified indices

WMdata.WMtimestep = a9concatenatedData.Var1(oneIndex:secondOneIndex);

WMdata.InputXAngle = a9concatenatedData.Var10(oneIndex:secondOneIndex);
WMdata.InputYAngle = a9concatenatedData.Var11(oneIndex:secondOneIndex);
WMdata.InputZAngle = a9concatenatedData.Var12(oneIndex:secondOneIndex);

WMdata.InputXVel = a9concatenatedData.Var7(oneIndex:secondOneIndex);
WMdata.InputYVel = a9concatenatedData.Var8(oneIndex:secondOneIndex);
WMdata.InputZVel = a9concatenatedData.Var9(oneIndex:secondOneIndex);

WMdata.OutputXAngle = twelveconcatenatedData.Var10(oneIndex:secondOneIndex);
WMdata.OutputYAngle = twelveconcatenatedData.Var11(oneIndex:secondOneIndex);
WMdata.OutputZAngle = twelveconcatenatedData.Var12(oneIndex:secondOneIndex);

WMdata.OutputXVel = twelveconcatenatedData.Var7(oneIndex:secondOneIndex);
WMdata.OutputYVel = twelveconcatenatedData.Var8(oneIndex:secondOneIndex);
WMdata.OutputZVel = twelveconcatenatedData.Var9(oneIndex:secondOneIndex);



end

% Placeholder for processing; adapt based on your actual needs
function compareAngVel(expData, theoData)
% Example: Compare angular velocity for a specific joint and link
% This is highly dependent on how your data is structured and needs to be adjusted
% Assume expData and theoData are structured to facilitate direct comparison

jointName = 'E'; % Example
linkName = 'ABEH'; % The link this joint is part of
speed = 'speed1'; % Example speed variant

expAngVel = expData.(jointName).AngVel; % Placeholder: Adjust to your structure
theoAngVel = theoData.(linkName).(speed).AngVel; % Placeholder: Adjust to your structure

% Interpolation and RMSE calculation would go here
% This is a conceptual outline; specifics depend on your data's organization and needs
end

% function dataStruct = readTheoreticalData(basePath)
% % Define mappings of categories to their relevant subcategories
% categoryMap = containers.Map();
% categoryMap('Acc') = {'AngAcc', 'LinAcc'};
% categoryMap('Pos') = {'Joint', 'LinkCoM'};  % 'Pos' behaves differently
% categoryMap('Vel') = {'AngVel', 'LinVel'};
% 
% dataStruct = struct(); % Initialize the main data structure
% 
% categoryKeys = categoryMap.keys;
% for iCategory = 1:length(categoryKeys)
%     category = categoryKeys{iCategory};
%     subCategories = categoryMap(category);
%     categoryPath = fullfile(basePath, category); % Path to the current category
% 
%     % Handle Position separately due to its structure
%     if strcmp(category, 'Pos')
%         handlePosSubdirectories(categoryPath, dataStruct, category);
%     else
%         % Handle Acceleration and Velocity categories
%         for iSubCat = 1:length(subCategories)
%             subCategory = subCategories{iSubCat};
%             subCategoryPath = fullfile(categoryPath, subCategory);
% 
%             % Directly handle the specified subcategories for Acc and Vel
%             if isfolder(subCategoryPath)
%                 readAndStoreData(subCategoryPath, dataStruct, category, subCategory);
%             end
%         end
%     end
% end
% end

% function handlePosSubdirectories(path, dataStruct, category)
% posSubDirs = {'Joint', 'LinkCoM'};
% 
% for iDir = 1:length(posSubDirs)
%     dirPath = fullfile(path, posSubDirs{iDir});
% 
%     % Check if the directory exists; if not, continue to the next
%     if isfolder(dirPath)
%         readAndStoreData(dirPath, dataStruct, category, posSubDirs{iDir});
%     end
% end
% end

% function dataStruct = readAndStoreData(path, category, posSubDir, dataStruct)
%     csvFiles = dir(fullfile(path, '*.csv'));
% 
%     for file = csvFiles'
%         % Extract information from the filename using regexp correctly
%         tokens = regexp(file.name, '^(.+?)_(speed\d+)\.csv$', 'tokens');
%         if isempty(tokens) || isempty(tokens{1})
%             continue; % Skip if the filename doesn't match the expected pattern or tokens are empty
%         end
% 
%         % Correctly access the tokens based on the structure returned by regexp
%         itemName = tokens{1}{1};  % Corrected access
%         speed = tokens{1}{2};     % Corrected access
% 
%         % Read the CSV file into a table
%         dataTable = readtable(fullfile(file.folder, file.name));
% 
%         % Ensure categories and subcategories exist in dataStruct
%         if ~isfield(dataStruct, category)
%             dataStruct.(category) = struct();
%         end
%         if ~isfield(dataStruct.(category), posSubDir)
%             dataStruct.(category).(posSubDir) = struct();
%         end
%         if ~isfield(dataStruct.(category).(posSubDir), itemName)
%             dataStruct.(category).(posSubDir).(itemName) = struct();
%         end
% 
%         % Assign the table to the correct location in dataStruct
%         dataStruct.(category).(posSubDir).(itemName).(speed) = dataTable;
%     end
% end

% function dataStruct = readTheoreticalData(basePath)
%     % Define mappings of categories to their relevant subcategories
%     categoryMap = containers.Map({'Acc', 'Pos', 'Vel'}, ...
%                                  {{'AngAcc', 'LinAcc'}, {'Joint', 'LinkCoM'}, {'AngVel', 'LinVel'}});
% 
%     dataStruct = struct(); % Initialize the main data structure
% 
%     % Iterate over each category like Acc, Pos, Vel
%     for k = categoryMap.keys
%         category = k{1};
%         subCategories = categoryMap(category);
%         categoryPath = fullfile(basePath, category); % Path to the current category
% 
%         % Handle each subcategory appropriately
%         for subCategory = subCategories
%             subCategoryPath = fullfile(categoryPath, subCategory{1});
% 
%             % Check if it's a 'Pos' category for different handling
%             if strcmp(category, 'Pos')
%                 handlePosSubdirectories(subCategoryPath, dataStruct, category, subCategory{1});
%             else
%                 % For Acc and Vel categories
%                 handleGeneralSubdirectories(subCategoryPath, dataStruct, category, subCategory{1});
%             end
%         end
%     end
% end
% 
% function handlePosSubdirectories(path, dataStruct, category, posSubDir)
%     % Read and handle files directly in the Pos subdirectories
%     readAndStoreData(path, dataStruct, category, posSubDir);
% end
% 
% function handleGeneralSubdirectories(path, dataStruct, category, subCategory)
%     % Check if there are further subcategories like Joint or LinkCoM
%     furtherSubs = {'Joint', 'LinkCoM'};
%     for sub = furtherSubs
%         subPath = fullfile(path, sub{1});
%         if isfolder(subPath)
%             readAndStoreData(subPath, dataStruct, category, subCategory, sub{1});
%         end
%     end
% end
% 
% function readAndStoreData(path, dataStruct, category, subCategory, furtherSub)
%     csvFiles = dir(fullfile(path, '*.csv'));
%     for file = csvFiles'
%         % Extract filename components correctly
%         [itemName, speeds] = strtok(file.name, '_');
%         speedTag = regexprep(speeds, {'_','.csv'}, ''); % Remove underscore and '.csv'
% 
%         % Construct the path to read the file
%         fullPath = fullfile(file.folder, file.name);
%         dataTable = readtable(fullPath);
% 
%         % Ensure the hierarchical structure in dataStruct
%         if ~isfield(dataStruct, category)
%             dataStruct.(category) = struct();
%         end
%         if ~isfield(dataStruct.(category), subCategory)
%             dataStruct.(category).(subCategory) = struct();
%         end
%         if ~isfield(dataStruct.(category).(subCategory), furtherSub)
%             dataStruct.(category).(subCategory).(furtherSub) = struct();
%         end
% 
%         % Store data
%         if ~isfield(dataStruct.(category).(subCategory).(furtherSub), itemName)
%             dataStruct.(category).(subCategory).(furtherSub).(itemName) = struct();
%         end
% 
%         dataStruct.(category).(subCategory).(furtherSub).(itemName).(speedTag) = dataTable;
%     end
% end

% function dataStruct = readTheoreticalData(basePath)
%     % Define mappings of categories to their relevant subcategories
%     categoryMap = containers.Map({'Acc', 'Vel', 'Pos'}, ...
%                                  {{'AngAcc', 'LinAcc'}, {'AngVel', 'LinVel'}, {'Joint', 'LinkCoM'}});
% 
%     dataStruct = struct(); % Initialize the main data structure
% 
%     % Iterate over each category like Acc, Pos, Vel
%     for k = categoryMap.keys
%         category = k{1};
%         subCategories = categoryMap(category);
%         categoryPath = fullfile(basePath, category); % Path to the current category
% 
%         % Handle each subcategory appropriately
%         for subCategory = subCategories
%             subCategoryPath = fullfile(categoryPath, subCategory{1});
% 
%             % Check if it's a 'Pos' category for different handling
%             if strcmp(category, 'Pos')
%                 dataStruct = handlePosSubdirectories(subCategoryPath, dataStruct, category);
%             else
%                 % For Acc and Vel categories
%                 dataStruct = handleGeneralSubdirectories(subCategoryPath, dataStruct, category, subCategory{1});
%             end
%         end
%     end
% end
% 
% function dataStruct = handlePosSubdirectories(path, dataStruct, category)
%     % Directly handle files in Pos subdirectories
%     subDirs = {'Joint', 'LinkCoM'};
%     for iSubDir = 1:length(subDirs)
%         subDirPath = fullfile(path, subDirs{iSubDir});
%         if isfolder(subDirPath)
%             dataStruct = readAndStoreData(subDirPath, dataStruct, category, subDirs{iSubDir});
%         end
%     end
% end
% 
% function dataStruct = handleGeneralSubdirectories(path, dataStruct, category, subCategory)
%     % Read and store files directly in general subcategories
%     dataStruct = readAndStoreData(path, dataStruct, category, subCategory);
% end
% 
% function dataStruct = readAndStoreData(path, dataStruct, category, subCategory)
%     csvFiles = dir(fullfile(path, '*.csv'));
%     for file = csvFiles'
%         % Extract filename components correctly
%         [itemName, speeds] = strtok(file.name, '_');
%         speedTag = regexprep(speeds, {'_','.csv'}, ''); % Remove underscore and '.csv'
% 
%         % Construct the path to read the file
%         fullPath = fullfile(file.folder, file.name);
%         dataTable = readtable(fullPath);
% 
%         % Ensure the hierarchical structure in dataStruct
%         if ~isfield(dataStruct, category)
%             dataStruct.(category) = struct();
%         end
%         if ~isfield(dataStruct.(category), subCategory)
%             dataStruct.(category).(subCategory) = struct();
%         end
% 
%         % Initialize further if needed
%         if ~isfield(dataStruct.(category).(subCategory), itemName)
%             dataStruct.(category).(subCategory).(itemName) = struct();
%         end
% 
%         dataStruct.(category).(subCategory).(itemName).(speedTag) = dataTable;
%     end
% end

% function dataStruct = readTheoreticalData(basePath)
%     % Define mappings of categories to their relevant subcategories
%     categoryMap = containers.Map({'Acc', 'Vel', 'Pos'}, ...
%                                  {{'AngAcc', 'LinAcc'}, {'AngVel', 'LinVel'}, {'Joint', 'LinkCoM'}});
% 
%     dataStruct = struct(); % Initialize the main data structure
% 
%     % Iterate over each category like Acc, Pos, Vel
%     for k = categoryMap.keys
%         category = k{1};
%         subCategories = categoryMap(category);
%         categoryPath = fullfile(basePath, category); % Path to the current category
% 
%         % Process each subcategory appropriately
%         for subCategoryIndex=1:1:length(subCategories)
%             subCategory = subCategories(subCategoryIndex);
%             subCategoryPath = fullfile(categoryPath, subCategory); % Correct subcategory path construction
% 
%             if strcmp(category, 'Pos')
%                 % Handle Position differently, assuming it directly contains files
%                 dataStruct = handlePosSubdirectories(subCategoryPath, dataStruct, category, subCategory);
%             else
%                 % For Acc and Vel categories with further subcategories
%                 dataStruct = handleGeneralSubdirectories(subCategoryPath, dataStruct, category, subCategory);
%             end
%         end
%     end
% end
% 
% function dataStruct = handlePosSubdirectories(path, dataStruct, category, subCategory)
%     % Check if the directory exists; if not, continue to the next
%     if isfolder(path)
%         dataStruct = readAndStoreData(path, dataStruct, category, subCategory);
%     end
% end
% 
% function dataStruct = handleGeneralSubdirectories(path, dataStruct, category, subCategory)
%     % Read and store files directly in general subcategories
%     if isfolder(path)
%         dataStruct = readAndStoreData(path, dataStruct, category, subCategory);
%     end
% end
% 
% function dataStruct = readAndStoreData(path, dataStruct, category, subCategory)
%     csvFiles = dir(fullfile(path{1}, '*.csv'));
%     for file = csvFiles'
%         % Correctly extract item name and speed tag from filename
%         tokens = regexp(file.name, '^(.+?)_(speed\d+)\.csv$', 'tokens');
%         if isempty(tokens)
%             continue; % Skip if filename doesn't match expected format
%         end
% 
%         itemName = tokens{1}{1};
%         speedTag = tokens{1}{2};
% 
%         % Read the CSV file into a table
%         dataTable = readtable(fullfile(file.folder, file.name));
% 
%         % Create nested structures based on category and subcategory
%         if ~isfield(dataStruct, category)
%             dataStruct.(category) = struct();
%         end
%         if ~isfield(dataStruct.(category), subCategory{1})
%             dataStruct.(category).(subCategory{1}) = struct();
%         end
%         if ~isfield(dataStruct.(category).(subCategory{1}), itemName)
%             dataStruct.(category).(subCategory{1}).(itemName) = struct();
%         end
%         dataStruct.(category).(subCategory{1}).(itemName).(speedTag) = dataTable;
%     end
% end

% function dataStruct = readTheoreticalData(basePath)
%     % Define mappings of categories to their relevant subcategories
%     categoryMap = containers.Map({'Acc', 'Vel', 'Pos'}, ...
%                                  {{'AngAcc', 'LinAcc'}, {'AngVel', 'LinVel'}, {'Joint', 'LinkCoM'}});
% 
%     dataStruct = struct();  % Initialize the main data structure
% 
%     % Iterate over each category like Acc, Pos, Vel
%     for k = categoryMap.keys()
%         category = k{1};
%         subCategories = categoryMap(category);
%         categoryPath = fullfile(basePath, category);
% 
%         for subCategory = subCategories
%             subCategoryPath = fullfile(categoryPath, subCategory{1});
% 
%             % Check if further nesting is required (for LinAcc or LinVel)
%             if any(strcmp(subCategory{1}, {'LinAcc', 'LinVel'}))
%                 nestedDirs = {'Joint', 'LinkCoM'};
%                 for nestedDir = nestedDirs
%                     nestedPath = fullfile(subCategoryPath, nestedDir{1});
%                     if isfolder(nestedPath)
%                         dataStruct = readNestedData(nestedPath, dataStruct, category, subCategory{1}, nestedDir{1});
%                     end
%                 end
%             else
%                 dataStruct = readDataFromDir(subCategoryPath, dataStruct, category, subCategory{1});
%             end
%         end
%     end
% end
% 
% function dataStruct = readNestedData(path, dataStruct, category, subCategory, nestedDir)
%     % Read data from nested directories like Joint and LinkCoM under LinAcc and LinVel
%     csvFiles = dir(fullfile(path, '*.csv'));
%     for file = csvFiles'
%         [itemName, speedTag] = parseFileName(file.name);
%         if isempty(itemName)
%             continue;
%         end
%         dataTable = readtable(fullfile(file.folder, file.name));
%         dataStruct = updateDataStruct(dataStruct, category, subCategory, nestedDir, itemName, speedTag, dataTable);
%     end
% end
% 
% function dataStruct = readDataFromDir(path, dataStruct, category, subCategory)
%     % Read data directly from directories that do not have further subdirectories
%     csvFiles = dir(fullfile(path, '*.csv'));
%     for file = csvFiles'
%         [itemName, speedTag] = parseFileName(file.name);
%         if isempty(itemName)
%             continue;
%         end
%         dataTable = readtable(fullfile(file.folder, file.name));
%         dataStruct = updateDataStruct(dataStruct, category, subCategory, '', itemName, speedTag, dataTable);
%     end
% end
% 
% function [itemName, speedTag] = parseFileName(fileName)
%     % Parse filenames that follow the pattern 'itemName_speedTag.csv'
%     tokens = regexp(fileName, '^(.+?)_(speed\d+)\.csv$', 'tokens');
%     if isempty(tokens)
%         itemName = '';
%         speedTag = '';
%     else
%         itemName = tokens{1}{1};
%         speedTag = tokens{1}{2};
%     end
% end
% 
% function dataStruct = updateDataStruct(dataStruct, category, subCategory, nestedDir, itemName, speedTag, dataTable)
%     % Update the data structure with new data
%     if ~isfield(dataStruct, category)
%         dataStruct.(category) = struct();
%     end
%     if ~isfield(dataStruct.(category), subCategory)
%         dataStruct.(category).(subCategory) = struct();
%     end
%     targetSubCategory = nestedDir;
%     if ~isempty(nestedDir) && ~isfield(dataStruct.(category).(subCategory), nestedDir)
%         dataStruct.(category).(subCategory).(nestedDir) = struct();
%         targetSubCategory = nestedDir;
%     end
%     if ~isfield(dataStruct.(category).(subCategory).(targetSubCategory), itemName)
%         dataStruct.(category).(subCategory).(targetSubCategory).(itemName) = struct();
%     end
%     dataStruct.(category).(subCategory).(targetSubCategory).(itemName).(speedTag) = dataTable;
% end
% 

% function dataStruct = readTheoreticalData(basePath)
%     % Define mappings of categories to their relevant subcategories
%     categoryMap = containers.Map({'Acc', 'Vel', 'Pos'}, ...
%                                  {{'AngAcc', 'LinAcc'}, {'AngVel', 'LinVel'}, {'Joint', 'LinkCoM'}});
% 
%     dataStruct = struct();  % Initialize the main data structure
% 
%     % Iterate over each category like Acc, Pos, Vel
%     for k = categoryMap.keys()
%         category = k{1};
%         subCategories = categoryMap(category);
%         categoryPath = fullfile(basePath, category);
% 
%         for subCategory = subCategories
%             subCategoryPath = fullfile(categoryPath, subCategory{1});
% 
%             % Check if further nesting is required (for LinAcc or LinVel)
%             if any(strcmp(subCategory{1}, {'LinAcc', 'LinVel'}))
%                 nestedDirs = {'Joint', 'LinkCoM'};
%                 for nestedDir = nestedDirs
%                     nestedPath = fullfile(subCategoryPath, nestedDir{1});
%                     if isfolder(nestedPath)
%                         dataStruct = readNestedData(nestedPath, dataStruct, category, subCategory{1}, nestedDir{1});
%                     end
%                 end
%             else
%                 dataStruct = readDataFromDir(subCategoryPath, dataStruct, category, subCategory{1});
%             end
%         end
%     end
% end
% function dataStruct = readTheoreticalData(basePath)
%     % Define mappings of categories to their relevant subcategories
%     categoryMap = containers.Map({'Acc', 'Vel', 'Pos'}, ...
%                                  {{'AngAcc', 'LinAcc'}, {'AngVel', 'LinVel'}, {'Joint', 'LinkCoM'}});
% 
%     dataStruct = struct(); % Initialize the main data structure
% 
%     % Iterate over each category like Acc, Pos, Vel
%     for k = categoryMap.keys
%         category = k{1};
%         subCategories = categoryMap(category);
%         categoryPath = fullfile(basePath, category); % Path to the current category
% 
%         % Process each subcategory appropriately
%         for subCategory = subCategories
%             subCategoryPath = fullfile(categoryPath, subCategory{1});
% 
%             if strcmp(category, 'Pos')
%                 % Handle Position differently, assuming it directly contains files
%                 dataStruct = readDataFromDirectory(subCategoryPath, dataStruct, category, subCategory{1}, '');
%             else
%                 % For Acc and Vel categories with further subcategories
%                 subDirs = {'Joint', 'LinkCoM'}; % Assume these are the possible nested directories
%                 for subDir = subDirs
%                     nestedPath = fullfile(subCategoryPath, subDir{1});
%                     if isfolder(nestedPath)
%                         dataStruct = readDataFromDirectory(nestedPath, dataStruct, category, subCategory{1}, subDir{1});
%                     end
%                 end
%             end
%         end
%     end
% end

function dataStruct = readTheoreticalData(basePath)
    % Define mappings of categories to their relevant subcategories
    categoryMap = containers.Map({'Acc', 'Vel', 'Pos'}, ...
                                 {{'AngAcc', 'LinAcc'}, {'AngVel', 'LinVel'}, {'Joint', 'LinkCoM'}});

    dataStruct = struct(); % Initialize the main data structure

    % Iterate over each category like Acc, Pos, Vel
    for k = categoryMap.keys
        category = k{1};
        subCategories = categoryMap(category);
        categoryPath = fullfile(basePath, category); % Path to the current category

        % Process each subcategory appropriately
        for subCategory = subCategories
            subCategoryPath = fullfile(categoryPath, subCategory{1});

            if strcmp(category, 'Pos')
                % Handle Position differently, assuming it directly contains files
                dataStruct = readDataFromDirectory(subCategoryPath, dataStruct, category, subCategory{1}, '');
            else
                % For Acc and Vel categories
                % Check if we're dealing with linear components that have nested directories
                if strcmp(subCategory{1}, 'LinAcc') || strcmp(subCategory{1}, 'LinVel')
                    subDirs = {'Joint', 'LinkCoM'}; % These are the possible nested directories for linear components
                    for subDir = subDirs
                        nestedPath = fullfile(subCategoryPath, subDir{1});
                        if isfolder(nestedPath)
                            dataStruct = readDataFromDirectory(nestedPath, dataStruct, category, subCategory{1}, subDir{1});
                        end
                    end
                else
                    % Directly handle the subCategoryPath if it's Angular data
                    dataStruct = readDataFromDirectory(subCategoryPath, dataStruct, category, subCategory{1}, '');
                end
            end
        end
    end
end


function [itemName, speedTag] = parseFileName(fileName)
    % Parse filenames that follow the pattern 'itemName_speedTag.csv'
    tokens = regexp(fileName, '^(.+?)_(speed\d+)\.csv$', 'tokens');
    if isempty(tokens)
        itemName = '';
        speedTag = '';
    else
        itemName = tokens{1}{1};
        speedTag = tokens{1}{2};
    end
end

% function dataStruct = updateDataStruct(dataStruct, category, subCategory, nestedDir, itemName, speedTag, dataTable)
%     % Update the data structure with new data
%     if ~isfield(dataStruct, category)
%         dataStruct.(category) = struct();
%     end
%     if ~isfield(dataStruct.(category), subCategory)
%         dataStruct.(category).(subCategory) = struct();
%     end
% 
%     % Decide the correct subcategory layer based on whether nestedDir is provided
%     if isempty(nestedDir)
%         targetCategory = subCategory;
%     else
%         if ~isfield(dataStruct.(category).(subCategory), nestedDir)
%             dataStruct.(category).(subCategory).(nestedDir) = struct();
%         end
%         targetCategory = nestedDir;
%     end
% 
%     if ~isfield(dataStruct.(category).(subCategory).(targetCategory), itemName)
%         dataStruct.(category).(subCategory).(targetCategory).(itemName) = struct();
%     end
% 
%     dataStruct.(category).(subCategory).(targetCategory).(itemName).(speedTag) = dataTable;
% end
function dataStruct = updateDataStruct(dataStruct, category, subCategory, nestedDir, itemName, speedTag, dataTable)
    % Ensure the base category structure exists
    if ~isfield(dataStruct, category)
        dataStruct.(category) = struct();
    end

    % Ensure the sub-category structure exists
    if ~isfield(dataStruct.(category), subCategory)
        dataStruct.(category).(subCategory) = struct();
    end
    
    % Decide on the final target based on whether nestedDir is provided
    finalTarget = dataStruct.(category).(subCategory);
    if ~isempty(nestedDir)
        % Check and create nestedDir if it doesn't exist
        if ~isfield(finalTarget, nestedDir)
            finalTarget.(nestedDir) = struct();
        end
        finalTarget = finalTarget.(nestedDir);
    end

    % Ensure the item structure exists under the final target
    if ~isfield(finalTarget, itemName)
        finalTarget.(itemName) = struct();
    end
    
    % Update the final structure with the new data table under the correct speed tag
    finalTarget.(itemName).(speedTag) = dataTable;

    % Reflect the changes back to the main data structure
    if isempty(nestedDir)
        dataStruct.(category).(subCategory) = finalTarget;
    else
        dataStruct.(category).(subCategory).(nestedDir) = finalTarget;
    end
end

function dataStruct = readDataFromDirectory(path, dataStruct, category, subCategory, nestedDir)
    csvFiles = dir(fullfile(path, '*.csv'));
    for file = csvFiles'
        % Parse the file name to extract item and speed
        [itemName, speedTag] = parseFileName(file.name);
        if isempty(itemName)
            continue;
        end
        dataTable = readtable(fullfile(file.folder, file.name));
        dataStruct = updateDataStruct(dataStruct, category, subCategory, nestedDir, itemName, speedTag, dataTable);
    end
end


function dataStruct = readDataFromDir(path, dataStruct, category, subCategory)
    % Read data directly from directories that do not have further subdirectories
    csvFiles = dir(fullfile(path, '*.csv'));
    for file = csvFiles'
        [itemName, speedTag] = parseFileName(file.name);
        if isempty(itemName)
            continue;
        end
        dataTable = readtable(fullfile(file.folder, file.name));
        dataStruct = updateDataStruct(dataStruct, category, subCategory, '', itemName, speedTag, dataTable);
    end
end

function dataStruct = readNestedData(path, dataStruct, category, subCategory, nestedDir)
    % Read data from nested directories like Joint and LinkCoM under LinAcc and LinVel
    csvFiles = dir(fullfile(path, '*.csv'));
    for file = csvFiles'
        [itemName, speedTag] = parseFileName(file.name);
        if isempty(itemName)
            continue;
        end
        dataTable = readtable(fullfile(file.folder, file.name));
        dataStruct = updateDataStruct(dataStruct, category, subCategory, nestedDir, itemName, speedTag, dataTable);
    end
end

