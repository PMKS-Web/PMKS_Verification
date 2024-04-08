classdef GeneralUtils
    methods(Static)
        function com = determineCoM(poses)

            sumX = 0;
            sumY = 0;
            sumZ = 0;

            numPoses = size(poses, 1);
            for i = 1:numPoses
                pose = poses(i,:);
                sumX = sumX + pose(1);
                sumY = sumY + pose(2);
                sumZ = sumZ + pose(3);
            end

            % Calculate average position
            avgX = sumX / numPoses;
            avgY = sumY / numPoses;
            avgZ = sumZ / numPoses;

            com = [avgX, avgY, avgZ];
        end
        function exportMatricesToCSV(baseDir, csvDir)
            % Create CSV directory if it doesn't exist
            if ~exist(csvDir, 'dir')
                mkdir(csvDir);
            end

            % Process each .mat file
            GeneralUtils.processDirectory(baseDir, baseDir, csvDir);
        end

        function processDirectory(baseDir, currentDir, csvDir)
            items = dir(currentDir);
            for i = 1:length(items)
                if items(i).isdir && ~ismember(items(i).name, {'.', '..'})
                    % If it's a subdirectory, recursively process it
                    GeneralUtils.processDirectory(baseDir, fullfile(currentDir, items(i).name), csvDir);
                elseif ~items(i).isdir
                    % Process .mat file
                    matFilePath = fullfile(currentDir, items(i).name);
                    data = load(matFilePath);
                    fieldName = fieldnames(data);
                    if ~isempty(fieldName)
                        matrix = data.(fieldName{1});
                        if isnumeric(matrix) && size(matrix, 2) == 3
                            % Construct CSV file path
                            relPath = strrep(currentDir, baseDir, ''); % Relative path
                            csvFileName = strrep(items(i).name, '.mat', '.csv');
                            csvFilePath = fullfile(csvDir, relPath, csvFileName);

                            % Ensure subdirectory exists
                            [csvFileDir, ~, ~] = fileparts(csvFilePath);
                            if ~exist(csvFileDir, 'dir')
                                mkdir(csvFileDir);
                            end

                            % Write matrix to CSV
                            GeneralUtils.writeMatrixToCSV(matrix, csvFilePath);
                        end
                    end
                end
            end
        end

        function writeMatrixToCSV(matrix, csvFilePath)
            % Open CSV file
            fileId = fopen(csvFilePath, 'w');
            % Check if the file is opened successfully
            if fileId == -1
                error('Failed to open file for writing: %s', csvFilePath);
            end
            % Write each row of the matrix to the CSV file
            for i = 1:size(matrix, 1)
                fprintf(fileId, '%f,%f,%f\n', matrix(i, 1), matrix(i, 2), matrix(i, 3));
            end
            % Close the file
            fclose(fileId);
        end

        function projectRoot = findProjectRoot(currentDir, targetDirName)
            % Initialize projectRoot with the current directory
            projectRoot = currentDir;

            % Get the name of the current directory
            [~, currentFolderName] = fileparts(currentDir);

            % Loop until the current folder's name matches targetDirName or we hit the root directory
            while ~strcmp(currentFolderName, targetDirName)
                % Move up one directory level
                projectRoot = fileparts(projectRoot);

                % Break if we've reached the root directory
                if isempty(projectRoot) || strcmp(projectRoot, filesep)
                    error('Target directory "%s" not found in the path.', targetDirName);
                end

                % Update currentFolderName
                [~, currentFolderName] = fileparts(projectRoot);
            end
        end
    end
end