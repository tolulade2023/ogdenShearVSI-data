function [E_t] = F_t_to_E_t(F_t,vec)
switch vec
    case '3D'
        F_temp = convJonFtoDennisF(F_t);
        tlen = size(F_t,2);
        volsz = size(F_t{1,tlen}{1,1});
        for t = tlen:-1:1
            for i = volsz(1):-1:1
                for j = volsz(2):-1:1
                    for k = volsz(3):-1:1
                        F_calc = F_temp{t,i,j,k};
                        E_calc{t,i,j,k} = 0.5*(transpose(F_calc)*F_calc-eye(3));
                    end
                end
            end
        end
        E_t = convDennisFtoJonF(E_calc);
    case 'lin'
        sz = length(F_t{1}{1,1});
        for t = 1:length(F_t)
            for i = 1:sz
                F_calc = [F_t{t}{1,1}(i),F_t{t}{1,2}(i),F_t{t}{1,3}(i);
                    F_t{t}{2,1}(i),F_t{t}{2,2}(i),F_t{t}{2,3}(i);
                    F_t{t}{3,1}(i),F_t{t}{3,2}(i),F_t{t}{3,3}(i)];
                U_calc = sqrtm(transpose(F_calc)*F_calc);
                E_calc = 0.5*(U_calc*U_calc-eye(3));
                for j = 1:3
                    for k = 1:3
                        E_t{t}{j,k}(i) = E_calc(j,k);
                    end
                end
            end
        end
end
end