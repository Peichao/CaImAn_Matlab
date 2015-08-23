function [C,f,Y_res,P] = update_temporal_components(Y,A,b,Cin,fin,P,LD)

% update temporal components and background given spatial components

[d,T] = size(Y);
if ~isfield(P,'method'); method = 'constrained_foopsi'; else method = P.method; end
if ~isfield(P,'restimate_g'); restimate_g = 1; else restimate_g = P.restimate_g; end % re-estimate time constant (only with constrained foopsi)
if ~isfield(P,'temporal_iter'); ITER = 1; else ITER = P.temporal_iter; end
if isfield(P,'interp'); Y_interp = P.interp; else Y_interp = sparse(d,T); end
if isfield(P,'unsaturatedPix'); unsaturatedPix = P.unsaturatedPix; else unsaturatedPix = 1:d; end

mis_data = find(Y_interp);
Y(mis_data) = Y_interp(mis_data);

saturatedPix = setdiff(1:d,unsaturatedPix);
Ysat = Y(saturatedPix,:);
Asat = A(saturatedPix,:);
bsat = b(saturatedPix,:);
Y = Y(unsaturatedPix,:);
A = A(unsaturatedPix,:);
b = b(unsaturatedPix,:);
d = length(unsaturatedPix);

flag_G = 1;
if ~iscell(P.g)
    flag_G = 0;
    G = make_G_matrix(T,P.g);
end
nr = size(A,2);
A = [A,b];
Cin = [Cin;fin];
C = Cin;

if strcmpi(method,'noise_constrained')
    Y_res = Y - A*Cin;
    mc = min(d,15);  % number of constraints to be considered
    if nargin < 7
        LD = 10*ones(mc,nr);
    end
else
    nA = sum(A.^2);
    YrA = Y'*A - Cin'*(A'*A);
    if strcmpi(method,'constrained_foopsi') || strcmpi(method,'MCEM_foopsi')
        P.gn = cell(nr,1);
        P.b = cell(nr,1);
        P.c1 = cell(nr,1);           
        P.neuron_sn = cell(nr,1);
        options.bas_nonneg = 0;
        if isfield(P,'p'); options.p = P.p; else options.p = length(P.g); end
        if isfield(P,'fudge_factor'); options.fudge_factor = P.fudge_factor; end
    end
end
for iter = 1:ITER
    perm = randperm(nr+1);
    for jj = 1:nr
        ii = perm(jj);
        if ii<=nr
            if flag_G
                G = make_G_matrix(T,P.g{ii});
            end
            switch method
                case 'project'
                    YrA(:,ii) = YrA(:,ii) + nA(ii)*Cin(ii,:)';
                    maxy = max(YrA(:,ii)/nA(ii));
                    cc = plain_foopsi(YrA(:,ii)/nA(ii)/maxy,G);
                    C(ii,:) = full(cc')*maxy;
                    YrA(:,ii) = YrA(:,ii) - nA(ii)*C(ii,:)';
                case 'constrained_foopsi'
                    YrA(:,ii) = YrA(:,ii) + nA(ii)*Cin(ii,:)';
                    if restimate_g
                        [cc,cb,c1,gn,sn,~] = constrained_foopsi(YrA(:,ii)/nA(ii),[],[],[],[],options);
                        P.gn{ii} = gn;
                    else
                        [cc,cb,c1,gn,sn,~] = constrained_foopsi(YrA(:,ii)/nA(ii),[],[],g,[],options);
                    end
                    gd = max(roots([1,-gn']));  % decay time constant for initial concentration
                    gd_vec = gd.^((0:T-1));
                    C(ii,:) = full(cc(:)' + cb + c1*gd_vec);
                    YrA(:,ii) = YrA(:,ii) - nA(ii)*C(ii,:)';
                    P.b{ii} = cb;
                    P.c1{ii} = c1;           
                    P.neuron_sn{ii} = sn;
                case 'MCEM_foopsi'
                    options.p = length(P.g);
                    YrA(:,ii) = YrA(:,ii) + nA(ii)*Cin(ii,:)';
                    [cc,cb,c1,gn,sn,~] = MCEM_foopsi(YrA(:,ii)/nA(ii),[],[],P.g,[],options);
                    gd = max(roots([1,-gn.g(:)']));
                    gd_vec = gd.^((0:T-1));
                    C(ii,:) = full(cc(:)' + cb + c1*gd_vec);
                    YrA(:,ii) = YrA(:,ii) - nA(ii)*C(ii,:)';
                    P.b{ii} = cb;
                    P.c1{ii} = c1;           
                    P.neuron_sn{ii} = sn;
                    P.gn{ii} = gn.g;
                case 'MCMC'
                    params.B = 300;
                    params.Nsamples = 400;
                    params.p = length(P.g);
                    YrA(:,ii) = YrA(:,ii) + nA(ii)*Cin(ii,:)';
                    SAMPLES = cont_ca_sampler(YrA(:,ii)/nA(ii),params);
                    C(ii,:) = make_mean_sample(SAMPLES,YrA(:,ii)/nA(ii));
                    YrA(:,ii) = YrA(:,ii) - nA(ii)*C(ii,:)';
                    P.b{ii} = mean(SAMPLES.Cb);
                    P.c1{ii} = mean(SAMPLES.Cin);
                    P.neuron_sn{ii} = sqrt(mean(SAMPLES.sn2));
                    P.gn{ii} = mean(exp(-1./SAMPLES.g));
                case 'noise_constrained'
                    Y_res = Y_res + A(:,ii)*Cin(ii,:);
                    [~,srt] = sort(A(:,ii),'descend');
                    ff = srt(1:mc);
                    [cc,LD(:,ii)] = lagrangian_foopsi_temporal(Y_res(ff,:),A(ff,ii),T*P.sn(unsaturatedPix(ff)).^2,G,LD(:,ii));        
                    C(ii,:) = full(cc');
                    Y_res = Y_res - A(:,ii)*cc';
            end
        else
            YrA(:,ii) = YrA(:,ii) + nA(ii)*Cin(ii,:)';
            cc = max(YrA(:,ii)/nA(ii),0);
            C(ii,:) = full(cc');
            YrA(:,ii) = YrA(:,ii) - nA(ii)*C(ii,:)';
        end
        if mod(jj,10) == 0
            fprintf('%i out of total %i temporal components updated \n',jj,nr);
        end
    end
    %disp(norm(Fin(1:nr,:) - F,'fro')/norm(F,'fro'));
    if norm(Cin - C,'fro')/norm(C,'fro') <= 1e-3
        % stop if the overall temporal component does not change by much
        break;
    else
        Cin = C;
    end
end

if ~strcmpi(method,'noise_constrained')
    Y_res = Y - A*C;
end

f = C(nr+1:end,:);
C = C(1:nr,:);
Y_res(unsaturatedPix,:) = Y_res;
Y_res(saturatedPix,:) = Ysat - Asat*C - bsat*f;