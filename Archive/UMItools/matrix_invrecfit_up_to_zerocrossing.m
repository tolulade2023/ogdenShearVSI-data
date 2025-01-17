function out=matrix_invrecfit_up_to_zerocrossing(varargin)
%out=matrix_invrecfit_up_to_zerocrossing(incube,taxis,weighting)
%incube is a stack of image matrices (the same slice) acquired at different times
%taxis is an axis of times;

indata=squeeze(varargin{1});
taxis=varargin{2};

if ndims(indata) == 3;                          %one slice, multiple times
    out = matrix_invrecfit_3d(indata,taxis);
elseif ndims(indata) ==4;                       %multislice, multiple times
    [ntd nph nsl nti] = size(indata);
    out.amplitude=zeros(ntd,nph,nsl);
    out.Tau=zeros(ntd,nph,nsl);
    for ns=1:nsl;
        oout= matrix_invrecfit_3d(squeeze(indata(:,:,ns,:)),taxis);
        out.amplitude(:,:,ns)=oout.amplitude(:,:);
        out.Tau(:,:,ns)=oout.Tau(:,:);
    end
end
out.Tau(abs(out.Tau(:))>5)=0;

function out=matrix_invrecfit_3d(varargin)
%out=matrix_invrecfit_3d(incube,taxis,weighting)
%fit to exponential recovery
%incube: nro X npe (x numslices) X numel(taxis) is a stack of images acquired at different times
%the times passed down in the taxis.
%out is structure with fields 'amplitude' and 'Tau', result of a pixelwise
%
%the inversion recovery  ' y= a*(1-2*exp(bt)) '
%can't be done by straight linear regression, so this routine implements an
%iterative linear regression, where an initail amplitude matrix a is
%guessed, then updated iteratively
%log[-(y-a)/2] = log(a) + bt;

incube=varargin{1};
taxis=varargin{2};
[taxis,sortindex]=sort(taxis); %sort by ascending times
incube=incube(:,:,sortindex);  %sort by ascending times

[tmax,tmaxind]=max(taxis);
[tmin,tminind]=min(taxis);


%third dimension is the echotime dimension
phasemat=incube(:,:,tminind)./abs(incube(:,:,tminind)); %phase of the image with the shortest wait time
phincube=zeros(size(incube));

%1. rotate the phase, short times are positive, long times negative
for nt=1:numel(taxis);
    phincube(:,:,nt)= incube(:,:,nt)./phasemat; %rotate signal into the imaginary axis
end



%2. generate a starting guess for the amplitude, using the two shortest
%times and interpolating backwards
a0= abs(phincube(:,:,1) - (phincube(:,:,2)-phincube(:,:,1))/(taxis(2)-taxis(1)) * taxis(1));

%2b. weighting
weight_post_zero_crossing=0.1;
weighting=ones(size(phincube));
weighting(phincube<0)=weight_post_zero_crossing;

%3. iteratively fit and update the amplitude guess
si=size(phincube);
Y=zeros(size(phincube));

niter=20;
for jj=1:niter;
    for nt=1:numel(taxis);
        Y(:,:,nt)= phincube(:,:,nt)+a0;
    end
    %outY=matrix_expfit(Y,taxis,'weighting',weighting);
    outY=matrix_expfit(Y,taxis,'oddeven');
    
    F=outY.amplitude/2;
    mesh(F-a0);
    set(gca,'clim',5e3*[-1 1],'zlim',[-5000 5000]); title(num2str(jj)); pause(0.1);
    %imagesc(gg);
    
    %update the amplitude guess%%%%%
    if jj==1;
        a0 = F/2;
    else
        a0=(a0+F)/2;
        %stepsize = min(0.1, 0.1*gg/ogg);
        %a0 = (1-sign(gg).*stepsize).*a0;
    end
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
end

out.amplitude=F;
out.Tau=outY.Tau;


