function defgrad = convJonFtoDennisF_lin(jonF)

tlen = size(jonF,2); %should be t, i, j, k
try
    volsz = size(jonF{1,tlen}{1,1});
%     F11 = ones(szDG(2),szDG(3),szDG(4));
%     F22 = F11; F33 = F11;
%     F12 = zeros(szDG(2),szDG(3),szDG(4));
%     F13 = F12; F21 = F12; F23 = F12; F31 = F12; F32 = F12;
%
%% Match up the indices by looping
for t = tlen:-1:1
    for i = volsz(1):-1:1
        for j = volsz(2):-1:1
                defgrad{t,i,j}(1,1) = jonF{t}{1,1}(i,j);
                defgrad{t,i,j}(1,2) = jonF{t}{1,2}(i,j);
                defgrad{t,i,j}(1,3) = jonF{t}{1,3}(i,j);
                defgrad{t,i,j}(2,1) = jonF{t}{2,1}(i,j);
                defgrad{t,i,j}(2,2) = jonF{t}{2,2}(i,j);
                defgrad{t,i,j}(2,3) = jonF{t}{2,3}(i,j);
                defgrad{t,i,j}(3,1) = jonF{t}{3,1}(i,j);
                defgrad{t,i,j}(3,2) = jonF{t}{3,2}(i,j);
                defgrad{t,i,j}(3,3) = jonF{t}{3,3}(i,j);
        end
    end

end
catch
    volsz = size(jonF{1,1});
    for i = volsz(1):-1:1
        for j = volsz(2):-1:1
                defgrad{i,j}(1,1) = jonF{1,1}(i,j);
                defgrad{i,j}(1,2) = jonF{1,2}(i,j);
                defgrad{i,j}(1,3) = jonF{1,3}(i,j);
                defgrad{i,j}(2,1) = jonF{2,1}(i,j);
                defgrad{i,j}(2,2) = jonF{2,2}(i,j);
                defgrad{i,j}(2,3) = jonF{2,3}(i,j);
                defgrad{i,j}(3,1) = jonF{3,1}(i,j);
                defgrad{i,j}(3,2) = jonF{3,2}(i,j);
                defgrad{i,j}(3,3) = jonF{3,3}(i,j);
        end
    end

end

end