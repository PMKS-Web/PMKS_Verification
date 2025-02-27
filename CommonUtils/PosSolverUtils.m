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
                initialLinkLinearPosition = Mechanism.LinkCoM.(linkNames{i});
                Mechanism.LinkCoM.(linkNames{i}) = zeros(max_iterations, 3); % Initialize with zeros
                Mechanism.LinkCoM.(linkNames{i})(1, :) = initialLinkLinearPosition; % Set initial position
            end
            % angleName = fieldnames(Mechanism.Angle);
            % for i = 1:length(angleName)
            %     initialAnglePosition = Mechanism.Angle.(angleName{i});
            %     Mechanism.Angle.(linkNames{i}) = zeros(max_iterations, 3); % Initialize with zeros
            %     Mechanism.Angle.(linkNames{i})(1, :) = initialAnglePosition; % Set initial position
            % end
            for i = 1:length(linkNames)
                initialLinkAnglePosition = Mechanism.Angle.Link.(linkNames{i});
                Mechanism.Angle.Link.(linkNames{i}) = zeros(max_iterations, 3); % Initialize with zeros
                Mechanism.Angle.Link.(linkNames{i})(1, :) = initialLinkAnglePosition; % Initialize with zeros
            end
            for i = 1:length(tracerPointNames)
                initialTracerPointAnglePosition = Mechanism.Angle.Joint.(tracerPointNames{i});
                Mechanism.Angle.Joint.(tracerPointNames{i}) = zeros(max_iterations, 3); % Initialize with zeros
                Mechanism.Angle.Joint.(tracerPointNames{i})(1, :) = initialTracerPointAnglePosition; % Initialize with zeros
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

            for i = 1:length(linkNames)
                Mechanism.Angle.Link.(linkNames{i}) = Mechanism.Angle.Link.(linkNames{i})(1:iteration-1,:);
            end
            for i = 1:length(tracerPointNames)
                Mechanism.Angle.Joint.(tracerPointNames{i}) = Mechanism.Angle.Joint.(tracerPointNames{i})(1:iteration-1, :);
            end
            % angleNames = fieldnames(Mechanism.Angle);
            % for i = 1:length(angleNames)
            %     Mechanism.Angle.(angleNames{i}) = Mechanism.Angle.(angleNames{i})(1:iteration-1,:);
            % end
            Mechanism.inputSpeed = Mechanism.inputSpeed(1:iteration-1,:);
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

        % function [x_calc, y_calc] = determineTracerJoint(lastJoint, joint_with_neighboring_ground, unknown_joint)
        %     % Extract coordinates from the input structs or arrays
        %     x1 = lastJoint(1); y1 = lastJoint(2); % Coordinates of the last joint
        %     x2 = joint_with_neighboring_ground(1); y2 = joint_with_neighboring_ground(2); % Coordinates of neighboring joint
        %     prevJoint_x = unknown_joint(1); prevJoint_y = unknown_joint(2); % Coordinates of previous position of the unknown joint
        % 
        %     % Step 1: Compute distances r1, r2, and r3
        %     r1 = euclideanDistance(x1, y1, prevJoint_x, prevJoint_y); % Distance between lastJoint and unknown_joint
        %     r2 = euclideanDistance(x2, y2, prevJoint_x, prevJoint_y); % Distance between neighboring joint and unknown_joint
        %     r3 = euclideanDistance(x1, y1, x2, y2); % Distance between lastJoint and neighboring joint
        % 
        %     % Step 2: Compute the internal angle using the cosine law
        %     internal_angle = acos((r1^2 + r3^2 - r2^2) / (2 * r1 * r3));
        % 
        %     % Step 3: Compute the angle between the two known joints using atan2
        %     angle = atan2(y2 - y1, x2 - x1);
        % 
        %     % Step 4: Compute the two potential solutions for the unknown joint
        %     [x_calc1, y_calc1, x_calc2, y_calc2] = determineUnknownJointUsingTriangulation( ...
        %         x1, y1, x2, y2, r1, prevJoint_x, prevJoint_y, angle, internal_angle);
        % 
        %     % Step 5: Choose the solution closer to the previous joint position
        %     dist1 = euclideanDistance(x_calc1, y_calc1, prevJoint_x, prevJoint_y);
        %     dist2 = euclideanDistance(x_calc2, y_calc2, prevJoint_x, prevJoint_y);
        % 
        %     if dist1 < dist2
        %         x_calc = x_calc1;
        %         y_calc = y_calc1;
        %     else
        %         x_calc = x_calc2;
        %         y_calc = y_calc2;
        %     end
        % end
        % 
        % function [x_calc1, y_calc1, x_calc2, y_calc2] = determineUnknownJointUsingTriangulation( ...
        %     x1, y1, x2, y2, r1, prevJoint_x, prevJoint_y, angle, internal_angle)
        % 
        %     % Compute the two possible solutions for the unknown joint position
        % 
        %     if x1 > x2
        %         if y1 > y2
        %             % A to the right and above B
        %             x_calc1 = x1 + r1 * cos(pi + (internal_angle + (pi + angle)));
        %             y_calc1 = y1 + r1 * sin(pi + (internal_angle + (pi + angle)));
        %             x_calc2 = x1 + r1 * cos(pi - (internal_angle - (pi + angle)));
        %             y_calc2 = y1 + r1 * sin(pi - (internal_angle - (pi + angle)));
        %         else
        %             % A to the right and below B
        %             x_calc1 = x1 + r1 * cos(pi + (internal_angle - (pi - angle)));
        %             y_calc1 = y1 + r1 * sin(pi + (internal_angle - (pi - angle)));
        %             x_calc2 = x1 + r1 * cos(pi - (internal_angle + (pi - angle)));
        %             y_calc2 = y1 + r1 * sin(pi - (internal_angle + (pi - angle)));
        %         end
        %     else
        %         if y1 > y2
        %             % A to the left and above B
        %             x_calc1 = x1 + r1 * cos(2 * pi - (abs(angle) + internal_angle));
        %             y_calc1 = y1 + r1 * sin(2 * pi - (abs(angle) + internal_angle));
        %             x_calc2 = x1 + r1 * cos(internal_angle - abs(angle));
        %             y_calc2 = y1 + r1 * sin(internal_angle - abs(angle));
        %         else
        %             % A to the left and below B
        %             x_calc1 = x1 + r1 * cos(2 * pi - (angle - internal_angle));
        %             y_calc1 = y1 + r1 * sin(angle - internal_angle);
        %             x_calc2 = x1 + r1 * cos(internal_angle + angle);
        %             y_calc2 = y1 + r1 * sin(internal_angle + angle);
        %         end
        %     end
        % end
        % 
        % function dist = euclideanDistance(x1, y1, x2, y2)
        %     % Compute the Euclidean distance between two points
        %     dist = sqrt((x2 - x1)^2 + (y2 - y1)^2);
        % end

        % function p3 = determineTracerJoint(x0, y0, r0, x1, y1, r1, )
        %     % Calculate the intersection points of two circles
        %     % Input: 
        %     %   (x0, y0) - center of the first circle
        %     %   r0       - radius of the first circle
        %     %   (x1, y1) - center of the second circle
        %     %   r1       - radius of the second circle
        %     % Output:
        %     %   p1, p2   - coordinates of the intersection points (if they exist)
        %     %   valid    - boolean indicating if a valid intersection exists
        % 
        %     % Step 1: Calculate the distance between the centers of the two circles
        %     dx = x1 - x0;
        %     dy = y1 - y0;
        %     d = sqrt(dx^2 + dy^2);
        % 
        %     % Step 2: Check for conditions where no intersection occurs
        %     if d > r0 + r1
        %         % Circles are too far apart, no intersection
        %         valid = false;
        %         p1 = [];
        %         p2 = [];
        %         return;
        %     elseif d < abs(r0 - r1)
        %         % One circle is completely inside the other, no intersection
        %         valid = false;
        %         p1 = [];
        %         p2 = [];
        %         return;
        %     elseif d <= 0.001
        %         % The circles are practically coincident
        %         valid = false;
        %         p1 = [];
        %         p2 = [];
        %         return;
        %     end
        % 
        %     % Step 3: Normalize the vector between the two centers
        %     dx = dx / d;
        %     dy = dy / d;
        % 
        %     % Step 4: Calculate 'a', the distance from the center of the first circle
        %     % to the point where the line through the intersection points crosses the line between the circle centers
        %     a = (r0^2 - r1^2 + d^2) / (2 * d);
        % 
        %     % Step 5: Calculate the point (px, py) where the line through the two intersection points
        %     % intersects the line between the centers of the circles
        %     px = x0 + a * dx;
        %     py = y0 + a * dy;
        % 
        %     % Step 6: Calculate the distance from (px, py) to the intersection points
        %     h = sqrt(r0^2 - a^2);
        % 
        %     % Step 7: Calculate the actual intersection points
        %     p1x = px + h * dy;
        %     p1y = py - h * dx;
        %     p2x = px - h * dy;
        %     p2y = py + h * dx;
        % 
        %     % Store the intersection points
        %     p1 = [p1x, p1y];
        %     p2 = [p2x, p2y];
        % 
        % end

        function selectedIndex = circleCircleIntersectionSelect(x0, y0, r0, x1, y1, r1, prevJoint_x, prevJoint_y)
            % This function computes the intersection points and returns the index (1 or 2)
            % corresponding to the point that is closest to the previous joint position.
            
            % Calculate the intersection points
            [p1x, p1y, p2x, p2y, valid] = PosSolverUtils.calculateIntersectionPoints(x0, y0, r0, x1, y1, r1);
            
            % If the intersection is not valid, return an empty result
            if ~valid
                selectedIndex = NaN;
                return;
            end
            
            % Compute distances from previous joint to both intersection points
            dist1 = PosSolverUtils.euclideanDistance(p1x, p1y, prevJoint_x, prevJoint_y);
            dist2 = PosSolverUtils.euclideanDistance(p2x, p2y, prevJoint_x, prevJoint_y);
            
            % Return 1 if the first point is closer, otherwise return 2
            if dist1 < dist2
                selectedIndex = 1;
            else
                selectedIndex = 2;
            end
        end
        
        function [p_final, valid] = circleCircleIntersectionWithPrevious(x0, y0, r0, x1, y1, r1, index)
            % This function computes the intersection points and selects the point
            % based on the provided index (1 or 2).
            
            % Calculate the intersection points
            [p1x, p1y, p2x, p2y, valid] = PosSolverUtils.calculateIntersectionPoints(x0, y0, r0, x1, y1, r1);
            
            % If the intersection is not valid, return an empty result
            if ~valid
                p_final = [];
                return;
            end
            
            % Select the intersection point based on the index (1 or 2)
            if index == 1
                p_final = [p1x, p1y, 0];
            elseif index == 2
                p_final = [p2x, p2y, 0];
            else
                % Invalid index
                p_final = [];
                valid = false;
                return;
            end
        end
        
        function [p1x, p1y, p2x, p2y, valid] = calculateIntersectionPoints(x0, y0, r0, x1, y1, r1)
            % Helper function to calculate the two intersection points between two circles
            % Returns both intersection points and a validity flag
            
            % Calculate the distance between the centers
            dx = x1 - x0;
            dy = y1 - y0;
            d = sqrt(dx^2 + dy^2);
            
            % Check if there are valid intersection points
            if d > r0 + r1 || d < abs(r0 - r1) || d <= 0.001
                % No valid intersection points
                p1x = []; p1y = [];
                p2x = []; p2y = [];
                valid = false;
                return;
            end
            
            % Normalize the direction vector between the two centers
            dx = dx / d;
            dy = dy / d;
            
            % Calculate 'a' (distance from the center of the first circle to the point
            % where the line through the intersection points intersects the line between the centers)
            a = (r0^2 - r1^2 + d^2) / (2 * d);
            
            % Calculate the midpoint (px, py) on the line between the centers
            px = x0 + a * dx;
            py = y0 + a * dy;
            
            % Calculate the distance from (px, py) to the intersection points
            h = sqrt(r0^2 - a^2);
            
            % Calculate the intersection points
            p1x = px + h * dy;
            p1y = py - h * dx;
            p2x = px - h * dy;
            p2y = py + h * dx;
            
            % Mark the intersection as valid
            valid = true;
        end
        
        function dist = euclideanDistance(x1, y1, x2, y2)
            % Compute the Euclidean distance between two points
            dist = sqrt((x2 - x1)^2 + (y2 - y1)^2);
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

            pointJointFolder = fullfile(pointFolder, 'Joint');
            pointLinkCoMFolder = fullfile(pointFolder, 'LinkCoM');

            % Create subdirectories if they don't exist
            if ~exist(pointJointFolder, 'dir')
                mkdir(pointJointFolder);
            end
            if ~exist(pointLinkCoMFolder, 'dir')
                mkdir(pointLinkCoMFolder);
            end

            % Angle data is saved directly under Pos
            angleFolder = fullfile(posDir, 'Angle');  % Changed location under Pos
            if ~exist(angleFolder, 'dir')
                mkdir(angleFolder);
            end

            angleJointFolder = fullfile(angleFolder, 'Joint'); 
            angleLinkCoMFolder = fullfile(angleFolder, 'LinkCoM');

            % Create subdirectories if they don't exist
            if ~exist(angleJointFolder, 'dir')
                mkdir(angleJointFolder);
            end
            if ~exist(angleLinkCoMFolder, 'dir')
                mkdir(angleLinkCoMFolder);
            end

            % Save Joint data
            jointNames = fieldnames(Mechanism.Joint);
            for i = 1:length(jointNames)
                jointName = jointNames{i};
                tempStruct = struct(jointName, Mechanism.Joint.(jointName));
                save(fullfile(pointJointFolder, jointName), '-struct', 'tempStruct', jointName);
            end

            % Save Tracer Point data
            tracerPointNames = fieldnames(Mechanism.TracerPoint);
            for i = 1:length(tracerPointNames)
                tracerPointName = tracerPointNames{i};
                tempStruct = struct(tracerPointName, Mechanism.TracerPoint.(tracerPointName));
                save(fullfile(pointJointFolder, tracerPointName), '-struct', 'tempStruct', tracerPointName);
            end

            % Save Link CoM data
            linkNames = fieldnames(Mechanism.LinkCoM);
            for i = 1:length(linkNames)
                linkName = linkNames{i};
                tempStruct = struct(linkName, Mechanism.LinkCoM.(linkName));
                save(fullfile(pointLinkCoMFolder, linkName), '-struct', 'tempStruct', linkName);
            end

            % Save angle for each Link CoM
            for i = 1:length(linkNames)
                linkName = linkNames{i};
                tempStruct = struct(linkName, Mechanism.Angle.Link.(linkName));
                save(fullfile(angleLinkCoMFolder, linkName), '-struct', 'tempStruct', linkName);
            end
            % Save angle for each sensor 
            for i = 1:length(tracerPointNames)
                tracerPointName = tracerPointNames{i};
                tempStruct = struct(tracerPointName, Mechanism.Angle.Joint.(tracerPointName));
                save(fullfile(angleJointFolder, tracerPointName), '-struct', 'tempStruct', tracerPointName);
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

%         function [x_calc, y_calc, determined_index] = determineTracerJoint(x1, y1, r1, x2, y2, r2, pointX, pointY, index)
%             % Determine the next joint position using circle-circle intersection
%             % Inputs:
%             % x1, y1, r1: Position and radius of the first joint
%             % x2, y2, r2: Position and radius of the second joint
%             % pointX, pointY: Previous point position
%             % index: Index of the intersection point to use (1 or 2). If unknown, pass []
%         
%             % Calculate the distance between the two centers
%             d = sqrt((x2 - x1)^2 + (y2 - y1)^2);
%         
%             % Check if the circles intersect
%             if d > r1 + r2 || d < abs(r1 - r2) || d == 0
%                 error('Circles do not intersect or are degenerate.');
%             end
%         
%             % Calculate the midpoint between the circle centers
%             a = (r1^2 - r2^2 + d^2) / (2 * d);
%             h = sqrt(r1^2 - a^2);
%         
%             % Determine the intersection points
%             px = x1 + a * (x2 - x1) / d;
%             py = y1 + a * (y2 - y1) / d;
%         
%             % Offset for intersection points
%             offset_x = h * (y2 - y1) / d;
%             offset_y = h * (x2 - x1) / d;
%         
%             % Two possible intersection points
%             intersection1 = [px + offset_x, py - offset_y];
%             intersection2 = [px - offset_x, py + offset_y];
%         
%             % Determine index if not provided
%             if isempty(index)
%                 dist1 = sqrt((intersection1(1) - pointX)^2 + (intersection1(2) - pointY)^2);
%                 dist2 = sqrt((intersection2(1) - pointX)^2 + (intersection2(2) - pointY)^2);
%         
%                 if dist1 < dist2
%                     determined_index = 1;
%                     selected_point = intersection1;
%                 else
%                     determined_index = 2;
%                     selected_point = intersection2;
%                 end
%             else
%                 determined_index = index;
%                 % Select the desired intersection point based on the index
%                 if index == 1
%                     selected_point = intersection1;
%                 elseif index == 2
%                     selected_point = intersection2;
%                 else
%                     error('Index must be 1 or 2.');
%                 end
%             end
%         
%             % Assign the calculated position
%             x_calc = selected_point(1);
%             y_calc = selected_point(2);
%         end
        function [determined_index] = determineIntersectionIndex(x1, y1, r1, x2, y2, r2, pointX, pointY)
            % Determine the index of the closest intersection point
            % Inputs:
            % x1, y1, r1: Position and radius of the first joint
            % x2, y2, r2: Position and radius of the second joint
            % pointX, pointY: Previous point position
        
            % Calculate the distance between the two centers
            d = sqrt((x2 - x1)^2 + (y2 - y1)^2);
        
            % Check if the circles intersect
            if d > r1 + r2 || d < abs(r1 - r2) || d == 0
                error('Circles do not intersect or are degenerate.');
            end
        
            % Calculate the midpoint between the circle centers
            a = (r1^2 - r2^2 + d^2) / (2 * d);
            h = sqrt(r1^2 - a^2);
        
            % Determine the intersection points
            px = x1 + a * (x2 - x1) / d;
            py = y1 + a * (y2 - y1) / d;
        
            % Offset for intersection points
            offset_x = h * (y2 - y1) / d;
            offset_y = h * (x2 - x1) / d;
        
            % Two possible intersection points
            intersection1 = [px + offset_x, py - offset_y];
            intersection2 = [px - offset_x, py + offset_y];
        
            % Determine the index of the closest intersection point
            dist1 = sqrt((intersection1(1) - pointX)^2 + (intersection1(2) - pointY)^2);
            dist2 = sqrt((intersection2(1) - pointX)^2 + (intersection2(2) - pointY)^2);
        
            if dist1 < dist2
                determined_index = 1;
            else
                determined_index = 2;
            end
        end
        
        function curPoint = determineTracerPoint(x1, y1, r1, x2, y2, r2, pointX, pointY, index)
            % Determine the next joint position using circle-circle intersection
            % Inputs:
            % x1, y1, r1: Position and radius of the first joint
            % x2, y2, r2: Position and radius of the second joint
            % pointX, pointY: Previous point position
            % index: Index of the intersection point to use (1 or 2)
        
            % Calculate the distance between the two centers
            d = sqrt((x2 - x1)^2 + (y2 - y1)^2);
        
            % Check if the circles intersect
            if d > r1 + r2 || d < abs(r1 - r2) || d == 0
                error('Circles do not intersect or are degenerate.');
            end
        
            % Calculate the midpoint between the circle centers
            a = (r1^2 - r2^2 + d^2) / (2 * d);
            h = sqrt(r1^2 - a^2);
        
            % Determine the intersection points
            px = x1 + a * (x2 - x1) / d;
            py = y1 + a * (y2 - y1) / d;
        
            % Offset for intersection points
            offset_x = h * (y2 - y1) / d;
            offset_y = h * (x2 - x1) / d;
        
            % Two possible intersection points
            intersection1 = [px + offset_x, py - offset_y];
            intersection2 = [px - offset_x, py + offset_y];
        
            % Select the desired intersection point based on the index
            if index == 1
                selected_point = intersection1;
            elseif index == 2
                selected_point = intersection2;
            else
                error('Index must be 1 or 2.');
            end
        
            % Assign the calculated position
            x_calc = selected_point(1);
            y_calc = selected_point(2);
            curPoint = [x_calc, y_calc, 0];
        end


    end
end