classdef VelAccSolverUtils
    methods(Static)
        function Mechanism = VelAccSolver(Mechanism, determineAngVelFunc, determineLinVelFunc, determineAngAccFunc, determineLinAccFunc)

            % Determine the number of iterations (rows in Joints)
            numIterations = size(Mechanism.Joint.A, 1); % Assuming 'A' is a joint in Mechanism.Joints

            % Initialize fields for storing kinematics data
            Mechanism.AngVel = struct();
            Mechanism.LinVel = struct();
            Mechanism.AngAcc = struct();
            Mechanism.LinAcc = struct();

            blankVector = [0 0 0];
            % Initialize blank joint vector dynamically
            jointNames = fieldnames(Mechanism.Joint); % Get all joint names from Mechanism
            initialBlankJointVector = struct();
            for i = 1:length(jointNames)
                initialBlankJointVector.(jointNames{i}) = blankVector;
            end
            jointNames = fieldnames(Mechanism.TracerPoint); % Get all joint names from Mechanism
            for i = 1:length(jointNames)
                initialBlankJointVector.(jointNames{i}) = blankVector;
            end
            

            % Initialize blank link vector dynamically
            linkNames = fieldnames(Mechanism.LinkCoM); % Get all link names from Mechanism
            initialBlankLinkVector = struct();
            for i = 1:length(linkNames)
                initialBlankLinkVector.(linkNames{i}) = blankVector;
            end


            numSpeeds = size(Mechanism.inputSpeed, 2); % Assuming inputSpeed has dimensions: iterations x speeds
            [Mechanism] = VelAccSolverUtils.initializeAngVels(Mechanism, initialBlankLinkVector, numIterations, Mechanism.input_speed_str);
            [Mechanism] = VelAccSolverUtils.initializeLinVels(Mechanism, initialBlankJointVector, initialBlankLinkVector, numIterations, Mechanism.input_speed_str);
            [Mechanism] = VelAccSolverUtils.initializeAngAccs(Mechanism, initialBlankLinkVector, numIterations, Mechanism.input_speed_str);
            [Mechanism] = VelAccSolverUtils.initializeLinAccs(Mechanism, initialBlankJointVector, initialBlankLinkVector, numIterations, Mechanism.input_speed_str);

            for speedIndex = 1:numSpeeds
                for iter = 1:numIterations
                    % Extract joint positions for this iteration
                    JointPos = VelAccSolverUtils.extractJointPositions(Mechanism, iter);
                    LinkCoMPos = VelAccSolverUtils.extractLinkCoMPositions(Mechanism, iter);

                    % Assuming input_speed is defined or extracted from Mechanism
                    input_speed = Mechanism.inputSpeed(iter, speedIndex); % Placeholder, adjust based on your Mechanism structure

                    % Define the speed field name
                    % speedStr = ['f' num2str(Mechanism.input_speed_str(speedIndex)) 'RPM'];
                    speedStrTemp = strrep(num2str(Mechanism.input_speed_str(speedIndex)), '.', '_');  % Replace '.' with '_'
                    speedStr = ['f' speedStrTemp 'RPM'];  % Construct the new name

                    % Calculate kinematics for the current iteration and store within the Mechanism
                    Mechanism = VelAccSolverUtils.determineKinematics(Mechanism, iter, speedStr, JointPos, LinkCoMPos, input_speed, determineAngVelFunc, determineLinVelFunc, determineAngAccFunc, determineLinAccFunc);
                end
            end

            % Save the updated Mechanism
            save('Mechanism.mat', 'Mechanism');

            % Define the base folder name for Velocities and Accelerations
            baseVelFolder = 'Kin/Vel';
            baseAccFolder = 'Kin/Acc';

            % Directories for velocities
            linVelJointFolder = fullfile(baseVelFolder, 'LinVel', 'Joint');
            linVelLinkCoMFolder = fullfile(baseVelFolder, 'LinVel', 'LinkCoM');
            angVelFolder = fullfile(baseVelFolder, 'AngVel');

            % Directories for accelerations
            linAccJointFolder = fullfile(baseAccFolder, 'LinAcc', 'Joint');
            linAccLinkCoMFolder = fullfile(baseAccFolder, 'LinAcc', 'LinkCoM');
            angAccFolder = fullfile(baseAccFolder, 'AngAcc');

            % Create the directories if they don't exist
            folders = {linVelJointFolder, linVelLinkCoMFolder, angVelFolder, linAccJointFolder, linAccLinkCoMFolder, angAccFolder};
            for i = 1:length(folders)
                if ~exist(folders{i}, 'dir')
                    mkdir(folders{i});
                end
            end

            % Example usage:
            VelAccSolverUtils.saveData(linVelJointFolder, Mechanism.LinVel.Joint);
            VelAccSolverUtils.saveData(linVelLinkCoMFolder, Mechanism.LinVel.LinkCoM);
            VelAccSolverUtils.saveData(angVelFolder, Mechanism.AngVel);
            VelAccSolverUtils.saveData(linAccJointFolder, Mechanism.LinAcc.Joint);
            VelAccSolverUtils.saveData(linAccLinkCoMFolder, Mechanism.LinAcc.LinkCoM);
            VelAccSolverUtils.saveData(angAccFolder, Mechanism.AngAcc);

        end

        function JointPos = extractJointPositions(Mechanism, iteration)
            % Extract joint positions for a specific iteration
            JointPos = struct();
            jointNames = fieldnames(Mechanism.Joint);
            for i = 1:length(jointNames)
                JointPos.(jointNames{i}) = Mechanism.Joint.(jointNames{i})(iteration, :);
            end
            tracerPointNames = fieldnames(Mechanism.TracerPoint);
            for i = 1:length(tracerPointNames)
                JointPos.(tracerPointNames{i}) = Mechanism.TracerPoint.(tracerPointNames{i})(iteration, :);
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

        % Desired functions to do cross products appropriately
        function vel = velSolver(w, r)
            vel = cross(w,r);
        end
        function acc = accSolver(w,a,r)
            acc = cross(w,cross(w,r)) + cross(a,r);
        end

        % Initialize AngVel, LinVel, AngAcc, LinAcc
        function Mechanism = initializeAngVels(Mechanism, initialBlankLinkVector, numIterations, speeds)
            angVelNames = fieldnames(initialBlankLinkVector);
            for i = 1:length(angVelNames)
                for j = 1:length(speeds)
                    % rpmName = ['f' num2str(speeds(j)) 'RPM'];
                    % rpmName = strrep(num2str(speeds(j)), '.', '_');  % Replace '.' with '_'
                    speedStr = strrep(num2str(speeds(j)), '.', '_');  % Replace '.' with '_'
                    rpmName = ['f' speedStr 'RPM'];  % Construct the new name
                    Mechanism.AngVel.(angVelNames{i}).(rpmName) = zeros(numIterations, 3); % Removing the third dimension for speeds
                end
            end
        end
        function Mechanism = initializeLinVels(Mechanism, initialBlankJointVector, initialBlankLinkVector, numIterations, speeds)
            % Initialize linear velocities for joints
            linJointVelNames = fieldnames(initialBlankJointVector);
            for i = 1:length(linJointVelNames)
                for j = 1:length(speeds)
                    % rpmName = ['f' num2str(speeds(j)) 'RPM'];
                    speedStr = strrep(num2str(speeds(j)), '.', '_');  % Replace '.' with '_'
                    rpmName = ['f' speedStr 'RPM'];  % Construct the new name
                    Mechanism.LinVel.Joint.(linJointVelNames{i}).(rpmName) = zeros(numIterations, 3);
                end
            end
            % Initialize linear velocities for Link CoM
            linLinkCoMVelNames = fieldnames(initialBlankLinkVector);
            for i = 1:length(linLinkCoMVelNames)
                for j = 1:length(speeds)
                    % rpmName = ['f' num2str(speeds(j)) 'RPM'];
                    speedStr = strrep(num2str(speeds(j)), '.', '_');  % Replace '.' with '_'
                    rpmName = ['f' speedStr 'RPM'];  % Construct the new name
                    Mechanism.LinVel.LinkCoM.(linLinkCoMVelNames{i}).(rpmName) = zeros(numIterations, 3);
                end
            end
        end
        function Mechanism = initializeAngAccs(Mechanism, initialBlankLinkVector, numIterations, speeds)
            angAccNames = fieldnames(initialBlankLinkVector);
            for i = 1:length(angAccNames)
                for j = 1:length(speeds)
                    % rpmName = ['f' num2str(speeds(j)) 'RPM'];
                    speedStr = strrep(num2str(speeds(j)), '.', '_');  % Replace '.' with '_'
                    rpmName = ['f' speedStr 'RPM'];  % Construct the new name
                    Mechanism.AngAcc.(angAccNames{i}).(rpmName) = zeros(numIterations, 3);
                end
            end
        end
        function Mechanism = initializeLinAccs(Mechanism, initialBlankJointVector, initialBlankLinkVector, numIterations, speeds)
            % Initialize linear accelerations for joints
            linJointAccNames = fieldnames(initialBlankJointVector);
            for i = 1:length(linJointAccNames)
                for j = 1:length(speeds)
                    % rpmName = ['f' num2str(speeds(j)) 'RPM'];
                    speedStr = strrep(num2str(speeds(j)), '.', '_');  % Replace '.' with '_'
                    rpmName = ['f' speedStr 'RPM'];  % Construct the new name
                    Mechanism.LinAcc.Joint.(linJointAccNames{i}).(rpmName) = zeros(numIterations, 3);
                end
            end
            % Initialize linear accelerations for Link CoM
            linLinkCoMAccNames = fieldnames(initialBlankLinkVector);
            for i = 1:length(linLinkCoMAccNames)
                for j = 1:length(speeds)
                    % rpmName = ['f' num2str(speeds(j)) 'RPM'];
                    speedStr = strrep(num2str(speeds(j)), '.', '_');  % Replace '.' with '_'
                    rpmName = ['f' speedStr 'RPM'];  % Construct the new name
                    Mechanism.LinAcc.LinkCoM.(linLinkCoMAccNames{i}).(rpmName) = zeros(numIterations, 3);
                end
            end
        end

        function Mechanism = determineKinematics(Mechanism, iter, speedStr, JointPos, LinkCoMPos, input_speed, determineAngVelFunc, determineLinVelFunc, determineAngAccFunc, determineLinAccFunc)
            % Determine angular velocity
            [Mechanism, AngVel] = feval(determineAngVelFunc, Mechanism, iter, speedStr, JointPos, input_speed);

            % Determine linear velocity
            [Mechanism] = feval(determineLinVelFunc, Mechanism, iter, speedStr, JointPos, LinkCoMPos, AngVel);

            % Determine angular acceleration
            [Mechanism, AngAcc] = feval(determineAngAccFunc, Mechanism, iter, speedStr, JointPos, AngVel);

            % Determine linear acceleration
            [Mechanism] = feval(determineLinAccFunc, Mechanism, iter, speedStr, JointPos, LinkCoMPos, AngVel, AngAcc);
        end

        % Save function for clarity and reusability
        function saveData(baseFolder, dataStruct)
            % Ensure the base folder exists
            if ~exist(baseFolder, 'dir')
                mkdir(baseFolder);
            end

            names = fieldnames(dataStruct); % Get all component names (e.g., 'JointA', 'JointB')
            for i = 1:length(names)
                component = names{i};  % Example: 'JointA'
                speedNames = fieldnames(dataStruct.(component)); % Get all speed fields ('f10RPM', 'f20RPM', 'f30RPM')

                for j = 1:length(speedNames)
                    speedName = speedNames{j};  % Example: 'f10RPM'
                    speedFolder = fullfile(baseFolder, speedName);  % Directory name includes speed

                    % Ensure the speed directory exists
                    if ~exist(speedFolder, 'dir')
                        mkdir(speedFolder);
                    end

                    data = dataStruct.(component).(speedName);  % Extract data for the current speed
                    fileName = [component '.mat'];  % File name based on the component, example: 'JointA.mat'

                    % Save the data to a .mat file in the speed directory
                    save(fullfile(speedFolder, fileName), 'data');
                end
            end
        end

    end
end