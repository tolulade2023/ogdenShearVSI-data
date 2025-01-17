function out=matrix_invrecfit4(indata,taxis,varargin)
%out=matrix_invrecfit(indata,taxis,['oddeven'])
%indata:        3D or 4D stack of image matrices (the same slice) acquired at different times (last dimension
%taxis:         times after which the images were acquired
%'oddeven':     option to average odd even slices, eliminates funky systematics
%'convergence': option to monitor the convergence of the amplitude plot
%'monitorplot': looks at chi2, deviation, and tau
%
%out.T1, out.amplitude contain the fitted results 

options=varargin;

indata=squeeze(indata);

if ndims(indata) == 3;                          %one slice, multiple times
    out = matrix_invrecfit_3d(indata,taxis,options{:});
elseif ndims(indata) ==4;                       %multislice, multiple times
    [ntd nph nsl nti] = size(indata);
    out.amplitude=zeros(ntd,nph,nsl);
    out.err_amplitude=zeros(ntd,nph,nsl);
    out.T1=zeros(ntd,nph,nsl);
    out.err_T1=zeros(ntd,nph,nsl);
    out.err_chi2=zeros(ntd,nph,nsl);
    
    for ns=1:nsl;
        oout= matrix_invrecfit_3d(squeeze(indata(:,:,ns,:)),taxis,options{:});
        out.amplitude(:,:,ns)=oout.amplitude;
        out.T1(:,:,ns)=oout.T1;
        out.err_amplitude(:,:,ns)=oout.err_amplitude;
        out.err_T1(:,:,ns)=oout.err_T1;
        %out.err_chi2(:,:,ns)=oout.err_chi2;
    end
end
out.T1(abs(out.T1(:))>5)=0;

function out=matrix_invrecfit_3d(incube,taxis,varargin)
%out=matrix_invrecfit_3d(incube,taxis,weighting)
%fit to exponential recovery
%incube: nro X npe (x numslices) X numel(taxis) is a stack of images acquired at different times
%the times passed down in the taxis.
%out is structure with fields 'amplitude' and 'T1', result of a pixelwise
%
%the inversion recovery  ' y= a*(1-2*exp(bt)) '
%can't be done by straight linear regression, so this routine implements an
%iterative linear regression, where an initial amplitude matrix a is
%guessed, then updated iteratively

options=varargin;

[taxis,sortindex]=sort(taxis); %sort by ascending times
incube=incube(:,:,sortindex);  %sort by ascending times

[tmin,tminind]=min(taxis);

%Third dimension is the echotime dimension
phase_matrix=incube(:,:,tminind)./abs(incube(:,:,tminind)); %phase of the image with the shortest wait time
phased_incube=zeros(size(incube));

%1. rotate the phase, short times are positive, long times negative
for nt=1:numel(taxis);
    phased_incube(:,:,nt)= real(incube(:,:,nt)./phase_matrix);
end

%2. generate a starting guess for the amplitude, 
% option 1: interpolating backwards on the two shortest times
%a0= abs( phased_incube(:,:,1) - (phased_incube(:,:,2)-phased_incube(:,:,1))/(taxis(2)-taxis(1)) * taxis(1) );
% option 2: half the sum of the first and last image
a0= (phased_incube(:,:,1)-phased_incube(:,:,end))/2;

noiseestimate=2*estimate_noiselevel(a0);

si=size(phased_incube);
test=zeros([si(1) si(2) numel(taxis)-1]);

%3. iteratively fit and update the amplitude guess
for jj=1:numel(taxis)-1;
    test(:,:,jj)=phased_incube(:,:,jj)+a0; 
end
outY=matrix_expfit(test,taxis(1:end-1));
initamp=outY.amplitude;
initTau=outY.Tau;
initTau(initTau<min(taxis))=1e-6;
initTau(initTau>5)=1e-6;

[n, bins]=hist(initTau(:),101);
n=n(2:end); sn=sum(n); sbins=cumsum(n); bins=bins(2:end); 
medianTau=bins(find(sbins>sn/2,1,'first'));
meanTau=sum(bins.*n)/sn;

%update the TR correction
if any(strcmp(options,'TR'));
    ind=find(strcmp(options,'TR'));
    TR=options{ind+1};
    TRT1correction=1.4*initamp.*exp(-TR./initTau);
else
    TRT1correction=zeros(size(initamp));
end

correction_multiplier=0.95*ones(size(TRT1correction));


niter=30;
si=size(phased_incube);
global chimon; chimon=zeros([si(1) si(2) niter]);
global devmon; devmon=zeros([si(1) si(2) niter]);
global taumon; taumon=zeros([si(1) si(2) niter]);
for jj=1:niter;
    for nt=1:numel(taxis);
        Y(:,:,nt)= phased_incube(:,:,nt)+initamp+TRT1correction;
    end
    
    outY=matrix_expfit(Y,taxis,options{:});
    
    if any(strcmp(options,'TR'));
        
        TRT1correction=TRT1correction.*correction_multiplier;
        %TRT1correction=(niter-jj)/niter*TRT1correction.*correction_multiplier+jj/niter*a0.*exp(-TR./outY.Tau);
        
        if jj==1;
            oldchi2=outY.error.chi2.chi2;
        else
            dummyind=outY.error.chi2.chi2<0.01;
            correction_multiplier(dummyind)=1;
        end
        chimon(:,:,jj)=outY.error.chi2.chi2;
        devmon(:,:,jj)=outY.error.chi2.dev2;
        taumon(:,:,jj)=outY.Tau;
    end
    
    initamp=outY.amplitude/2;
    
    monflag=false;
    if monflag
        dummyi=0;
        xvec=150:5:190;
        yvec=170:5:210;
        for xi= xvec;
            for yi=yvec;
                dummyi=dummyi+1;
                tsubplot(numel(xvec),numel(yvec),dummyi);
                ploterrs(xi,yi,outY.error.chi2);
                set(gca,'YLim',[2 10],'YTicklabel','','XTicklabel','');
            end
        end
        pause(0.1)
    end
    
end

%%
monflag=any(strcmp(options,'monitorplot'));
if monflag;
    si=size(initamp);
    xi=round(si(2)/2);
    yi=round(si(1)/2);
    figure;
    subplot(2,4,1);
    him=imagesc(initamp);
    h(1)=gca;
    set(him,'Hittest','off');
    set(gca,'YDir','normal','ButtonDownFcn','update_monitorplot');
    set(gca,'Tag', 'Magimage');
    caxis([0 20000]);
    hold on;
    title(['mag image (x,y)=(' num2str(xi) ',' num2str(yi) ')']);
    axis image
    
    subplot(2,4,2);
    him=imagesc(outY.Tau);
    set(gca,'clim',[0 2],'Ydir','normal');
    set(him,'Hittest','off');
    set(gca,'YDir','normal','ButtonDownFcn','update_monitorplot');
    axis image;
    title(['T1 image (x,y)=(' num2str(xi) ',' num2str(yi) ')']);
    set(gca,'Tag', 'Tauimage');
    hold on;
    
    
    
    subplot(2,2,2);
    plot(squeeze(taumon(yi,xi,:)),'-o');
    h(2)=gca;
    set(gca,'Tag','taumonitor','Ylim',[0 3]);
    title('Tau');
    
    subplot(2,2,3);
    plot(squeeze(chimon(yi,xi,:)),'-o');
    h(3)=gca;
    set(gca,'Tag','chimonitor','YLim',[0 2]);
    title('\chi^2');
    
    subplot(2,2,4);
    plot(squeeze(devmon(yi,xi,:)),'-o');
    h(4)=gca;
    set(gca,'Tag','devmonitor','YLim',[-0.1 1]);
    title('deviation');
end

%%
% fit it once more, now taking the average of the expected monoexponential
% inversion recovery correction and the correction found by chi2
if any(strcmp(options,'TR'));
    TRT1correction=(TRT1correction+initamp.*exp(-TR./outY.Tau))/2; 
    for nt=1:numel(taxis);
        Y(:,:,nt)= phased_incube(:,:,nt)+initamp+TRT1correction;
    end
    outY=matrix_expfit(Y,taxis,options{:});
end




out.amplitude=outY.amplitude/2;
out.T1=outY.Tau;
out.err_amplitude=outY.error.amplitude;
out.err_T1=outY.error.Tau;
out.err_chi2=outY.error.chi2.chi2;

