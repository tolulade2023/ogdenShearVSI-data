function out=varianms(varargin)
%out=varianms(filename, [option1, option2....]);
%if filename is a file, we are anlyzing fid's
%if filename is a directory, then we are reading the images (fdf's)
%if filename is a 4 digit number, and 'fid' is not an argument, open the image directory
%created by vjnmr, and stack them into a file;
%options:
%'plot'     : plots the slices, additional option 'col' makes a colorplot 
%'iso'      : (default as 11/2016) zerofill (if time domain) or interpolate (if images) to make isotropic pixels
%'1k'       : force 1k pixels in each direction
%'512'      : force 512 pixels in each direction '192', '256', '384'
%'zf'       : zero fills 1.5 times in each direction, when analyzing fids
%'zf2'      : zero fills 2 times, in each direction, when analyzing fids
%'zf3'      : zerofills in the third dimension, for 3D acquisitions only
%'fliplr'   : flips the images left-right
%'flipud'	: flips the images up-down
%'flipfb'   : flips front and back
%'filter'   : running gaussian filter, sigma=0.8pixels
%'apod'     : apodization (smooth roll off, optional 2d or 1d number input [kx/kmax,ky/kmax] or [k/kmax] sets where roll off begins
%'upsample' : double the matrix in each direction by interpolation (careful, may not work with complex numbers
%'gradlag'  : shift the timedomain data by gradlag (microseconds) to reduce readout roll
%'freq'     : shift the resonance frequency (shift in time domain)
%'shphase'  : shift the image in the PE direction, [-1 1]
%'norm'     : normalize by the slice thickness

%check if the filename is image or fid, directory or file
[inputtype,varargin{1}]=check_img_or_fid(varargin{1});

%make it iso by default
if ~any(strcmp(varargin,'iso'));
    varargin=[varargin 'iso'];
end


if strcmp(inputtype{1}, 'timedomain');          %a filename or directory for the fid was handed down
    display('Reconstructing complex images from fid...')
    if strcmp(inputtype{2}, 'directory');
        varargin{1}=[varargin{1} '/fid'];
    end
    out=reconfids(varargin{:});
    image=out.image;
    pars=out.pars;
    
else   %an image file or directory is to be read
    display('Reading real images from Varian .fdf files.');
    if strcmp(inputtype{2}, 'directory');
        d=dir(varargin{1});
        names={d.name};
        for jj=1:numel(d);
            nam=names{jj}; %dummy is a cell array, the first entry is the file name
            matchflag(jj)=~isempty(regexp(nam, '\w+\.fdf'));
        end
        numslabsorslices=sum(matchflag);
        nam=names(matchflag);
        for jjj=1:numslabsorslices;
            rdfdf=readfdf([varargin{1} '/' nam{jjj}]);
            if jjj==1;
                image=zeros([size(rdfdf.image) numslabsorslices]);
            end
            si=size(rdfdf.image);
            switch numel(si);
                case 2
                    image(:,:,jjj)=rdfdf.image;     %multislice
                case 3
                    image(:,:,:,jjj)=rdfdf.image;   %multislab
            end
        end
        pars=getparameters([varargin{1} '/procpar']);
        %pars.lpe=pars.span{1};
        %pars.lro=pars.span{2};
    elseif strcmp(inputtype{2}, 'file');
        rdfdf=readfdf(varargin{1});
        image=rdfdf.image;
        %pars=rdfdf.pars;
        %check this later, to see if axes are changed by orientation info
        pars=getparameters('procpar');
        %pars.lpe=pars.span{1};
        %pars.lro=pars.span{2};
    end
    
    %image files have been read, but the pixels may not be square
    si_image=size(image);
    imres(2)=pars.lpe./si_image(2);  %cm/pixel  xaxis
    imres(1)=pars.lro./si_image(1);  %cm/pixel  yaxis
    
    if any(strcmp('iso',varargin));
        %
        highest_resolution=min(imres);  
        highest_resolution=highest_resolution(1);
        largest_FOV=max(pars.lpe,pars.lro);
        largest_FOV=largest_FOV(1);
        smallest_FOV=min(pars.lpe,pars.lro);
        
        %display a warning that this data set has anisotropic FOV
        if abs((1-smallest_FOV/largest_FOV))>0.01;
            display('This data set was acquired with a non-square field of view.')
            display('Images are made isotropic and square in varianms.m');
            display('out.pars.lpe and out.pars.lro were updated.');
        end
        
        npts=round(largest_FOV/highest_resolution);
        y_tempaxis=(1:si_image(1)+2)*imres(1);
        y_tempaxis(1)=0;
        y_tempaxis(end)=100;                        %100cmFOV
        x_tempaxis=(1:si_image(2)+2)*imres(2);
        x_tempaxis(1)=0;
        x_tempaxis(end)=100;                             %100cmFOV
        [Xtmp,Ytmp]=meshgrid(x_tempaxis,y_tempaxis);
        
        %upsample the dimension with fewer points
        nsl=numel(image)/(si_image(1)*si_image(2));
        newimages=zeros([npts npts si_image(3:end)]);
        [XX,YY]=meshgrid((1:npts)/npts*largest_FOV,(1:npts)/npts*largest_FOV);
        pars.lpe=largest_FOV;
        pars.lro=largest_FOV;
        for ns=1:nsl;
            src=zeros(size(Xtmp));
            src(1:si_image(1),1:si_image(2))=image(:,:,ns);
            newimages(:,:,ns)=interp2(Xtmp,Ytmp,src,XX,YY);
        end
        image=newimages;
    end
    out.kspace=[];
    
    %reshape the image files;
    si_image=size(image);
    if isfield(pars,'arraydim') && pars.arraydim~=pars.nv;
        image=squeeze(reshape(image,[si_image(1:2) pars.arraydim pars.ne pars.ns 1 1 1]));
    else
        image=squeeze(reshape(image,[si_image(1:2) pars.ne pars.ns 1 1 1]));
    end
    image=squeeze(permute(image,[1 2 4 3 5 6 7]));
end
%End distintion of whether data is derived from FID or from IMG source

%check if image should be shifted in the phase direction
if any(strcmp(varargin,'shphase'));
    ii=find(strcmp(varargin,'shphase'));
    if nargin>ii && isnumeric(varargin{ii+1}) && varargin{ii+1}>=-0.5 && varargin{ii+1}<=0.5;
        
        si_image=size(image);
        shiftindex=-round(si_image(2)*varargin{ii+1});
        pindex=1+mod(shiftindex+(0:si_image(2)-1),si_image(2));
        numsl=numel(image)/(si_image(1)*si_image(2));
        for ns=1:numsl;
            image(:,:,ns)=image(:,pindex,ns);
            
        end
    else
        display('aborted: varianms Input argument shphase must be followed by a number in [-0.5 0.5].');
        return
    end
end

%check if image should be flipped;
fliplr_flag=strcmp(varargin,'fliplr');
flipud_flag=strcmp(varargin,'flipud');
if any(fliplr_flag | flipud_flag);		%some flipping has been requested, execute it in the order it was requested
    si_image=size(image);
    numsl=numel(image)/(si_image(1)*si_image(2));
    for ns=1:numsl;
        if any(fliplr_flag);
            image(:,:,ns)=fliplr(image(:,:,ns));
        end
        if any(flipud_flag);
            image(:,:,ns)=flipud(image(:,:,ns));
        end
    end
end

%check if image should be filtered
if any(strcmp(varargin,'filter'));
    si_image=size(image);
    numsl=numel(image)/(si_image(1)*si_image(2));
    kfilter=[];
    ind=find(strcmp(varargin,'filter'));
    if nargin>ind && isreal(varargin{ind+1});
        %a filter length (in pixels) has been defined;
        [dummy,kfilter]=blur(image(:,:,1),varargin{ind+1});
    end
    
    for ns=1:numsl;
        display(['Filtering image ' num2str(ns) ' in varianms.m....'])
        [image(:,:,ns),kfilter]=blur(image(:,:,ns),kfilter);
    end
    
    %redistribute the dimensions
    image=reshape(image,si_image);
    clear smi;
    
    %if real image files were read, then take the absolute value of the
    %image
    if strcmp(inputtype{1}, 'image');
        image=abs(image);
    end
end

%check if image should be upsampled, if .img files where read only
if strcmp(inputtype{1},'image') && (any(strcmp(varargin,'upsample')) || ...
        any(strcmp(varargin,'1k')) || any(strcmp(varargin,'1K'))  || any(strcmp(varargin,'512')) || any(strcmp(varargin,'256')) ...
        || any(strcmp(varargin,'1024')) || any(strcmp(varargin,'384')) || any(strcmp(varargin,'192')));
    si_image=size(image);
    numsl=numel(image)/(si_image(1)*si_image(2));
    if any(strcmp(varargin,'1k')) || any(strcmp(varargin,'1K')) || any(strcmp(varargin,'1024'));
        interpfactor(1)=1024/si_image(1);
        interpfactor(2)=1024/si_image(2);
        newi=1024;
        newj=1024;
    elseif any(strcmp(varargin,'512'));
        interpfactor(1)=512/si_image(1);
        interpfactor(2)=512/si_image(2);
        newi=512;
        newj=512;
    elseif any(strcmp(varargin,'384'));
        interpfactor(1)=384/si_image(1);
        interpfactor(2)=384/si_image(2);
        newi=384;
        newj=384;
    elseif any(strcmp(varargin,'192'));
        interpfactor(1)=192/si_image(1);
        interpfactor(2)=192/si_image(2);
        newi=192;
        newj=192;
    elseif any(strcmp(varargin,'256'));
        interpfactor(1)=256/si_image(1);
        interpfactor(2)=256/si_image(2);
        newi=256;
        newj=256;
    else
        interpfactor=[2 2];
        newi=interpfactor(1)*si_image(1);
        newj=interpfactor(2)*si_image(2);
    end
    smi=zeros(newi, newj,numsl); %interpolated search matrices
    [XX,YY]=meshgrid((0:si_image(2)),(0:si_image(1))');
    for ns=1:numsl;
        %diplay according to options
        if any(strcmp(varargin,'1k')) || any(strcmp(varargin,'1K')) || any(strcmp(varargin,'1024'));
            display(['Setting image ' num2str(ns) ' to 1024 resolution in varianms....']);
        elseif any(strcmp(varargin,'512'));
            display(['Setting image ' num2str(ns) ' to 512 resolution in varianms....']);
        elseif any(strcmp(varargin,'256'));
            display(['Setting image ' num2str(ns) ' to 256 resolution in varianms....']);
        elseif any(strcmp(varargin,'384'));
            display(['Setting image ' num2str(ns) ' to 384 resolution in varianms....']);
        elseif any(strcmp(varargin,'192'));
            display(['Setting image ' num2str(ns) ' to 192 resolution in varianms....']);
        else
            display(['Upsampling image twofold ' num2str(ns) ' in varianms.m....'])
        end
        ZZ=zeros(size(XX));		%magnitude
        ZZ(2:si_image(1)+1,2:si_image(2)+1)=abs(image(:,:,ns));
        smi(:,:,ns)=interp2(XX,YY,ZZ,(1:newj)/interpfactor(2),(1:newi)'/interpfactor(1),'*cubic');
        
        ZZi=zeros(size(XX));	%phase
        smi_phase=ZZi;
        ZZi(2:si_image(1)+1,2:si_image(2)+1)=angle(image(:,:,ns));
        smi_phase=interp2(XX,YY,ZZi,(1:newj)/interpfactor(2),(1:newi)'/interpfactor(1),'linear');
        
        smi(:,:,ns)=smi(:,:,ns).*exp(1i*smi_phase);
    end
    
    %redistribute the dimensions
    si_smi=size(smi);
    image=reshape(smi,[si_smi(1:2) si_image(3:end)]);
    clear smi;
end

%optional flipfb front to back
flipfb_flag=any(strcmp(varargin,'flipfb'));
if flipfb_flag && ndims(image)>2;
    si=size(image);
    image=image(:,:,end:-1:1,:,:,:,:);
end


out.image=image;
out.pars=pars;

%make axes for plotting
si=size(image);
if out.pars.phi==0;
    %RO is ydirection, PE is x direction
    out.pars.yaxis=-((1:si(1))/si(1)*out.pars.lro+out.pars.pro)*10;
    out.pars.xaxis=((1:si(2))/si(2)*out.pars.lpe+out.pars.ppe)*10;
elseif out.pars.phi==90;
    out.pars.yaxis=-((1:si(1))/si(1)*out.pars.lpe+out.pars.ppe)*10;
    out.pars.xaxis=((1:si(2))/si(2)*out.pars.lro+out.pars.pro)*10;
else
    out.pars.yaxis=-((1:si(1))/si(1)*out.pars.lro)*10;
    out.pars.xaxis=((1:si(2))/si(2)*out.pars.lpe)*10;
end
if ~isempty(strfind(out.pars.seqfil,'ge3d'));
    out.pars.zaxis=((1:si(3))/si(3)*out.pars.lpe2)*10;
end

%make a surveyplot
if any(strcmp(varargin,'plot'));
   h=slice_surveyplot([{image} varargin]);
end

function out=reconfids(varargin)
filename=varargin{1};
path=fileparts(filename);   %path of fid file to be read
if ~isempty(path);          %pwd is higher up
    procparfile=[path '/procpar'];
    pathname=path;
    %define the path to vnmrsys, to be able to find other auxiliary files
    currentdir=pwd;
    cd(path);
    ind=regexp(pwd,'vnmrsys');
    dummy=pwd;
    pvnmr=[dummy(1:ind-1) 'vnmrsys/'];
    cd(currentdir);
else
    procparfile='procpar';  %the current working directory contains the fid and procpar
    ind=regexp(pwd,'vnmrsys');
    dummy=pwd;
    pathname=pwd;
    pvnmr=[dummy(1:ind-1) 'vnmrsys/'];
end

%load a list of parameters from procpar, which may/will come in handy when
%generating images
pc=getparameters(procparfile);
pc.pathname=pathname;

%read the data into a matrix, td rows and however many columns
[acquireddata,header]=readit(filename);

%check if the gradient lag in the readout direction is specified
remainshift=0;
kshift=0;
if any(strcmp(varargin,'gradlag'));
    dii=find(strcmp(varargin,'gradlag'));
    if numel(varargin)>dii
        if isfloat(varargin{dii+1});
            graddelay=varargin{dii+1};
        else
            graddelay=30; %microseconds
        end
    else
        graddelay=30; %microseconds
    end
    si=size(acquireddata);
    ntd=si(1);
    dwell=pc.at/ntd;
	
    tdshift=round(graddelay*1e-6/dwell);
	remainshift=graddelay-tdshift*dwell*1e6;
	kshift=remainshift*1e-6/dwell*2*pi;
	
    dummy=zeros(size(acquireddata));
    if tdshift>=0;
        dummy(1:ntd-tdshift,:)=acquireddata(1+tdshift:ntd,:);
    else
        tdshift=-tdshift;
        dummy(1+tdshift:ntd,:)=acquireddata(1:ntd-tdshift,:);
    end
    acquireddata=dummy;
    clear dummy;
end

%rearrange the data according to what pulse sequence it is
si=size(acquireddata); %td x number of traces
td=si(1);
switchstring=pc.seqfil;

%replace the switch string with a generic switchstring, to allow multiple
%versions of the same sequence (differing by a number or an appendix)
seqclass='dwssgg'; if ~isempty(findstr(switchstring,seqclass)); switchstring=seqclass; end
seqclass='gesege'; if ~isempty(findstr(switchstring,seqclass)); switchstring=seqclass; end
seqclass='fsems'; if ~isempty(findstr(switchstring,seqclass)) && ~strcmp('sems',switchstring); switchstring=seqclass; end
seqclass='stems'; if ~isempty(findstr(switchstring,seqclass)); switchstring=seqclass; end;
seqclass='tagcine'; if ~isempty(findstr(switchstring,seqclass)); switchstring=seqclass; end
seqclass='ge3d'; if ~isempty(findstr(switchstring,seqclass)); switchstring=seqclass; end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
acquisitiontype='2D';       %this is the default type
                            %any 3D sequences in the switch seegment below
                            %need to set this to '3D';
navigatorflag=false;        %default no navigator

switch lower(switchstring)
    case {'sems'; 'semsdw'; 'stems';'stemsdw';'gems';'gemsvc'};%%%%%%%%%%%%%%%%%%%%%% single echo/FID multislice
        rem=numel(acquireddata)/si(1)/pc.ns/pc.nv;
        
        %time phase slice block/array
        if strcmp(pc.seqcon,'nssnn');
            acquireddata=reshape(acquireddata,[si(1) pc.ns*rem pc.nv]);
            acquireddata=permute(acquireddata,[1 3 2]);
        elseif numel(pc.ti)== rem; %straight inversion recovery;
            acquireddata=reshape(acquireddata,[si(1) pc.ns rem pc.nv]);  %seqcon=nccnn
            acquireddata=permute(acquireddata,[1 4 2 3]);
        else
            acquireddata=reshape(acquireddata,[si(1) pc.ns pc.nv rem]);  %seqcon=nccnn
            acquireddata=permute(acquireddata,[1 3 2 4]);
        end
    case {'mems'; 'mgems';'mems_us';'mgems_us';'dwsemgems_us'; ...
            'dwgs1';'dwssgg'};%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% multiecho multislice (T2-weighting)
        rem=numel(acquireddata)/si(1)/pc.ne/pc.ns/pc.nv; %remainder
        
        %check if the data came in blocks, if it did, that is an arrayed
        %experiment, and varian stacks this into the second dimension! 
        
        %check if there are multiple parameters arrayed
        if ~isempty(strfind(pc.array,',')); %there is a comma (punctuation) in the parameter pc.arrary 
            number_of_arrayed_variables = numel(strfind(pc.array,','))+1;
            separatorindices=strfind(pc.array,',');
            switch number_of_arrayed_variables;
                case 2;
                    arrvar{1}=pc.array(1:(separatorindices(1)-1));
                    arrvar{2}=pc.array(separatorindices(1)+1:end);
                case 3
                    arrvar{1}=pc.array(1:(separatorindices(1)-1));
                    arrvar{2}=pc.array(separatorindices(1)+1:separatorindices(2)-1);
                    arrvar{3}=pc.array(separatorindices(2)+1:end);
            end
        else
            if ~isempty(pc.array);
                arrvar{1}=pc.array;
            end
        end
        
        if ~isempty(pc.array);
            for jj=1:numel(arrvar);
                remcount(jj)= numel(eval(['pc.' arrvar{jj}]));
            end
            rem=prod(remcount);
            acquireddata=reshape(acquireddata,[si(1) pc.ne pc.ns rem pc.nv]);  %seqcon = ccsnn (echo slice ph1 ph2 ph3)
            acquireddata=permute(acquireddata,[1 5 3 2 4]);
            si=size(acquireddata);
            acquireddata=reshape(acquireddata,[si(1:end-1) remcount(end:-1:1)]);
        else
            rem=1;
            remcount=1;
            acquireddata=reshape(acquireddata,[si(1) pc.ne pc.ns pc.nv rem]);  %seqcon = ccsnn (echo slice ph1 ph2 ph3)
            acquireddata=permute(acquireddata,[1 4 3 2 5]);
        end
        
        %time phase slice echo block/array
        
    case {'fsems'; 'fsemsdw'}  %%%%%%%%%%%%%%%%%%%%%%%%%%% fast spin echo (multiecho, different k each echo) multislice
        if strcmp(pc.navigator,'y');
            navigatorflag=true;
            %Navigator
            %for now it is not clear to me how procpar indexes the
            %navigators, but by inspection I see them at the end
            if strcmp(pc.nav_type,'pairwise');
                num_navs=2;
            else
                num_navs=1;
            end
            
            rem=numel(acquireddata)/si(1)/pc.ns/pc.nv/(pc.etl+num_navs)*pc.etl;
            nsegs=pc.nv/pc.etl;
            acquireddata=reshape(acquireddata,[si(1) (pc.etl + num_navs) pc.ns nsegs rem]);  %seqcon = nccnn
            siacq=size(acquireddata);
            %navigatorscalars=(sum(sum(squeeze(acquireddata(siacq(1)/2+(-7:7),(siacq(2)-(num_navs-1)):siacq(2),:,:,:,:,:)),2),1)); %for 2 navigators at the end;
            navigatorscalars=(sum(sum(squeeze(abs(acquireddata(:,(siacq(2)-(num_navs-1)):siacq(2),:,:,:,:,:))),2),1)); %for 2 navigators at the end;
            
            complexnavigatorscalars=squeeze(sum(acquireddata(:,(siacq(2)-(num_navs-1)):siacq(2),:,:,:,:,:),1));
            
            %                         td, etl,  ns,seg,array      
            acquireddata=acquireddata(:,1:pc.etl,:,:,:,:,:);
            navigatordata=zeros(size(acquireddata));
            segmentmap=navigatordata; %this will be filled with the indices
            for sl=1:pc.ns;
                for nsg=1:nsegs;
                    for rm=1:rem;
                        navigatordata(1:siacq(1),1:pc.etl,sl,nsg, rm)=ones(siacq(1),pc.etl,1,1,1)*navigatorscalars(1,1,sl,nsg,rm);
                        segmentmap(:,:,sl,nsg, rm)   = ones(siacq(1),pc.etl) *nsg;
                    end
                end
            end
            %put the phase dimensions next to each other
            acquireddata=permute(acquireddata, [1 2 4 3 5 6] );

            %stack the phase dimension
            si=[size(acquireddata) 1 1 1];
            acquireddata=reshape(acquireddata, [si(1) si(2)*si(3) si(4:end)]);
            
            segmentmap=permute(segmentmap, [1 2 4 3 5 6] );
            segmentmap=reshape(segmentmap, [si(1) si(2)*si(3) si(4:end)] );
            
            navigatordata=permute(navigatordata, [1 2 4 3 5 6] );
            navigatordata=reshape(navigatordata, [si(1) si(2)*si(3) si(4:end)]);
            
            navigatorphase=navigatordata./abs(navigatordata);
            
            if any(strcmp(varargin,'nav'));
                acquireddata=acquireddata./navigatorphase;
            end
                
            out.navigators=squeeze(navigatorscalars);
            out.segmentmap=squeeze(segmentmap);
            
            
        else
            %No navigator
            rem=numel(acquireddata)/si(1)/pc.ns/pc.nv;
            acquireddata=reshape(acquireddata,[si(1) pc.etl pc.ns pc.nv/pc.etl rem]);  %seqcon = nccnn
            
            %put the phase dimensions next to each other
            acquireddata=permute(acquireddata, [1 2 4 3 5 6] );
            %stack the phase dimension
            si=[size(acquireddata) 1 1 1];
            acquireddata=reshape(acquireddata, [si(1) si(2)*si(3) si(4:end)]);
        end
        
        
        %Now reorder the k space data
        if isfield(pc,'pelist');
            if pc.nv~=numel(pc.pelist);
                pelistflag=false;
            else
                pelistflag=true;
            end
        else
            pelistflag=false;
        end
        if ~pelistflag;
            pelistfromfile=(importdata([pvnmr 'tablib/' pc.petable], '\t',1));
            pc.pelist=(pelistfromfile.data)';
            pc.pelist=pc.pelist(:);
        else
            %display('FSE order in .pars.pelist');
        end
        
        T2weightflag=false;
        if T2weightflag;
            %undo T2weighting of the echoes
            Tweight=100;
            si=size(pelistfromfile.data);
            taxis=pc.te+(0:si(2)-1)*pc.esp;
            wtmap=(ones(si(1),1)*exp(taxis/Tweight))';
            wtlist=wtmap(:);
            wtlist=wtlist/mean(wtlist);
            dummy=ones(size(acquireddata));
            for ii=1:numel(wtlist);
                dummy(:,ii,:,:,:)=dummy(:,ii,:,:,:)*wtlist(ii);
            end
            acquireddata=acquireddata.*dummy;
        end
        
        acquireddata(:,pc.pelist+pc.nv/2,:,:,:,:)=acquireddata; 
        if exist('segmentmap','var');
            segmentmap(:,pc.pelist+pc.nv/2,:,:,:,:)=segmentmap;
        end
    case {'gemsll'}; %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% look locker
        acquireddata=reshape(acquireddata,[si(1) pc.etl pc.ns numel(pc.ti) pc.nv/pc.etl]);  %seqcon = nccnn
        %put the phase dimensions next to each other
        acquireddata=permute(acquireddata, [1 2 5 3 4]);
        %stack the phase dimension
        si=[size(acquireddata) 1 1 1];
        acquireddata=reshape(acquireddata, [si(1) si(2)*si(3) si(4:end)]);
        %Now reorder the k space data
        if isfield(pc,'pelist');
            if pc.nv~=numel(pc.pelist);
                pelistflag=false;
            else
                pelistflag=true;
            end
        else
            pelistflag=false;
        end
        if ~pelistflag;fsemsdwvc
            dummy=(importdata([pvnmr 'tablib/' pc.petable], '\t',1));
            pc.pelist=(dummy.data)';
            pc.pelist=pc.pelist(:);
        else
            %display('FSE order in .pars.pelist');
        end
        acquireddata(:,pc.pelist+pc.nv/2+1,:,:,:,:)=acquireddata;
        acquireddata=squeeze(acquireddata);
    case {'tagcine'; 'tagcinevc'};
        rem=numel(acquireddata)/si(1)/pc.ne/pc.nv;
        acquireddata=reshape(acquireddata,[si(1) pc.ne pc.nv rem 1 1]);
        acquireddata=permute(acquireddata, [1 3 2 4 5]);
    case {'ge3d'}
        acquireddata=squeeze(reshape(acquireddata,[pc.np/2, pc.ne, pc.nv, pc.nv2]));
        if ndims(acquireddata)>3; %multidim or multiecho acquisition
            dd=ndims(acquireddata);
            acquireddata=permute(acquireddata, [1 3:dd 2]);
        end
        acquisitiontype='3D';
    otherwise
end

%test: reverse phase domain data; result: don't do it
%si=size(acquireddata);
%acquireddata=acquireddata(:,si(2):-1:1,:,:,:);

%frequency shift if desired
%check if a frequency offset [,'freq', frequency] was handed down in varargin
if any(strcmp(varargin,'freq'));
	dii=find(strcmp(varargin,'freq'));
	if numel(varargin)>dii
		if isfloat(varargin{dii+1});
			freqoffset=varargin{dii+1};
		else
			freqoffset=0; %microseconds
		end
	end
	si=size(acquireddata);
	ntd=si(1);
	dwell=pc.at/ntd;
	freqoffsetmatrix = exp(1i*freqoffset*(1:ntd)')*ones([1 si(2)]);
	restd=prod(si)/(si(1)*si(2));
	acquireddata=reshape(acquireddata, [si(1) si(2) restd]);
	for jj=1:restd;
		acquireddata(:,:,jj)=acquireddata(:,:,jj).*freqoffsetmatrix;
	end
	acquireddata=reshape(acquireddata,si);
end

%generate the images, with zerofill if requested
si=[size(acquireddata) 1];
nimages=prod(si(3:end));
%Default: no zero filling
mrows=td;
ncols=pc.nv;

%forced zero fills to fixed number of pixels if requested *****************
if any(strcmp(varargin,'256'));
    %this will be used if there is additional iso or zf argument in
    %varargin
    mrows=256;
    ncols=256;
end
if any(strcmp(varargin,'384'));
    %this will be used if there is additional iso or zf argument in
    %varargin
    mrows=384;
    ncols=384;
end
if any(strcmp(varargin,'192'));
    %this will be used if there is additional iso or zf argument in
    %varargin
    mrows=192;
    ncols=192;
end
if any(strcmp(varargin,'512'));
    %this will be used if there is additional iso or zf argument in
    %varargin
    mrows=512;
    ncols=512;
end
if any(strcmp(varargin,'1024'));
    %this will be used if there is additional iso or zf argument in
    %varargin
    mrows=1024;
    ncols=1024;
end
%**************************************************************************

%zerofilling either by multiplier zf or zf2, or to generate isotropic pixels
if any(strcmp( 'zf',varargin)) || any(strcmp( 'zf2',varargin))  || any(strcmp( 'iso',varargin));  %zerofill called for
    
    %generate the images, with zerofill if requested
    si=[size(acquireddata) 1];
    imres(1)=pc.lro./si(1);  %cm/pixel  yaxis (readout axis)
    imres(2)=pc.lpe./si(2);  %cm/pixel  xaxis (phase encode axis)
    
    
    %1. the raw length in the time domain and pe direction is given by
    mrows=td;
    ncols=pc.nv;
    %make the pixels isotropic
    if any(strcmp( 'iso',varargin));
        %default iso, no filling factor but isotropic pixels
        fff=1;
        
        if imres(1)<imres(2);                   %highest resolution in the readout direction;
            ncols=2*round(pc.lpe/imres(1)/2);   %set to isotropic pixels, but no extra zerofill
            
            if any(strcmp(varargin,'256'));     %upsample to 256 requested
                mrows=256;
                ncols=2*round(pc.lpe/(pc.lro/256)/2);
            end
            if any(strcmp(varargin,'384'));     %upsample to 384 requested
                mrows=384;
                ncols=2*round(pc.lpe/(pc.lro/384)/2);
            end
            if any(strcmp(varargin,'192'));     %upsample to 384 requested
                mrows=192;
                ncols=2*round(pc.lpe/(pc.lro/192)/2);
            end
            if any(strcmp(varargin,'512'));     %upsample to 512 requested
                mrows=512;
                ncols=2*round(pc.lpe/(pc.lro/512)/2);
            end
            if any(strcmp(varargin,'1024'));    %upsample to 1024 requested
                mrows=1024;
                ncols=2*round(pc.lpe/(pc.lro/1024)/2);
            end
        else
            mrows=2*round(pc.lro/imres(2)/2);   %set to isotropic pixels, but no extra zerofill
            
            if any(strcmp(varargin,'256'));     %upsample to 512 requested
                ncols=256;
                mrows=2*round(pc.lro/(pc.lpe/256)/2);
            end
            if any(strcmp(varargin,'384'));     %upsample to 512 requested
                ncols=384;
                mrows=2*round(pc.lro/(pc.lpe/384)/2);
            end
            if any(strcmp(varargin,'192'));     %upsample to 512 requested
                ncols=192;
                mrows=2*round(pc.lro/(pc.lpe/192)/2);
            end
            if any(strcmp(varargin,'512'));     %upsample to 512 requested
                ncols=512;
                mrows=2*round(pc.lro/(pc.lpe/512)/2);
            end
            if any(strcmp(varargin,'1024'));    %upsample to 1024 requested
                ncols=1024;
                mrows=2*round(pc.lro/(pc.lpe/1024)/2);
            end
        end 
    end
    
    %zerofill factor 1.5 in each direction
    if any(strcmp( 'zf',varargin));
        fff=1.5;
    end
    %zerofill by factor 2 in each direction
    if any(strcmp( 'zf2',varargin));
        fff=2;
    end
    mrows=2*round(mrows*fff/2);
    ncols=2*round(ncols*fff/2);
end



if any(strcmp(varargin,'apod'));
    %apodization filter is requested
    
    %1. check if a numeric argument follows apod
    apodindex=find(strcmp(varargin,'apod'));
    if nargin==apodindex || ~isnumeric(varargin{apodindex+1}); %'apod' is last option or next option not numeric
        si=size(acquireddata);
        k2=si(1:2)/2;       %number of (ky, kx) /2
        kc=0.9;             %cutoff k
        w=1-kc;             %width of the apod roll off
        
        ky=[-k2(1):k2(1)-1]'./k2(1);
        kx=[-k2(2):k2(2)-1]./k2(2);
        kabs=sqrt((ky.^2)* ones(1,si(2)) + ones(si(1),1)*(kx.^2) );
        ktophat=kabs<kc;
        kring =kabs>kc+w;
        W=cos(pi*(kabs-kc)/(2*w)).^2;
        W(ktophat(:))=1;
        W(kring(:))=0;
    elseif nargin>apodindex && isnumeric(varargin{apodindex+1}) && numel(varargin{apodindex+1})==4;
        %selective set a patch in kspace to zero, useful for killing
        %stimulated echo signatures
        si=size(acquireddata);
        W=ones(si(1:2));
        zpl=varargin{apodindex+1};
        W(zpl(1):zpl(2),zpl(3):zpl(4))=0;
    elseif nargin>apodindex && isnumeric(varargin{apodindex+1}) && numel(varargin{apodindex+1})==2;
        %define a central oval in kspace and kill the rest
        si=size(acquireddata);
        k2=si(1:2)/2;                   %number of (ky, kx) /2
        kcut=varargin{apodindex+1};     %cutoff fraction ky kx
        w=0.1;                          %width of the apod roll off
        
        ky=[-k2(1):k2(1)-1]'./k2(1)/kcut(1);    %normalized ky
        kx=[-k2(2):k2(2)-1]./k2(2)/kcut(2);     %normalized kx
        %kabs=sqrt((ky.^2)* ones(1,si(2)) + ones(si(1),1)*(kx.^2) );
        ktophat=abs(ones(si(1),1)*kx)<1 & abs(ky*ones(1,si(2)))<1;
        W=zeros(si(1:2));
        W(ktophat(:))=1;
          
    end
    
    for jj=1:nimages;
        acquireddata(:,:,jj)=acquireddata(:,:,jj).*W;
    end
end

%initialize the phase warp matrix to account for an off-center echo
YY=exp(1i*(-mrows/2:mrows/2-1)'*ones(1,ncols)/mrows*kshift);

%initialize the picture array and Fourier transform with zerofilling;
siacq=size(acquireddata);
ioff=mrows/2-siacq(1)/2;
joff=ncols/2-siacq(2)/2;

if strcmp(acquisitiontype,'2D');
    pic=zeros([mrows ncols si(3:end)]);
    for jj=1:nimages;
        paddedslice=zeros(mrows,ncols);
        paddedslice(ioff+(1:siacq(1)), joff+(1:siacq(2)))=acquireddata(:,:,jj);
        %experimental: virtual reduction of bandwidth by a factor 2
        if any(strcmp('BW',varargin));
            windowsize=2;
            paddedslice=filter(ones(1,windowsize)/windowsize,1,paddedslice);
        end
        pic(:,:,jj)=fftshift(fft2(fftshift(conj(paddedslice))));
        if kshift~=0;
            pic(:,:,jj)=pic(:,:,jj).*YY;
        end
    end
    
    %reshape the images into the original size
    si=[size(acquireddata) 1 1 1];
    sipic=size(pic);
    pic=reshape(pic, [sipic(1:2) si(3:end)]);
    
elseif strcmp(acquisitiontype,'3D');
    siacq=[size(acquireddata) 1 1 1];
    
    %zerofill in third dimansion if 'zf3' passed down%%%
    if any(strcmp(varargin, 'zf3'));
        nz=1.5*siacq(3);
        nzoff=round(siacq(3)/2);
        pic=zeros([mrows ncols 1.5*siacq(3) siacq(4:end)]);
        display('Zero filling 3rd dimension.');
    else
        nz=siacq(3);
        nzoff=0;
        pic=zeros([mrows ncols siacq(3:end)]);
    end
    
    for jj=1:siacq(4);
        paddedblock=zeros(mrows,ncols,nz);
        paddedblock(ioff+(1:siacq(1)), joff+(1:siacq(2)),nzoff+(1:siacq(3)))=squeeze(acquireddata(:,:,:,jj));
        pic(:,:,:,jj)=fftshift(fftn(fftshift(conj(paddedblock))));
    end
    
    %reshape the images into the original size%%%%%%%%%%%
    si=[size(acquireddata) 1 1 1];
    sipic=size(pic);
    pic=reshape(pic, [sipic(1:2) nz si(4:end)]);
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
end

%reorder the slices to be ascending
[sliceposition,orderindex]=sort(pc.pss);
if any(orderindex ~= (1:numel(orderindex)));
    display('varianms.m ordered interleaved slices...');
    display('varianms.m updated the slice positions in out.pars.pss ...');
    display('varianms.m ordered interleaved k-space slices ...');
    pic=pic(:,:,orderindex,:,:,:);
    pc.pss=pc.pss(orderindex);
    acquireddata=acquireddata(:,:,orderindex,:,:,:);
    if exist('segmentmap','var');
        segmentmap=segmentmap(:,:,orderindex,:,:,:);
    end
end


%normalize the pixel intensity to the voxel size if requested
if any(strcmp(varargin,'norm'));
    display('normalized images by slice thickness');
    pic=pic/pc.thk;
end

out.image=pic;
out.pars=pc;
out.kspace=acquireddata;  %end reconfids
if navigatorflag;
    out.segmentmap=segmentmap;
end

function [acquireddata,header]=readit(filename)
%open the fid
file_id=fopen(filename, 'r', 'b');          %always big endian format, even for Linux

%Start reading the file header to get the first 6 elements
[hdr, count] = fread(file_id, 6, 'int32'); %count is number of

header.nblocks = hdr(1);        %data blocks in a file (second dimension, if arrayed acquisition)
header.ntraces = hdr(2);        %number of traces
header.complex_td= hdr(3)/2;    %real and imaginary points (first dimension = time);
ebytes = hdr(4);                % 4 bytes per point	(double precision real, double precision imag)
tbytes = hdr(5);                %np*ebytes
bbytes = hdr(6);                %ntraces*tbytes+nhead*sizeof(datablockhead=28bytes)-total

%Read 2 16bit integers to see the data type and the status of the binary
[data_holder, count] = fread(file_id, 2, 'int16');
vers_file_id = data_holder(1);
status = data_holder(2);            %status determines whether data are store as 16 or 32 bit integers or floats
BinStat = fliplr(dec2bin(status));  %determine the binary format from the status info
%xx00xxxx means 16 bit data
%xx10xxxx means 32 bit data
%else means float

[data_holder, count] = fread(file_id, 1, 'int32');
nhead = data_holder(1);

data_holder = zeros(hdr(3)*hdr(2), 1);

%INT16 data type **********************************************************
if ((BinStat(3) == '0') & (BinStat(4) == '0'))
    for nblocks_count=1:header.nblocks
        for nhead_count=1:nhead
            fread(file_id, 14, 'int16');			%read in the block headers (28 bytes)
        end
        [b, count] = fread(file_id, hdr(2)*hdr(3), 'int16');   	%read in the actual data (ntraces*np)
        %put the data in the vector
        data_holder( ((nblocks_count-1)*hdr(2)*hdr(3)+1) : nblocks_count*hdr(2)*hdr(3) ) = b;
    end
    %INT32 data type **********************************************************
elseif ((BinStat(3) == '1') & (BinStat(4) == '0'))
    for nblocks_count=1:header.nblocks
        for nhead_count=1:nhead
            [d,count]=fread(file_id, 14, 'int16');			%read in the block headers (28 bytes)
            bhead=d;
        end
        [b, count] = fread(file_id, hdr(2)*hdr(3), 'int32');   	%read in the actual data (ntraces*np)
        %put the data in the vector
        data_holder( ((nblocks_count-1)*hdr(2)*hdr(3)+1) : nblocks_counthdr(2)*hdr(3) ) = b;
    end
    %FLOAT data type **********************************************************
else
    for nblocks_count=1:header.nblocks
        for nhead_count=1:nhead
            fread(file_id, 14, 'int16');			%read in the block headers (28 bytes)
        end
        [b, count] = fread(file_id, hdr(2)*hdr(3), 'float');   	%read in the actual data (ntraces*np)
        %put the data in the vector
        data_holder( ((nblocks_count-1)*hdr(2)*hdr(3)+1) : nblocks_count*hdr(2)*hdr(3) ) = b;
    end
end

%real imaginary pairs, create complex array
acquireddata=complex(data_holder(1:2:end),data_holder(2:2:end));
acquireddata=reshape(acquireddata,[header.complex_td numel(acquireddata)/header.complex_td]);


function [inputtype, fileidstring]=check_img_or_fid(fileidstring)
%check if the filename is image or fid, directory or file
if isreal(fileidstring); fileidstring=num2str(fileidstring); end
[parent, fnamin, ext]=fileparts(fileidstring); %#ok<*ASGLU>
switch ext;
    case '.img';
        inputtype={'image'; 'directory'};
    case '.fdf';
        inputtype={'image'; 'file'};
    case '.fid'
        inputtype={'timedomain'; 'directory'};
    case ''
        if strcmp(fnamin, 'fid');
            inputtype={'timedomain'; 'file'};
        else
            if (numel(fnamin)==4 && ~isempty(str2num(fnamin)));
                d=dir;
                istime=false(numel(d),1);
                isimg=false(numel(d),1);
                for jj=1:numel(d);
                    istime(jj)=~isempty(strfind(d(jj).name,fnamin));
                    isimg(jj)=~isempty(strfind(d(jj).name,'.img'));
                end
                isfid=~isimg;
                index=find(istime&isfid); inputtype={'timedomain'; 'directory'};
                %index=find(istime&isimg); inputtype={'image'; 'directory'};
                
                if ~isempty(index);
                fileidstring=d(index).name; %#ok<FNDSB>
                else
                    err=MException('directory_not_found:wrong_time_stamp',['No directories with time stamp ' fnamin]);
                    throw(err);
                end
                
            end
        end
end

function h=slice_surveyplot(in)
pic=in{1};
if any(strcmp(in,'col'));
    cmap=jet(128);
else
    cmap=gray(128);
end
%auto choose the layout
si=size(pic);
maxamp=max(pic(:));
meanamp=mean(abs(pic(:)));
switch ndims(pic);
    case 2
        nfig=1;
        nx=1;
        ny=1;
        nimperfigure=1;
    case 3;						%stack of slices or time stamped single slice
        nfig=1;
        nx=ceil(sqrt(si(3)));
        ny=ceil(si(3)/nx);
        nimperfigure=si(3);	%number of images per figure
    case 4
        nfig=1;
        nx=si(3);
        ny=si(4);
        nimperfigure=nx*ny;
    case 5
        nfig=si(5);
        nx=si(3);
        ny=si(4);
        nimperfigure=nx*ny;
end

%plot it
for ff=1:nfig;
    %h(ff)=figure('Name', pc.comment,'NumberTitle', 'off');
    h(ff)=figure;
    colormap(cmap);
    for ii=1:nimperfigure;
        tsubplot(ny,nx,ii);
        imagesc(abs(pic(:,:,ii)));
        shading flat;
        axis image
        set(gca,'clim',[0 3*meanamp],'TickDir', 'in','Xticklabel','','YTicklabel','');
        simage=size(pic);
        ht=textn(0.9,0.1, num2str(ii+(ff-1)*nimperfigure));
        set(ht, 'color', [0 0.8 0]);
    end
end

function out=readfdf(filename)
%read a varian image, return it in a matrix, loosely 
%based on ReadVarFDF by Lana Kaiser, Varian
if ~exist(filename, 'file')==2;
    display(['Image file ' filename ' does not exist!']);
    return;
else
    [fid,msg]=fopen(filename,'r');
end

%1. read text lines and define a pars structure
parscanflag=true;
jj=1;
rdln=(fgetl(fid)); %read the first line
while parscanflag;
    jj=jj+1;
    
    %read the line
    rdln=(fgetl(fid));
    
    %remove '*' and '[]' and '"' from the line
    rdln=strrep(rdln,'*', '');
    rdln=strrep(rdln,'[]','');
    rdln=strrep(rdln,'"', '''');
    
    [token,remain]=strtok(rdln);
    remain=strrep(remain,' ','');
    %display(['pars.' remain]);
    eval(['pars.' remain]);
    
    %display(strtok(rdln));
    if strfind(rdln, 'checksum');
        %display(['Last fdf header line at line ' num2str(jj)]);
        parscanflag=false;
    end
    
    if jj>50; parscanflag=false; end
end

%2D or 3D data?
dimensionality=pars.rank;

%bigendian or little endian?
if pars.bigendian==0;
    endian='l';
else
    endian='b';
end

%define the dimensions,read the data
if dimensionality ==2;
    dim(1)=pars.matrix{1};
    dim(2)=pars.matrix{2};
    status = fseek(fid, -dim(1)*dim(2)*pars.bits/8, 'eof');
    image=fread(fid,[dim(1), dim(2)],'float32',endian);
elseif dimensionality==3;
    dim(1)=pars.matrix{1};
    dim(2)=pars.matrix{2};
    dim(3)=pars.matrix{3};
    status = fseek(fid, -dim(1)*dim(2)*dim(3)*pars.bits/8, 'eof');
    image=fread(fid,[dim(1)*dim(2), dim(3)],'float32',endian);
    image=reshape(image,dim);
end

%permute the image data so that it is consistent with direct reconstruction
indvec=[1:ndims(image)];
indvec(1)=2;
indvec(2)=1;
%exchange x and y axes
image=permute(image,indvec); 
%invert axis directions
si=(size(image));
image=image(si(1):-1:1,si(2):-1:1,:,:,:);
out.image=image;
out.pars=pars;

%Now determine the size of the data, locate the beginning of the binary
%data, read it in, redimension
fclose(fid);
