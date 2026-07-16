classdef ForceSolverUtils
    methods(Static)
        function Mechanism = ForceSolver(Mechanism, scenarios, performForceAnalysisFunc)

            % Assuming numIterations is defined by the size of an array in Mechanism
            numIterations = size(Mechanism.Joint.A, 1);

            numSpeeds = size(Mechanism.inputSpeed, 2); % Assuming inputSpeed has dimensions: iterations x speeds

            % Initialize fields for storing static analysis data
            [Mechanism] = ForceSolverUtils.initializeForceSolvers(Mechanism, numIterations, numSpeeds, scenarios);


            % Iterate through all iterations for static analysis
            for speedIndex = 1:numSpeeds
                for iter = 1:numIterations
                    % Extract joint and link center of mass positions for this iteration
                    JointPos = ForceSolverUtils.extractJointPositions(Mechanism, iter);
                    LinkCoMPos = ForceSolverUtils.extractLinkCoMPositions(Mechanism, iter);
                    % input_speed = Mechanism.inputSpeed(iter, speedIndex); % Placeholder, adjust based on your Mechanism structure
                    % speedStr = ['f' num2str(Mechanism.input_speed_str(speedIndex)) 'RPM'];
                    speedStrTemp = strrep(num2str(Mechanism.input_speed_str(speedIndex)), '.', '_');  % Replace '.' with '_'
                    speedStr = ['f' speedStrTemp 'RPM'];  % Construct the new name

                    % Scenarios: [newtonFlag, gravityFlag, frictionFlag]
                    % scenarios = [0 0 0; 0 0 1; 0 1 0; 0 1 1; 1 0 0; 1 0 1; 1 1 0; 1 1 1];
                    for scenario = scenarios.'
                        % Mechanism = performForceAnalysisFunc(Mechanism, fieldName, iter, JointPos, LinkCoMPos, scenario);
                        Mechanism = ForceSolverUtils.updateMechanismForces(Mechanism, iter, speedStr, JointPos, LinkCoMPos, scenario(1), scenario(2), scenario(3), performForceAnalysisFunc);
                    end
                end
            end

            % Save the updated Mechanism with static analysis results
            save('Mechanism.mat', 'Mechanism');

            baseFolder = 'Force';
            % Save Force Data
            ForceSolverUtils.saveForceData(baseFolder, Mechanism);
        end

        function suffix = getSuffix(scenario)
            % Determine the type of force based on the scenario
            if scenario(1) == 1
                forceType = 'Newton';
            else
                forceType = 'Static';
            end

            % Determine the gravitational setting
            if scenario(2) == 1
                gravType = 'Grav';
            else
                gravType = 'NoGrav';
            end

            % Determine the friction setting
            if scenario(3) == 1
                frictionType = 'Friction';
            else
                frictionType = 'NoFriction';
            end

            % Concatenate parts to form the suffix
            suffix = [forceType gravType frictionType];
        end


        % function Mechanism = updateMechanismForces(Mechanism, iter, speedStr, JointPos, LinkCoMPos, newtonFlag, gravityFlag, frictionFlag, performForceAnalysisFunc)
        %     % Define the suffix based on the provided flags for readability
        %     suffix = '';
        %     if newtonFlag
        %         suffix = [suffix, 'NewtonForce'];
        %     else
        %         suffix = [suffix, 'StaticForce'];
        %     end
        %     if gravityFlag
        %         suffix = [suffix, 'Grav'];
        %     else
        %         suffix = [suffix, 'NoGrav'];
        %     end
        %     if frictionFlag
        %         suffix = [suffix, 'Friction'];
        %     else
        %         suffix = [suffix, 'NoFriction'];
        %     end
        %
        %     % Perform force analysis
        %     solution = feval(performForceAnalysisFunc, Mechanism, iter, JointPos, LinkCoMPos, newtonFlag, gravityFlag, frictionFlag);
        %     jointNames = fieldnames(Mechanism.Joint);
        %
        %     % Update forces and torques in the mechanism structure
        %     for i = 1:length(jointNames)
        %         jointName = jointNames{i};
        %         Mechanism.(suffix).Joint.(jointName)(iter, :) = [double(solution.([jointName, 'x'])), double(solution.([jointName, 'y'])), 0];
        %     end
        %     Mechanism.(suffix).Torque(iter,:) = [0 0 double(solution.T)];
        %     % Check if 'N' exists in the solution
        %     if isfield(solution, 'N')
        %         % Extract N value
        %         N = double(solution.N);
        %         % Calculate normal force components based on theta
        %         normalForceX = N * cos(Mechanism.Theta);
        %         normalForceY = N * sin(Mechanism.Theta);
        %
        %         % Update Mechanism with normal force components
        %         Mechanism.(suffix).NormalForce(iter,:) = [normalForceX, normalForceY, 0];
        %     end
        % end
        %

        function Mechanism = updateMechanismForces(Mechanism, iter, speedStr, JointPos, LinkCoMPos, newtonFlag, gravityFlag, frictionFlag, performForceAnalysisFunc)
            % Define the suffix based on the provided flags and speed for readability
            suffix = '';
            if newtonFlag
                suffix = [suffix, 'Newton'];
            else
                suffix = [suffix, 'Static'];
            end
            if gravityFlag
                suffix = [suffix, 'Grav'];
            else
                suffix = [suffix, 'NoGrav'];
            end
            if frictionFlag
                suffix = [suffix, 'Friction'];
            else
                suffix = [suffix, 'NoFriction'];
            end

            % Perform force analysis using the provided function handle
            solution = feval(performForceAnalysisFunc, Mechanism, iter, speedStr, JointPos, LinkCoMPos, newtonFlag, gravityFlag, frictionFlag);
            jointNames = fieldnames(Mechanism.Joint);

            % Define categorization based on the provided flags
            if newtonFlag
                forceType = 'Newton';
            else
                forceType = 'Static';
            end

            if gravityFlag
                gravType = 'Grav';
            else
                gravType = 'NoGrav';
            end

            if frictionFlag
                frictionType = 'Friction';
            else
                frictionType = 'NoFriction';
            end

            % Update forces and torques in the mechanism structure
            for i = 1:length(jointNames)
                jointName = jointNames{i};
                Mechanism.ForceAnalysis.(forceType).(gravType).(frictionType).(speedStr).Joint.(jointName)(iter, :) = [double(solution.([jointName, 'x'])), double(solution.([jointName, 'y'])), 0];
            end
            Mechanism.ForceAnalysis.(forceType).(gravType).(frictionType).(speedStr).Torque(iter,:) = [0 0 double(solution.T)];

            % Check if 'N' exists in the solution and update normal forces
            if isfield(solution, 'N')
                N = double(solution.N);  % Extract N value
                % The guide reaction is normal to the slider axis.
                normalForceX = -N * sin(Mechanism.Theta);
                normalForceY = N * cos(Mechanism.Theta);
                Mechanism.ForceAnalysis.(forceType).(gravType).(frictionType).(speedStr).NormalForce(iter,:) = [normalForceX, normalForceY, 0];
            end
        end

        function [Mechanism] = initializeForceSolvers(Mechanism, numIterations, numSpeeds, scenarios)
            % Initialize only requested scenarios so uncomputed combinations are
            % never exported as plausible all-zero reference data.
            jointNames = fieldnames(Mechanism.Joint);

            for scenario = scenarios.'
                if scenario(1) == 1, forceType = 'Newton'; else, forceType = 'Static'; end
                if scenario(2) == 1, gravType = 'Grav'; else, gravType = 'NoGrav'; end
                if scenario(3) == 1, frictionType = 'Friction'; else, frictionType = 'NoFriction'; end

                for speedIndex = 1:numSpeeds
                    speedStrTemp = strrep(num2str(Mechanism.input_speed_str(speedIndex)), '.', '_');
                    speedStr = ['f' speedStrTemp 'RPM'];
                    for jointIndex = 1:length(jointNames)
                        jointName = jointNames{jointIndex};
                        Mechanism.ForceAnalysis.(forceType).(gravType).(frictionType).(speedStr).Joint.(jointName) = zeros(numIterations, 3, 'double');
                    end
                    Mechanism.ForceAnalysis.(forceType).(gravType).(frictionType).(speedStr).Torque = zeros(numIterations, 3, 'double');
                    Mechanism.ForceAnalysis.(forceType).(gravType).(frictionType).(speedStr).NormalForce = zeros(numIterations, 3, 'double');
                end
            end
        end

        function JointPos = extractJointPositions(Mechanism, iteration)
            % Extract joint positions for a specific iteration
            JointPos = struct();
            jointNames = fieldnames(Mechanism.Joint);
            for i = 1:length(jointNames)
                JointPos.(jointNames{i}) = Mechanism.Joint.(jointNames{i})(iteration, :);
            end
        end
        function LinkCoMPos = extractLinkCoMPositions(Mechanism, iteration)
            % Extract link center of mass positions for a specific iteration
            LinkCoMPos = struct();
            linkNames = fieldnames(Mechanism.LinkCoM);
            for i = 1:length(linkNames)
                LinkCoMPos.(linkNames{i}) = Mechanism.LinkCoM.(linkNames{i})(iteration, :);
            end
        end
        function pos = momentVec(pos, fixPos, force)
            % Position Vector
            r = pos - fixPos;
            pos = cross(r,force);
        end
        % function saveForceData(baseFolder, Mechanism, numSpeeds)
        %     % Define categories, conditions, and friction states
        %     categories = {'Static', 'Newton'};
        %     conditions = {'Grav', 'NoGrav'};
        %     frictions = {'Friction', 'NoFriction'};
        %
        %     % Iterate through each combination of categories, conditions, and frictions
        %     for iCategory = 1:length(categories)
        %         for iCondition = 1:length(conditions)
        %             for iFriction = 1:length(frictions)
        %                 for speedIndex = 1:numSpeeds
        %                     speedStr = ['f' num2str(Mechanism.inputSpeed(speedIndex)) 'RPM'];
        %                     forceFolder = fullfile(baseFolder, speedStr, categories{iCategory} + 'Force', conditions{iCondition}, frictions{iFriction});
        %                     if ~exist(forceFolder, 'dir')
        %                         mkdir(forceFolder);
        %                     end
        %
        %                     jointFolder = fullfile(forceFolder, 'Joint');
        %                     if ~exist(jointFolder, 'dir')
        %                         mkdir(jointFolder);
        %                     end
        %                     jointNames = fieldnames(Mechanism.Joint);
        %                     for iJoint = 1:length(jointNames)
        %                         jointName = jointNames{iJoint};
        %                         dataName = [jointName, '_', speedStr, '.mat'];
        %                         save(fullfile(jointFolder, dataName), 'Mechanism');
        %                     end
        %                     % speedStr = ['f' num2str(Mechanism.inputSpeed(speedIndex)) 'RPM'];
        %                     %
        %                     % category = categories{iCategory};
        %                     % condition = conditions{iCondition};
        %                     % friction = frictions{iFriction};
        %                     %
        %                     % % Construct force field name e.g., StaticForceGravFriction
        %                     % forceFieldName = [category 'Force' condition friction];
        %                     %
        %                     % % Prepare folders for Joint and Torque
        %                     % jointFolder = fullfile(baseFolder, [category 'Force'], condition, friction, 'Joint');
        %                     %
        %                     % % Ensure folders exist
        %                     % if ~exist(jointFolder, 'dir')
        %                     %     mkdir(jointFolder);
        %                     % end
        %                     %
        %                     % % Process and save Joint data
        %                     % if isfield(Mechanism, forceFieldName) && isfield(Mechanism.(forceFieldName), 'Joint')
        %                     %     jointNames = fieldnames(Mechanism.(forceFieldName).Joint);
        %                     %     for iJoint = 1:length(jointNames)
        %                     %         jointName = jointNames{iJoint};
        %                     %         tempStruct = struct(jointName, Mechanism.(forceFieldName).Joint.(jointName));
        %                     %         save(fullfile(jointFolder, jointName), '-struct', 'tempStruct', jointName);
        %                     %     end
        %                     % end
        %                     %
        %                     % % Process and save Torque data
        %                     % if isfield(Mechanism, forceFieldName) && isfield(Mechanism.(forceFieldName), 'Torque')
        %                     %     torqueFilePath = fullfile(baseFolder, [category 'Force'], condition, friction, 'Torque.mat');
        %                     %     Torque = Mechanism.(forceFieldName).Torque;
        %                     %     save(torqueFilePath, 'Torque');
        %                     % end
        %                     %
        %                     % % Process and save Normal Force data
        %                     % if isfield(Mechanism, forceFieldName) && isfield(Mechanism.(forceFieldName), 'NormalForce')
        %                     %     normalForceFilePath = fullfile(baseFolder, [category 'Force'], condition, friction, 'NormalForce.mat');
        %                     %     NormalForce = Mechanism.(forceFieldName).NormalForce; % Extract normal force data
        %                     %     save(normalForceFilePath, 'NormalForce');
        %                     % end
        %                 end
        %             end
        %         end
        %     end
        % end
        %
        % function saveForceData(baseFolder, Mechanism)
        %     fields = fieldnames(Mechanism.ForceData);
        %     for i = 1:length(fields)
        %         fieldPath = fullfile(baseFolder, fields{i});
        %         if ~exist(fieldPath, 'dir')
        %             mkdir(fieldPath);
        %         end
        %         save(fullfile(fieldPath, 'Joint.mat'), 'Mechanism.ForceData.(fields{i}).Joint');
        %         save(fullfile(fieldPath, 'Torque.mat'), 'Mechanism.ForceData.(fields{i}).Torque');
        %         save(fullfile(fieldPath, 'NormalForce.mat'), 'Mechanism.ForceData.(fields{i}).NormalForce');
        %     end
        % end
        % function saveForceData(baseFolder, Mechanism)
        %     % Extract the top-level fields (Newton, Static)
        %     forceTypes = fieldnames(Mechanism.ForceAnalysis);
        %
        %     for iType = 1:length(forceTypes)
        %         forceType = forceTypes{iType};
        %         gravTypes = fieldnames(Mechanism.ForceAnalysis.(forceType));
        %
        %         for iGrav = 1:length(gravTypes)
        %             gravType = gravTypes{iGrav};
        %             frictionTypes = fieldnames(Mechanism.ForceAnalysis.(forceType).(gravType));
        %
        %             for iFriction = 1:length(frictionTypes)
        %                 frictionType = frictionTypes{iFriction};
        %                 speedIndices = fieldnames(Mechanism.ForceAnalysis.(forceType).(gravType).(frictionType));
        %
        %                 for iSpeed = 1:length(speedIndices)
        %                     speedIndex = speedIndices{iSpeed};
        %                     savePath = fullfile(baseFolder, forceType, gravType, frictionType, speedIndex);
        %
        %                     if ~exist(savePath, 'dir')
        %                         mkdir(savePath);
        %                     end
        %
        %                     % Save Joint, Torque, and NormalForce data
        %                     dataTypes = {'Joint', 'Torque', 'NormalForce'};
        %                     for dataType = dataTypes
        %                         dataToSave = Mechanism.ForceAnalysis.(forceType).(gravType).(frictionType).(speedIndex).(dataType{1});
        %                         save(fullfile(savePath, [dataType{1} '.mat']), 'dataToSave');
        %                     end
        %                 end
        %             end
        %         end
        %     end
        % end
        % function saveForceData(baseFolder, Mechanism)
        %     % Extract the top-level fields (Newton, Static)
        %     forceTypes = fieldnames(Mechanism.ForceAnalysis);
        %
        %     for iType = 1:length(forceTypes)
        %         forceType = forceTypes{iType};
        %         gravTypes = fieldnames(Mechanism.ForceAnalysis.(forceType));
        %
        %         for iGrav = 1:length(gravTypes)
        %             gravType = gravTypes{iGrav};
        %             frictionTypes = fieldnames(Mechanism.ForceAnalysis.(forceType).(gravType));
        %
        %             for iFriction = 1:length(frictionTypes)
        %                 frictionType = frictionTypes{iFriction};
        %                 speedIndices = fieldnames(Mechanism.ForceAnalysis.(forceType).(gravType).(frictionType));
        %
        %                 for iSpeed = 1:length(speedIndices)
        %                     speedIndex = speedIndices{iSpeed};
        %                     savePath = fullfile(baseFolder, forceType, gravType, frictionType, speedIndex);
        %
        %                     if ~exist(savePath, 'dir')
        %                         mkdir(savePath);
        %                     end
        %
        %                     % Save Joint, Torque, and NormalForce data
        %                     dataTypes = {'Joint', 'Torque', 'NormalForce'};
        %                     for dataType = dataTypes
        %                         jointNames = fieldnames(Mechanism.ForceAnalysis.(forceType).(gravType).(frictionType).(speedIndex).(dataType{1}));
        %                         for iJoint = 1:length(jointNames)
        %                             jointName = jointNames{iJoint};
        %                             dataToSave = Mechanism.ForceAnalysis.(forceType).(gravType).(frictionType).(speedIndex).(dataType{1}).(jointName);
        %                             jointFolder = fullfile(savePath, dataType{1});
        %
        %                             % Ensure the directory for each joint exists
        %                             if ~exist(jointFolder, 'dir')
        %                                 mkdir(jointFolder);
        %                             end
        %
        %                             save(fullfile(jointFolder, [jointName '.mat']), 'dataToSave');
        %                         end
        %                     end
        %                 end
        %             end
        %         end
        %     end
        % end

        function saveForceData(baseFolder, Mechanism)
            % Extract the top-level fields (Newton, Static)
            forceTypes = fieldnames(Mechanism.ForceAnalysis);

            for iType = 1:length(forceTypes)
                forceType = forceTypes{iType};
                gravTypes = fieldnames(Mechanism.ForceAnalysis.(forceType));

                for iGrav = 1:length(gravTypes)
                    gravType = gravTypes{iGrav};
                    frictionTypes = fieldnames(Mechanism.ForceAnalysis.(forceType).(gravType));

                    for iFriction = 1:length(frictionTypes)
                        frictionType = frictionTypes{iFriction};
                        speedIndices = fieldnames(Mechanism.ForceAnalysis.(forceType).(gravType).(frictionType));

                        for iSpeed = 1:length(speedIndices)
                            speedIndex = speedIndices{iSpeed};
                            savePath = fullfile(baseFolder, forceType, gravType, frictionType, speedIndex);

                            if ~exist(savePath, 'dir')
                                mkdir(savePath);
                            end

                            % Save Joint data
                            jointFolder = fullfile(savePath, 'Joint');
                            if ~exist(jointFolder, 'dir')
                                mkdir(jointFolder);
                            end
                            jointData = Mechanism.ForceAnalysis.(forceType).(gravType).(frictionType).(speedIndex).Joint;
                            jointNames = fieldnames(jointData);
                            for iJoint = 1:length(jointNames)
                                jointName = jointNames{iJoint};
                                tempStruct = struct(jointName, jointData.(jointName));
                                save(fullfile(jointFolder, [jointName '.mat']), '-struct', 'tempStruct', jointName);
                            end

                            % Save Torque data
                            Torque = Mechanism.ForceAnalysis.(forceType).(gravType).(frictionType).(speedIndex).Torque;
                            torqueFilePath = fullfile(savePath, 'Torque.mat');
                            save(torqueFilePath, 'Torque');

                            % Save Normal Force data
                            NormalForce = Mechanism.ForceAnalysis.(forceType).(gravType).(frictionType).(speedIndex).NormalForce;
                            normalForceFilePath = fullfile(savePath, 'NormalForce.mat');
                            save(normalForceFilePath, 'NormalForce');
                        end
                    end
                end
            end
        end



    end
end
