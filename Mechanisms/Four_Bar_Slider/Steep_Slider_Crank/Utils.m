classdef Utils
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
    end
end