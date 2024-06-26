classdef PosSolverUtils
    methods(Static)
        function Mechanism = PosSolver(Mechanism, input_speed, calculateDistancesFunc, calculateNewPositionsFunc)
            max_iterations = 900;

            % Initialize positions for maximum iterations
            [Mechanism] = PosSolverUtils.initializePositions(Mechanism, max_iterations);

            % Calculate distances between points using the passed function
            if nargin >= 3 && ~isempty(calculateDistancesFunc)
                Mechanism = feval(calculateDistancesFunc, Mechanism);
            end

            % Initialize variables for iteration
            [iteration, theta, thetaIncrement] = PosSolverUtils.initializeVariables(Mechanism);

            % Initialize angular speed
            Mechanism = PosSolverUtils.initializeInputSpeed(Mechanism, input_speed, max_iterations);

            % Main loop for calculating joint positions using the passed function for new positions
            if nargin == 4 && ~isempty(calculateNewPositionsFunc)
                [Mechanism] = PosSolverUtils.calculateJointPositions(Mechanism, theta, thetaIncrement, iteration, max_iterations, calculateNewPositionsFunc);
            end

            baseDir = 'Kin/Pos';
            % Save joint positions
            PosSolverUtils.saveJointPositions(Mechanism)
        end

        % Function to initialize variables for the simulation
        function [iteration, theta, thetaIncrement] = initializeVariables(Mechanism)
            iteration = 2;
            thetaIncrement = 1; % Angle increment (in degrees)
            theta = atan2(Mechanism.Joint.B(1,2) - Mechanism.Joint.A(1,2), Mechanism.Joint.B(1,1) - Mechanism.Joint.A(1,1)); % Initial angle of link ABE with adjustment if necessary
        end

        % Function to initialize positions for all joints for max iterations
        function Mechanism = initializePositions(Mechanism, max_iterations)
            jointNames = fieldnames(Mechanism.Joint);
            for i = 1:length(jointNames)
                initialJointPosition = Mechanism.Joint.(jointNames{i});
                Mechanism.Joint.(jointNames{i}) = zeros(max_iterations, 3); % Initialize with zeros
                Mechanism.Joint.(jointNames{i})(1, :) = initialJointPosition; % Set initial position
            end
            tracerPointNames = fieldnames(Mechanism.TracerPoint);
            for i = 1:length(tracerPointNames)
                initialJointPosition = Mechanism.TracerPoint.(tracerPointNames{i});
                Mechanism.TracerPoint.(tracerPointNames{i}) = zeros(max_iterations, 3); % Initialize with zeros
                Mechanism.TracerPoint.(tracerPointNames{i})(1, :) = initialJointPosition; % Set initial position
            end
            linkNames = fieldnames(Mechanism.LinkCoM);
            for i = 1:length(linkNames)
                initialLinkPosition = Mechanism.LinkCoM.(linkNames{i});
                Mechanism.LinkCoM.(linkNames{i}) = zeros(max_iterations, 3); % Initialize with zeros
                Mechanism.LinkCoM.(linkNames{i})(1, :) = initialLinkPosition; % Set initial position
            end
            angleName = fieldnames(Mechanism.Angle);
            for i = 1:length(angleName)
                initialAnglePosition = Mechanism.Angle.(angleName{i});
                Mechanism.Angle.(linkNames{i}) = zeros(max_iterations, 3); % Initialize with zeros
                Mechanism.Angle.(linkNames{i})(1, :) = initialAnglePosition; % Set initial position
            end
        end

        % Main function to calculate joint positions through iterations
        function [Mechanism] = calculateJointPositions(Mechanism, theta, thetaIncrement, iteration, max_iterations, calculateNewPositionsFunc)
            forwardDir = true; % Flag to indicate the direction of rotation. Mechanism should be going forward on its last iteration

            while ~(PosSolverUtils.determineEqual(Mechanism.Joint.B(1, :), Mechanism.Joint.B(iteration - 1, :)) && ...
                    ~isequal(iteration, 2) && forwardDir) && iteration < max_iterations
                [Mechanism, theta, thetaIncrement, forwardDir, iteration] = PosSolverUtils.updateJointPositions(Mechanism, theta, thetaIncrement, iteration, forwardDir, calculateNewPositionsFunc);
            end

            % Trim positions and speeds to the last filled iteration
            jointNames = fieldnames(Mechanism.Joint);
            for i = 1:length(jointNames)
                Mechanism.Joint.(jointNames{i}) = Mechanism.Joint.(jointNames{i})(1:iteration-1, :);
            end
            tracerPointNames = fieldnames(Mechanism.TracerPoint);
            for i = 1:length(tracerPointNames)
                Mechanism.TracerPoint.(tracerPointNames{i}) = Mechanism.TracerPoint.(tracerPointNames{i})(1:iteration-1, :);
            end
            linkNames = fieldnames(Mechanism.LinkCoM);
            for i = 1:length(linkNames)
                Mechanism.LinkCoM.(linkNames{i}) = Mechanism.LinkCoM.(linkNames{i})(1:iteration-1,:);
            end
            angleNames = fieldnames(Mechanism.Angle);
            for i = 1:length(angleNames)
                Mechanism.Angle.(angleNames{i}) = Mechanism.Angle.(angleNames{i})(1:iteration-1,:);
            end
            Mechanism.inputSpeed= Mechanism.inputSpeed(1:iteration-1,:);
        end

        % Function to update positions based on current state
        function [Mechanism, theta, thetaIncrement, forwardDir, iteration] = updateJointPositions(Mechanism, theta, thetaIncrement, iteration, forwardDir, calculateNewPositionsFunc)
            % Calculate current joint angles
            theta = theta + deg2rad(thetaIncrement);

            % Calculate new positions for joints
            [Mechanism, valid, theta, iteration] = feval(calculateNewPositionsFunc, Mechanism, theta, iteration, forwardDir);

            % [Mechanism, valid, theta, iteration] = calculateNewPositions(Mechanism, theta, iteration, forwardDir);
            if ~valid
                % Revert theta if new positions are invalid and flip direction
                thetaIncrement = thetaIncrement * -1;
                forwardDir = ~forwardDir;
            end
        end

        % Function to calculate new positions for the joints
        function [Mechanism, valid, theta, iteration] = calculateNewPositions(Mechanism, theta, iteration, forwardDir)
            % Initialize validity flag
            valid = true;

            A = Mechanism.Joint.A(1, :);
            D = Mechanism.Joint.D(1, :);

            % Direct calculation for B
            B = [A(1) + Mechanism.LinkLength.AB * cos(theta), A(2) + Mechanism.LinkLength.AB * sin(theta), 0];

            % Circle-circle intersections for C, E, F, G
            C = circleCircleIntersection(B(1), B(2), Mechanism.LinkLength.BC, D(1), D(2), Mechanism.LinkLength.CD, Mechanism.Joint.C(iteration - 1, 1), Mechanism.Joint.C(iteration - 1, 2));
            if isempty(C), valid = false; return; end
            E = circleCircleIntersection(A(1), A(2), Mechanism.LinkLength.AE, B(1), B(2), Mechanism.LinkLength.BE, Mechanism.TracerPoint.E(iteration - 1, 1), Mechanism.TracerPoint.E(iteration - 1, 2));
            if isempty(E), valid = false; return; end
            F = circleCircleIntersection(B(1), B(2), Mechanism.LinkLength.BF, C(1), C(2), Mechanism.LinkLength.CF, Mechanism.TracerPoint.F(iteration - 1, 1), Mechanism.TracerPoint.F(iteration - 1, 2));
            if isempty(F), valid = false; return; end
            G = circleCircleIntersection(B(1), B(2), Mechanism.LinkLength.BG, C(1), C(2), Mechanism.LinkLength.CG, Mechanism.TracerPoint.G(iteration - 1, 1), Mechanism.TracerPoint.G(iteration - 1, 2));
            if isempty(G), valid = false; return; end
            H = circleCircleIntersection(C(1), C(2), Mechanism.LinkLength.CH, D(1), D(2), Mechanism.LinkLength.DH, Mechanism.TracerPoint.H(iteration - 1, 1), Mechanism.TracerPoint.H(iteration - 1, 2));
            if isempty(H), valid = false; return; end

            % Update positions
            Mechanism.Joint.A(iteration, :) = A;
            Mechanism.Joint.B(iteration, :) = B;
            Mechanism.Joint.C(iteration, :) = C;
            Mechanism.Joint.D(iteration, :) = D;
            Mechanism.TracerPoint.E(iteration, :) = E;
            Mechanism.TracerPoint.F(iteration, :) = F;
            Mechanism.TracerPoint.G(iteration, :) = G;
            Mechanism.TracerPoint.H(iteration, :) = H;

            utilsFolderPath = fullfile(pwd);
            addpath(utilsFolderPath);

            Mechanism.LinkCoM.ABE(iteration, :) = circleCircleIntersection(A(1), A(2), Mechanism.LinkLength.ABE_CoM_A, B(1), B(2), Mechanism.LinkLength.ABE_CoM_B, Mechanism.LinkCoM.ABE(iteration - 1, 1), Mechanism.LinkCoM.ABE(iteration - 1, 2));
            Mechanism.LinkCoM.BCFG(iteration, :) = circleCircleIntersection(B(1), B(2), Mechanism.LinkLength.BCFG_CoM_B, C(1), C(2), Mechanism.LinkLength.BCFG_CoM_C, Mechanism.LinkCoM.BCFG(iteration - 1, 1), Mechanism.LinkCoM.BCFG(iteration - 1, 2));
            Mechanism.LinkCoM.CDH(iteration, :) = circleCircleIntersection(C(1), C(2), Mechanism.LinkLength.CDH_CoM_C, D(1), D(2), Mechanism.LinkLength.CDH_CoM_D, Mechanism.LinkCoM.CDH(iteration - 1, 1), Mechanism.LinkCoM.CDH(iteration - 1, 2));

            if (forwardDir)
                Mechanism.inputSpeed(iteration) = Mechanism.inputSpeed(1);
            else
                Mechanism.inputSpeed(iteration) = Mechanism.inputSpeed(1) * -1;
            end
            iteration = iteration + 1;
        end

        % Utility function for circle-circle intersection calculation
        function result = circleCircleIntersection(x1, y1, r1, x2, y2, r2, pointX, pointY)
            % Find intersection points
            [xIntersect, yIntersect] = circcirc(x1, y1, r1, x2, y2, r2);

            % Check if the intersection points are determined
            if isempty(xIntersect) || isempty(yIntersect) || isnan(xIntersect(1)) || isnan(yIntersect(1))
                [xIntersect, yIntersect] = PosSolverUtils.circleCircleMethod(x1, y1, r1, x2, y2, r2);
            end
            if isempty(xIntersect) || isempty(yIntersect)
                result = [];
                return;
            end

            if isnan(xIntersect(1)) || isnan(yIntersect(1))
                result = [];
                return;
            end

            % Calculate distances from intersection points to the given point
            dist1 = sqrt((xIntersect(1) - pointX)^2 + (yIntersect(1) - pointY)^2);
            dist2 = sqrt((xIntersect(2) - pointX)^2 + (yIntersect(2) - pointY)^2);

            % Determine the closest intersection point
            if dist1 < dist2
                result = [xIntersect(1) yIntersect(1) 0];
            else
                result = [xIntersect(2) yIntersect(2) 0];
            end
        end
        % Utility function for circle-line intersection calculation
        function result = circleLineIntersection(x0, y0, r, xPrev, yPrev, theta)
            % Calculates the intersection points between a circle and a line defined by an angle and previous point
            % Inputs:
            % x0, y0: Coordinates of the circle's center
            % r: Radius of the circle
            % xPrev, yPrev: Coordinates of the previous joint position
            % theta: Angle of the line in degrees

            % Convert angle to radians for MATLAB trig functions
            thetaRad = deg2rad(theta);

            % Calculate slope (m) of the line
            m = tan(thetaRad);

            % Determine the line's y-intercept (b) using the point-slope form
            b = yPrev - m * xPrev;

            % Calculate intersection points using the circle equation
            A = 1 + m^2;
            B = 2*m*b - 2*x0 - 2*y0*m;
            C = x0^2 + y0^2 + b^2 - 2*y0*b - r^2;
            D = B^2 - 4*A*C; % Discriminant

            % Initialize output
            newX = NaN;
            newY = NaN;

            if D >= 0
                % Calculate potential x-coordinates for intersection points
                x1 = (-B + sqrt(D)) / (2*A);
                x2 = (-B - sqrt(D)) / (2*A);
                % Corresponding y-coordinates
                y1 = m*x1 + b;
                y2 = m*x2 + b;

                % Choose the intersection point that is closer to the previous position
                dist1 = sqrt((x1 - xPrev)^2 + (y1 - yPrev)^2);
                dist2 = sqrt((x2 - xPrev)^2 + (y2 - yPrev)^2);

                if dist1 < dist2
                    newX = x1;
                    newY = y1;
                else
                    newX = x2;
                    newY = y2;
                end
            else
                disp('Error: No real intersection points.');
            end
            result = [newX, newY, 0];
        end

        % Utility function to check if two arrays are approximately equal
        function result = determineEqual(arr1, arr2)
            tolerance = 0.001;
            result = all(abs(arr1 - arr2) < tolerance);
        end

        % function saveJointPositions(Mechanism, baseDir)
        %
        %     % Create Directory for Saving Results
        %     folderName = 'Kin';
        %     if ~exist(folderName, 'dir')
        %         mkdir(folderName);  % Create the directory if it doesn't exist
        %     end
        %
        %     % Save Joint Positions in the Created Directory
        %     save('Mechanism.mat', 'Mechanism');
        %
        %
        %     jointNames = fieldnames(Mechanism.Joint);
        %     jointFolder = fullfile(baseDir, 'Joint');
        %     if ~exist(jointFolder, 'dir')
        %         mkdir(jointFolder);
        %     end
        %
        %     for i = 1:length(jointNames)
        %         jointName = jointNames{i};
        %         % Create a temporary struct with the field name as the joint name
        %         tempStruct = struct(jointName, Mechanism.Joint.(jointName));
        %         % Save this struct using the -struct option
        %         save(fullfile(jointFolder, jointName), '-struct', 'tempStruct', jointName);
        %     end
        %
        %     tracerPointNames = fieldnames(Mechanism.TracerPoint);
        %
        %     for i = 1:length(tracerPointNames)
        %         tracerPointName = tracerPointNames{i};
        %         % Create a temporary struct with the field name as the joint name
        %         tempStruct = struct(tracerPointName, Mechanism.TracerPoint.(tracerPointName));
        %         % Save this struct using the -struct option
        %         save(fullfile(jointFolder, tracerPointName), '-struct', 'tempStruct', tracerPointName);
        %     end
        %
        %     % Save link CoM positions
        %     linkNames = fieldnames(Mechanism.LinkCoM);
        %     linkCoMFolder = fullfile(baseDir, 'LinkCoM');
        %     if ~exist(linkCoMFolder, 'dir')
        %         mkdir(linkCoMFolder);
        %     end
        %
        %     for i = 1:length(linkNames)
        %         linkName = linkNames{i};
        %         % Create a temporary struct with the field name as the link name
        %         tempStruct = struct(linkName, Mechanism.LinkCoM.(linkName));
        %         % Save this struct using the -struct option
        %         save(fullfile(linkCoMFolder, linkName), '-struct', 'tempStruct', linkName);
        %     end
        %
        %     % Save Angle for links
        % end
        % function saveJointPositions(Mechanism, baseDir)
        %     % Create Directory for Saving Results
        %     folderName = 'Kin';
        %     if ~exist(folderName, 'dir')
        %         mkdir(folderName);  % Create the directory if it doesn't exist
        %     end
        %
        %     % Save Joint Positions in the Created Directory
        %     save(fullfile(folderName, 'Mechanism.mat'), 'Mechanism');
        %
        %     % Directory for Joints and Links under Pos
        %     posDir = fullfile(folderName, 'Pos');
        %     if ~exist(posDir, 'dir')
        %         mkdir(posDir);
        %     end
        %
        %     jointFolder = fullfile(posDir, 'Joint');
        %     linkCoMFolder = fullfile(posDir, 'LinkCoM');
        %     angleFolder = fullfile(posDir, 'Angle');
        %
        %     % Create subdirectories if they don't exist
        %     if ~exist(jointFolder, 'dir')
        %         mkdir(jointFolder);
        %     end
        %     if ~exist(linkCoMFolder, 'dir')
        %         mkdir(linkCoMFolder);
        %     end
        %     if ~exist(angleFolder, 'dir')
        %         mkdir(angleFolder);
        %     end
        %
        %     % Save Joint data
        %     jointNames = fieldnames(Mechanism.Joint);
        %     for i = 1:length(jointNames)
        %         jointName = jointNames{i};
        %         tempStruct = struct(jointName, Mechanism.Joint.(jointName));
        %         save(fullfile(jointFolder, jointName), '-struct', 'tempStruct', jointName);
        %     end
        %
        %     % Save Tracer Point data
        %     tracerPointNames = fieldnames(Mechanism.TracerPoint);
        %     for i = 1:length(tracerPointNames)
        %         tracerPointName = tracerPointNames{i};
        %         tempStruct = struct(tracerPointName, Mechanism.TracerPoint.(tracerPointName));
        %         save(fullfile(jointFolder, tracerPointName), '-struct', 'tempStruct', tracerPointName);
        %     end
        %
        %     % Save Link CoM data
        %     linkNames = fieldnames(Mechanism.LinkCoM);
        %     for i = 1:length(linkNames)
        %         linkName = linkNames{i};
        %         tempStruct = struct(linkName, Mechanism.LinkCoM.(linkName));
        %         save(fullfile(linkCoMFolder, linkName), '-struct', 'tempStruct', linkName);
        %     end
        %
        %     % Save Angle data
        %     angleNames = fieldnames(Mechanism.Angle);
        %     for i = 1:length(angleNames)
        %         angleName = angleNames{i};
        %         tempStruct = struct(angleName, Mechanism.Angle.(angleName));
        %         save(fullfile(angleFolder, angleName), '-struct', 'tempStruct', angleName);
        %     end
        % end
        % function saveJointPositions(Mechanism)
        %     % Create Directory for Saving Results
        %     folderName = 'Kin';
        %     if ~exist(folderName, 'dir')
        %         mkdir(folderName);  % Create the directory if it doesn't exist
        %     end
        %
        %     % Directory for Joints and Links under Pos
        %     posDir = fullfile(folderName, 'Pos');
        %     if ~exist(posDir, 'dir')
        %         mkdir(posDir);
        %     end
        %
        %     jointFolder = fullfile(posDir, 'Joint');
        %     linkCoMFolder = fullfile(posDir, 'LinkCoM');
        %
        %     % Angle data is saved directly under Kin, not under Pos
        %     angleFolder = fullfile(folderName, 'Angle');  % Changed from posDir to folderName
        %
        %     % Create subdirectories if they don't exist
        %     if ~exist(jointFolder, 'dir')
        %         mkdir(jointFolder);
        %     end
        %     if ~exist(linkCoMFolder, 'dir')
        %         mkdir(linkCoMFolder);
        %     end
        %     if ~exist(angleFolder, 'dir')
        %         mkdir(angleFolder);
        %     end
        %
        %     % Save Joint data
        %     jointNames = fieldnames(Mechanism.Joint);
        %     for i = 1:length(jointNames)
        %         jointName = jointNames{i};
        %         tempStruct = struct(jointName, Mechanism.Joint.(jointName));
        %         save(fullfile(jointFolder, jointName), '-struct', 'tempStruct', jointName);
        %     end
        %
        %
        %     % Save Tracer Point data
        %     tracerPointNames = fieldnames(Mechanism.TracerPoint);
        %     for i = 1:length(tracerPointNames)
        %         tracerPointName = tracerPointNames{i};
        %         tempStruct = struct(tracerPointName, Mechanism.TracerPoint.(tracerPointName));
        %         save(fullfile(jointFolder, tracerPointName), '-struct', 'tempStruct', tracerPointName);
        %     end
        %
        %      % Save Link CoM data
        %     linkNames = fieldnames(Mechanism.LinkCoM);
        %     for i = 1:length(linkNames)
        %         linkName = linkNames{i};
        %         tempStruct = struct(linkName, Mechanism.LinkCoM.(linkName));
        %         save(fullfile(linkCoMFolder, linkName), '-struct', 'tempStruct', linkName);
        %     end
        %
        %     % Save Angle data
        %     angleNames = fieldnames(Mechanism.Angle);
        %     for i = 1:length(angleNames)
        %         angleName = angleNames{i};
        %         tempStruct = struct(angleName, Mechanism.Angle.(angleName));
        %         save(fullfile(angleFolder, angleName), '-struct', 'tempStruct', angleName);
        %     end
        % end
        function saveJointPositions(Mechanism)
            % Create Directory for Saving Results
            folderName = 'Kin';
            if ~exist(folderName, 'dir')
                mkdir(folderName);  % Create the directory if it doesn't exist
            end

            % Directory for Joints, Links, and Angles under Pos
            posDir = fullfile(folderName, 'Pos');
            if ~exist(posDir, 'dir')
                mkdir(posDir);
            end

            % Additional Point folder under Pos for Joint and LinkCoM
            pointFolder = fullfile(posDir, 'Point');
            if ~exist(pointFolder, 'dir')
                mkdir(pointFolder);
            end

            jointFolder = fullfile(pointFolder, 'Joint');
            linkCoMFolder = fullfile(pointFolder, 'LinkCoM');

            % Angle data is saved directly under Pos
            angleFolder = fullfile(posDir, 'Angle');  % Changed location under Pos

            % Create subdirectories if they don't exist
            if ~exist(jointFolder, 'dir')
                mkdir(jointFolder);
            end
            if ~exist(linkCoMFolder, 'dir')
                mkdir(linkCoMFolder);
            end
            if ~exist(angleFolder, 'dir')
                mkdir(angleFolder);
            end

            % Save Joint data
            jointNames = fieldnames(Mechanism.Joint);
            for i = 1:length(jointNames)
                jointName = jointNames{i};
                tempStruct = struct(jointName, Mechanism.Joint.(jointName));
                save(fullfile(jointFolder, jointName), '-struct', 'tempStruct', jointName);
            end

            % Save Tracer Point data
            tracerPointNames = fieldnames(Mechanism.TracerPoint);
            for i = 1:length(tracerPointNames)
                tracerPointName = tracerPointNames{i};
                tempStruct = struct(tracerPointName, Mechanism.TracerPoint.(tracerPointName));
                save(fullfile(jointFolder, tracerPointName), '-struct', 'tempStruct', tracerPointName);
            end

            % Save Link CoM data
            linkNames = fieldnames(Mechanism.LinkCoM);
            for i = 1:length(linkNames)
                linkName = linkNames{i};
                tempStruct = struct(linkName, Mechanism.LinkCoM.(linkName));
                save(fullfile(linkCoMFolder, linkName), '-struct', 'tempStruct', linkName);
            end

            % Save Angle data
            angleNames = fieldnames(Mechanism.Angle);
            for i = 1:length(angleNames)
                angleName = angleNames{i};
                tempStruct = struct(angleName, Mechanism.Angle.(angleName));
                save(fullfile(angleFolder, angleName), '-struct', 'tempStruct', angleName);
            end
        end


        function Mechanism = initializeInputSpeed(Mechanism, input_speed, max_iterations)
            % Assuming input_speed is a vector of different speeds
            numSpeeds = length(input_speed); % Number of different speeds
            % Initialize the inputSpeed matrix
            Mechanism.inputSpeed = zeros(max_iterations, numSpeeds);
            % Set the initial speed for each speed scenario
            for i = 1:numSpeeds
                Mechanism.inputSpeed(1, i) = input_speed(i);
            end
        end

        function [xIntersect, yIntersect] = circleCircleMethod(x1, y1, r1, x2, y2, r2)
            syms x y
            eq1 = (x - x1)^2 + (y - y1)^2 == r1^2;
            eq2 = (x - x2)^2 + (y - y2)^2 == r2^2;

            sol = solve([eq1, eq2], [x, y]);

            % Threshold for considering the imaginary part significant
            imaginaryThreshold = 1e-5; % Adjust this value based on your application's tolerance

            % Evaluating solutions (assuming sol.x and sol.y are symbolic solutions)
            xSolEval = [eval(sol.x(1)), eval(sol.x(2))];
            ySolEval = [eval(sol.y(1)), eval(sol.y(2))];

            % Initialize empty arrays to hold the processed solutions
            xIntersect = [];
            yIntersect = [];

            % Check the imaginary parts of the x solutions
            if all(abs(imag(xSolEval)) <= imaginaryThreshold)
                xIntersect = real(xSolEval);
            end

            % Check the imaginary parts of the y solutions
            if all(abs(imag(ySolEval)) <= imaginaryThreshold)
                yIntersect = real(ySolEval);
            end

            % xIntersect and yIntersect will be empty if any imaginary part was significant

        end
    end
end