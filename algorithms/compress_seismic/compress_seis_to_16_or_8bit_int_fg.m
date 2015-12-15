function [ trim_data_filt, scalars_out, zlocs_out, tpgrad_orig, scalepeak,  orig_nsamples, percenterr ] = compress_seis_to_16_or_8bit_int_fg( trim_data, morecompress, envlplot )
%
%% ------------------ Disclaimer  ------------------
%
% BG Group plc or any of its respective subsidiaries, affiliates and
% associated companies (or by any of their respective officers, employees
% or agents) makes no representation or warranty, express or implied, in
% respect to the quality, accuracy or usefulness of this repository. The code
% is this repository is supplied with the explicit understanding and
% agreement of recipient that any action taken or expenditure made by
% recipient based on its examination, evaluation, interpretation or use is
% at its own risk and responsibility.
%
% No representation or warranty, express or implied, is or will be made in
% relation to the accuracy or completeness of the information in this
% repository and no responsibility or liability is or will be accepted by
% BG Group plc or any of its respective subsidiaries, affiliates and
% associated companies (or by any of their respective officers, employees
% or agents) in relation to it.
% ------------------ License  ------------------
% GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007
% github
% https://github.com/AnalysePrestackSeismic/
% ------------------ FUNCTION DEFINITION ---------------------------------
%
%
% Defination: compress_seis_to_16_or_8bit_int compress the seismic into 16 bit
% integer or 8 bit with scalars to provide good recovery whilst still looking like
% seismic, so the result cane be viewed at 16 bit int, 8 bit int(like a very short agc)
% or uncompress to 32 bit ieee float
% morecompress values
% 1 = first envelope for data velaue  - do not use very inefficent compression
% 2 = second envelope, envelope of first envelope - 8 bit integer ~ 3 times dependant on trace length
% 3 = third envelope, ie envelope of 2nd envelope - 16 bit integer ~ 1.9 times compression
%
% Input:
% trim_data = a 2 dimensional array, rows are samples , columns are traces
% morecompress = 2 = 8 bit, 3 = 16 bit output
% envlplot = only set to 3 will produce plots all other plots commented out
%
% Output:
% trim_data_filt = the output 2 dimensional array of int16 or int 8 numbers
% scalars_out = 3 d array of the scalars, size of 2; number of samples; number of traces
%       1st dimension is the mid points (e.g. scalars_out(1,:,:) , second dimension is the
%       lower envelope e.g. scalars_out(2,:,:), values are singles
% zlocs_out = the z locations out 2d array, (locations, traces) stored as
%       unit16
% tpgrad_orig = number of scalar points
% scalepeak = peakvalue scaled to
% orig_nsamples = orginal number of samples in the trace
%
%
% to save space the code only write the sample numnbers as uint16 so means
% that the trace length limit is 65536 samples, which is 131 seconds at 2ms
% sampling, could just change to uint32 to move to longer records, but that
% would also need a review of the number of scalars
%
% Authors: Charles Jones 2015
%%
%
% read the command line variables
morecompress = str2double(morecompress);
envlplot = str2double(envlplot);
% work out input dimensions

%trim_data = reshape(trim_data,[],floor(size(trim_data,2)/50));
no_of_traces = size(trim_data,2);
intrlen = size(trim_data,1);
intrlen_orig = intrlen;
orig_nsamples = uint16(intrlen);
percenterr = zeros(no_of_traces,1,'single');
%
%outplot = 0;
firstpos = single(0);
endpos = single(0);
firstneg = single(0);
endneg = single(0);
%finaldroptri = 0.000001;
finaldroptri = 0.000001;
%nanperwhtnoise  = 0.02;

if morecompress == 1
    tpgrad_orig = floor(intrlen/10);  % max number of scalars to store
    if tpgrad_orig < 55
        tpgrad_orig = 55;
    end
    extrapoints = floor(intrlen/200); % max number of extra pointas to hold to take care of points missed in derivative envelope
    if extrapoints < 8
        extrapoints = 8;
    end
    nanperwhtnoise  = 0.01;  % % to add to avoid cliping
    %perwhtnoise = 0.3;
    scalepeak = double(100);   % the max value to scale to
    smalldrop = 0.000000001;
elseif morecompress == 2
    tpgrad_orig = floor(intrlen/20);   % max number of scalars to store
    if tpgrad_orig < 55
        tpgrad_orig = 55;
    end
    extrapoints = floor(intrlen/350); % max number of extra pointas to hold to take care of points missed in derivative envelope
    if extrapoints < 6
        extrapoints = 6;
    end
    nanperwhtnoise  = 0.03;  % % to add to avoid cliping
    %perwhtnoise = 0.06;
    scalepeak = double(110); % the max value to scale to
    smalldrop = 0.0000000000000001;
else
    tpgrad_orig = floor(intrlen/50);   % max number of scalars to store
    if tpgrad_orig < 20
        tpgrad_orig = 20;
    end
    extrapoints = floor(intrlen/500); % max number of extra pointas to hold to take care of points missed in derivative envelope
    if extrapoints < 3
        extrapoints = 3;
    end
    nanperwhtnoise  = 0.05;  % % to add to avoid cliping
    %perwhtnoise = 0.01;
    scalepeak = double(28000); % the max value to scale to
    smalldrop = 0.000000001;
end

%to make the envelope tend to the value +/- 2000
%   Detailed explanation goes here
%%
midpoints_red_t = [ones(tpgrad_orig,1,'single') zeros(tpgrad_orig,1,'single')];
midpoints_red_torg = midpoints_red_t;
points_all_blk = ones(tpgrad_orig,1,'single');
points_all_blk_org = points_all_blk;

%
%filt_smo =  ones(1,3)/3;
%filttraces = [1 2 2 3 3 3 2 2 1]/19;
%trim_data_filt = trim_data;


if morecompress < 3
    trim_data_filt = zeros(intrlen,no_of_traces,'int8');
else
    trim_data_filt = zeros(intrlen,no_of_traces,'int16');
end
diffout = zeros(intrlen,1,'single');
midblank = zeros(intrlen,1,'double');
scaleval_res = ones(intrlen,1,'double');
res_midpoints = midblank;
scaleval = midblank;
%midpointslogic = logical(diffout);
midpoints = midblank;
itpslocs = single(1:intrlen)';
itpslocstest = itpslocs;
origcount = itpslocs;
origcountconst = origcount;
tmpupper = itpslocstest;
blankone = single(1);
blanklogic = true;
blankdbl = 0;
xgrad = blankone;
ygrad = blankone;
pointlogic = blanklogic;
top15grads = blankone;
points_all = blankone;
itpslocsin = blankone;
itpsval = blankone;
mid_lens = blankone;
midpoints_red  = blankone;
midpoints_red_grad  = blankone;
mitpslocsin  = blankone;
mitpsval = blankone;
mitpsval_red = blankone;
%
scalars_out = ones(2,tpgrad_orig,no_of_traces,'single');
zlocs_out = ones(tpgrad_orig,no_of_traces,'uint16');
tpgrad_origsm = tpgrad_orig - extrapoints;
nanperwhtnoiseb = 0.0001;
addback = 2;
clipshift = 1.5;
%
%
%
for ckk = 1:no_of_traces
    %for ckk = 1227:1227
    %fprintf('trace %d \n',ckk);
    % find if the trace has zreros on the start or end and then remove
    % those as no need to compress them with this scheme
    if sum(trim_data(:,ckk)) ~= 0;
        tracezeros = (trim_data(:,ckk) ~= 0).*origcountconst;
        tracezerosout = tracezeros(tracezeros > 0);
        lastreal = tracezerosout(end);
        firstreal = tracezerosout(1);
        nooffzeros = firstreal - 1;
        nooflzeros = intrlen_orig - lastreal;
        noofrealsamps = (lastreal-firstreal)+1;
        trim_data(1:noofrealsamps,ckk) = trim_data(firstreal:lastreal,ckk);
        
        %set the other items to work for the reduced trace length
        intrlen = noofrealsamps;
        scaleval = midblank(1:noofrealsamps);
        midpoints = midblank(1:noofrealsamps);
        itpslocs = origcountconst(1:noofrealsamps);
        itpslocstest = origcountconst(1:noofrealsamps);
        origcount = origcountconst(1:noofrealsamps);
        %tmpupper = origcount(1:noofrealsamps);
        
        % reset some variables
        midpoints_red_t = midpoints_red_torg;
        points_all_blk = points_all_blk_org;
        tpgrad = tpgrad_origsm;
        
        % find the variance of the input data
        %varmeas = var(trim_data(:,ckk));
        %fprintf('%-10.8f variance\n',varmeas);
        %trim_data(:,ckk) =  conv(trim_data(:,ckk),filttraces,'same');
        %     if envlplot == 1
        %         figure(2); plot(trim_data(:,ckk));
        %         hold on
        %     end
        % find the first and second derivatives of the max
        max_1st_deriv = diff(trim_data(1:noofrealsamps,ckk));
        max_2nd_deriv = diff(trim_data(1:noofrealsamps,ckk),2);
        
        % apply a signum filter to get samples at zero crossings and make only 1
        % and 0's
        sign_1_deriv = sign(max_1st_deriv);
        sign_1_deriv(sign_1_deriv == 0) = 1;
        
        % find the point where sign of 1st deriv changes
        diffsign = diff(sign_1_deriv);
        mdiffsign = diffsign;
        
        % set the point to zero where second derivative is positive and pad, this
        % finds the peaks in the max dataset
        diffsign(sign(max_2nd_deriv) > 0) = 0;
        diffsign = [1;diffsign];
        
        % set the point to zero where second derivative is positive and pad, this
        % finds the mins in the max dataset
        mdiffsign(sign(max_2nd_deriv) <= 0) = 0;
        mdiffsign = [1;mdiffsign];
        orig_mdiffsign = mdiffsign;
        %use the peaks logical to get the values and indexes to then interpolate to
        %make and envelope which includes the signal, but preserves the wiggles in
        %the dataset
        % upper points
        itpsval = trim_data((diffsign < 0),ckk);
        %itpsval = trim_data([(diffsign < 0);false(nooflzeros,1)],ckk);
        itpslocsin = itpslocs(diffsign < 0);
        % lower points
        mitpsval = trim_data((mdiffsign > 0),ckk);
        %mitpsval = trim_data([false(nooffzeros,1);(mdiffsign > 0);false(nooflzeros,1)],ckk);
        mitpslocsin = itpslocs(mdiffsign > 0);
        
        %test to see if the envelope does not contain the start or end points
        % end of trace check
        if itpslocsin(end) > mitpslocsin(end)
            if itpslocsin(end) ~= intrlen
                itpslocsin = [itpslocsin; intrlen];
                %check to see if the real data extand outside of the last envelope
                %point
                if trim_data(lastreal,ckk) > itpsval(end)
                    itpsval = [itpsval; trim_data(lastreal,ckk)];
                else
                    itpsval = [itpsval; itpsval(end)];
                end
            end
            mitpslocsin = [mitpslocsin; intrlen];
            %check to see if the real data extand outside of the last envelope
            %point
            if trim_data(lastreal,ckk) < mitpsval(end)
                mitpsval = [mitpsval; trim_data(lastreal,ckk)];
            else
                mitpsval = [mitpsval; mitpsval(end)];
            end
        else
            %         if mitpslocsin(end) ~= intrlen
            %             mitpslocsin = [mitpslocsin; intrlen];
            %             mitpsval = [mitpsval; mitpsval(end)];
            %         end
            %         itpslocsin = [itpslocsin; intrlen];
            %         %itpsval = [itpsval; trim_data(lastreal,ckk)];
            %         itpsval = [itpsval; itpsval(end)];
            
            if mitpslocsin(end) ~= intrlen
                mitpslocsin = [mitpslocsin; intrlen];
                %check to see if the real data extand outside of the last envelope
                %point
                if trim_data(lastreal,ckk) < mitpsval(end)
                    mitpsval = [mitpsval; trim_data(lastreal,ckk)];
                else
                    mitpsval = [mitpsval; mitpsval(end)];
                end
            end
            itpslocsin = [itpslocsin; intrlen];
            %check to see if the real data extand outside of the last envelope
            %point
            if trim_data(lastreal,ckk) > itpsval(end)
                itpsval = [itpsval; trim_data(lastreal,ckk)];
            else
                itpsval = [itpsval; itpsval(end)];
            end
        end
        
        %start of trace check
        if itpslocsin(1) < mitpslocsin(1)
            if itpslocsin(1) ~= 1
                itpslocsin = [1; itpslocsin];
                itpsval = [itpsval(1); itpsval];
            end
            mitpslocsin = [1; mitpslocsin];
            %         mitpsval = [trim_data(1,ckk); mitpsval];
            %         if mitpsval(1) ==  itpsval(1)
            %             itpsval(1) = itpsval(2);
            %         end
            if trim_data(lastreal,ckk) < mitpsval(1)
                mitpsval = [trim_data(1,ckk); mitpsval];
            else
                mitpsval = [mitpsval(1); mitpsval];
            end
            if mitpsval(1) ==  itpsval(1)
                itpsval(1) = itpsval(2);
            end
        else
            if mitpslocsin(1) ~= 1
                mitpslocsin = [1; mitpslocsin];
                mitpsval = [mitpsval(1); mitpsval];
            end
            itpslocsin = [1; itpslocsin];
            if trim_data(lastreal,ckk) > itpsval(1)
                itpsval = [trim_data(1,ckk); itpsval];
            else
                itpsval = [itpsval(1); itpsval];
            end
            if mitpsval(1) ==  itpsval(1)
                mitpsval(1) = mitpsval(2);
            end
        end
        
        %store orginal points to compare at the end
        origuprloc = itpslocsin;
        origuprval = itpsval;
        origlowloc = mitpslocsin;
        origlowval = mitpsval;
        
        if envlplot == 3
            figure(44);
            plot(origlowloc,origlowval,'-or');
            hold on;
            plot(origuprloc,origuprval,'-og');
            plot(trim_data(1:noofrealsamps,ckk),'-k');
        end
        
        % make sure the start and end do not get lost
        firstpos = itpsval(1);
        endpos = itpsval(end);
        firstneg = mitpsval(1);
        endneg = mitpsval(end);
        
        % interpolate to make the envelope only using fast linear interp
        %posenv = double(interp1q(itpslocsin,itpsval,origcount));
        posenv = double(makefastinterp1(double(itpslocsin),double(itpsval),double(origcount)));
        
        %     if envlplot == 1
        %         plot(posenv,'-r')
        %     end
        %       if (morecompress > 1)
        %==========================================================================
        % calc the envelope of the envelope
        max_1st_deriv = diff(posenv);
        max_2nd_deriv = diff(posenv,2);
        sign_1_deriv = sign(max_1st_deriv);
        sign_1_deriv(sign_1_deriv == 0) = 1;
        diffsign = diff(sign_1_deriv);
        mdiffsign = diffsign;
        diffsign(sign(max_2nd_deriv) > 0) = 0;
        diffsign = [1;diffsign];
        mdiffsign(sign(max_2nd_deriv) <= 0) = 0;
        mdiffsign = [1;mdiffsign];
        itpsval = posenv(diffsign < 0);
        itpslocsin = itpslocs(diffsign < 0);
        % make sure the start and end do not get lost
        if itpslocsin(end) ~= intrlen
            itpslocsin = [itpslocsin; intrlen];
            itpsval = [itpsval; endpos];
        end
        if itpslocsin(1) ~= 1
            itpslocsin = [1; itpslocsin];
            itpsval = [firstpos; itpsval];
        end
        
        % add small white noise to avoid division errors/mess
        %itpsval = itpsval + (trimmean(itpsval,10)*0.001);
        % interpolate to make the envelope only using fast linear interp
        %posenv = double(interp1q(itpslocsin,itpsval,origcount));
        posenv = double(makefastinterp1(double(itpslocsin),double(itpsval),double(origcount)));
        %==========================================================================
        %test to see if any points have been chopped off in the envelope
        newposvals =  posenv(origuprloc);
        tmpupper = origcount;
        tmpupper(itpslocsin) = itpsval;
        tmpupper(origuprloc(newposvals < origuprval)) = origuprval(newposvals < origuprval);
        itpslocsin = itpslocstest(tmpupper ~= itpslocstest);
        itpsval = tmpupper(tmpupper ~= itpslocstest);
        %posenv = double(interp1q(itpslocsin,itpsval,origcount));
        posenv = double(makefastinterp1(double(itpslocsin),double(itpsval),double(origcount)));
        %==========================================================================
        
        
        
        %             figure(995); plot(itpslocsin,itpsval,'-ob'); hold on
        %             %plot(origuprloc,newposvals,'-ob')
        %             plot(posenv,'-c')
        %             %plot(origlowloc,origlowval,'-or')
        %             %plot(mitpslocsin,mitpsval,'-or')
        %             plot(origuprloc,origuprval,'-og')
        %             plot(trim_data(1:noofrealsamps,ckk),'-k')
        %
        %         finallocs_uppertmp = (itpslocsin -[0;itpslocsin(1:(end-1))]).*abs(itpsval -[0;itpsval(1:(end-1))]) + (abs(([itpslocsin(2:end);0]-itpslocsin)).*abs(itpsval -[itpsval(2:(end));0]));
        %         %finallocs_upper = ((itpsval.*(abs(itpsval -[0;itpsval(1:(end-1))]) + abs(itpsval -[itpsval(2:(end));0])))./itpsval) > smalldrop;
        %         finallocs_upper =  finallocs_uppertmp > (mean(finallocs_uppertmp) * 0.000001);
        %         finallocs_upper(1:2) = 1;
        %         finallocs_upper(end) = 1;
        %         itpslocsin = itpslocsin(finallocs_upper);
        %         itpsval = itpsval(finallocs_upper);
        %
        %         plot(itpslocsin,itpsval,'-or')
        
        %         if envlplot == 1
        %             plot(posenv,'-g')
        
        %         end
        %==========================================================================
        %        end
        if (morecompress > 2)
            %==========================================================================
            % calc the envelope of the envelope of the envelope
            max_1st_deriv = diff(posenv);
            max_2nd_deriv = diff(posenv,2);
            sign_1_deriv = sign(max_1st_deriv);
            sign_1_deriv(sign_1_deriv == 0) = 1;
            diffsign = diff(sign_1_deriv);
            mdiffsign = diffsign;
            diffsign(sign(max_2nd_deriv) > 0) = 0;
            diffsign = [1;diffsign];
            mdiffsign(sign(max_2nd_deriv) <= 0) = 0;
            mdiffsign = [1;mdiffsign];
            itpsval = posenv(diffsign < 0);
            itpslocsin = itpslocs(diffsign < 0);
            
            % make sure the start and end do not get lost
            if itpslocsin(end) ~= intrlen
                itpslocsin = [itpslocsin; intrlen];
                itpsval = [itpsval; endpos];
            end
            if itpslocsin(1) ~= 1
                itpslocsin = [1; itpslocsin];
                itpsval = [firstpos; itpsval];
            end
            
            %posenv = double(interp1q(itpslocsin,itpsval,origcount));
            posenv = double(makefastinterp1(double(itpslocsin),double(itpsval),double(origcount)));
            %==========================================================================
            %test to see if any points have been chopped off in the envelope
            newposvals =  posenv(origuprloc);
            tmpupper = origcount;
            tmpupper(itpslocsin) = itpsval;
            tmpupper(origuprloc(newposvals < origuprval)) = origuprval(newposvals < origuprval);
            itpslocsin = itpslocstest(tmpupper ~= itpslocstest);
            itpsval = tmpupper(tmpupper ~= itpslocstest);
            
            %==========================================================================
            
            
            %==========================================================================
        end
        
        %         finallocs_upper = ((itpsval.*(abs(itpsval -[0;itpsval(1:(end-1))]) + abs(itpsval -[itpsval(2:(end));0])))./itpsval) > smalldrop;
        %         finallocs_upper(1:2) = 1;
        %         finallocs_upper(end) = 1;
        %         itpslocsin = itpslocsin(finallocs_upper);
        %         itpsval = itpsval(finallocs_upper);
        
        
        % add small white noise to avoid division errors/mess
        %itpsval = itpsval.*nanperwhtnoise;
        itpsval = itpsval + abs(itpsval.*nanperwhtnoise);
        
        % interpolate to make the envelope only using fast linear interp
        %posenv = double(interp1q(itpslocsin,itpsval,origcount));
        posenv = double(makefastinterp1(double(itpslocsin),double(itpsval),double(origcount)));
        %mposenv = double(makefastinterp1(double(mitpslocsin),double(mitpsval),double(origcount)));
        %     if envlplot == 1
        %         plot(posenv,'-m')
        %     end
        
        
        %==========================================================================
        %use the mins logical to get the values and indexes to then interpolate to
        %make and envelope which includes the signal, but preserves the wiggles in
        %the dataset
        
        % interpolate to make the min envelope only using fast linear interp
        %mposenv = double(interp1q(mitpslocsin,mitpsval,origcount));
        mposenv = double(makefastinterp1(double(mitpslocsin),double(mitpsval),double(origcount)));
        %     if envlplot == 1
        %         plot(mposenv,'-r')
        %     end
        %        if (morecompress > 1)
        %==========================================================================
        % calc the envelope of the envelope
        max_1st_deriv = diff(mposenv);
        max_2nd_deriv = diff(mposenv,2);
        sign_1_deriv = sign(max_1st_deriv);
        sign_1_deriv(sign_1_deriv == 0) = 1;
        diffsign = diff(sign_1_deriv);
        mdiffsign = diffsign;
        diffsign(sign(max_2nd_deriv) > 0) = 0;
        diffsign = [1;diffsign];
        mdiffsign(sign(max_2nd_deriv) <= 0) = 0;
        mdiffsign = [1;mdiffsign];
        mitpsval = mposenv(mdiffsign > 0);
        mitpslocsin = itpslocs(mdiffsign > 0);
        % add small white noise to avoid division errors/mess
        %mitpsval = mitpsval + (trimmean(mitpsval,10)*0.001);
        % interpolate to make the envelope only using fast linear interp
        
        % make sure the start and end do not get lost
        if mitpslocsin(end) ~= intrlen
            mitpslocsin = [mitpslocsin; intrlen];
            mitpsval = [mitpsval; endneg];
        end
        if mitpslocsin(1) ~= 1
            mitpslocsin = [1; mitpslocsin];
            mitpsval = [firstneg; mitpsval];
        end
        
        %mposenv = double(interp1q(mitpslocsin,mitpsval,origcount));
        mposenv = double(makefastinterp1(double(mitpslocsin),double(mitpsval),double(origcount)));
        %==========================================================================
        %test to see if any points have been chopped off in the envelope
        newposvals =  mposenv(origlowloc);
        tmpupper = origcount;
        tmpupper(mitpslocsin) = mitpsval;
        tmpupper(origlowloc(newposvals > origlowval)) = origlowval(newposvals > origlowval);
        mitpslocsin = itpslocstest(tmpupper ~= itpslocstest);
        mitpsval = tmpupper(tmpupper ~= itpslocstest);
        %mposenv = double(interp1q(mitpslocsin,mitpsval,origcount));
        mposenv = double(makefastinterp1(double(mitpslocsin),double(mitpsval),double(origcount)));
        %==========================================================================
        
        %         if envlplot == 1
        %             plot(mposenv,'-g')
        %         end
        %        end
        %==========================================================================
        if (morecompress > 2)
            % calc the envelope of the envelope of the envelope
            max_1st_deriv = diff(mposenv);
            max_2nd_deriv = diff(mposenv,2);
            sign_1_deriv = sign(max_1st_deriv);
            sign_1_deriv(sign_1_deriv == 0) = 1;
            diffsign = diff(sign_1_deriv);
            mdiffsign = diffsign;
            diffsign(sign(max_2nd_deriv) > 0) = 0;
            diffsign = [1;diffsign];
            mdiffsign(sign(max_2nd_deriv) <= 0) = 0;
            mdiffsign = [1;mdiffsign];
            mitpsval = mposenv(mdiffsign > 0);
            mitpslocsin = itpslocs(mdiffsign > 0);
            % make sure the start and end do not get lost
            if mitpslocsin(end) ~= intrlen
                mitpslocsin = [mitpslocsin; intrlen];
                mitpsval = [mitpsval; endneg];
            end
            if mitpslocsin(1) ~= 1
                mitpslocsin = [1; mitpslocsin];
                mitpsval = [firstneg; mitpsval];
            end
            %mposenv = double(interp1q(mitpslocsin,mitpsval,origcount));
            mposenv = double(makefastinterp1(double(mitpslocsin),double(mitpsval),double(origcount)));
            %==========================================================================
            %test to see if any points have been chopped off in the envelope
            newposvals =  mposenv(origlowloc);
            tmpupper = origcount;
            tmpupper(mitpslocsin) = mitpsval;
            tmpupper(origlowloc(newposvals > origlowval)) = origlowval(newposvals > origlowval);
            mitpslocsin = itpslocstest(tmpupper ~= itpslocstest);
            mitpsval = tmpupper(tmpupper ~= itpslocstest);
            %mposenv = double(interp1q(mitpslocsin,mitpsval,origcount));
            
            %==========================================================================
        end
        % remove points that are very nearly the same value
        %finallocs = [1;mitpslocsin(((mitpsval.*(abs(mitpsval -[0;mitpsval(1:(end-1))]) + abs(mitpsval -[mitpsval(2:(end));0])))./mitpsval) > 0.00001)];
        %         finallocs_lower = ((mitpsval.*(abs(mitpsval -[0;mitpsval(1:(end-1))]) + abs(mitpsval -[mitpsval(2:(end));0])))./mitpsval) > smalldrop;
        %         finallocs_lower(1:2) = 1;
        %         finallocs_lower(end) = 1;
        %         mitpslocsin = mitpslocsin(finallocs_lower);
        %         mitpsval = mitpsval(finallocs_lower);
        
        %was adding some white noise
        mitpsval = mitpsval - abs(mitpsval.*nanperwhtnoise);
        
        % interpolate to make the envelope only using fast linear interp
        %mposenv = double(interp1q(mitpslocsin,mitpsval,origcount));
        mposenv = double(makefastinterp1(double(mitpslocsin),double(mitpsval),double(origcount)));
        
        
        %=========================================================================
        % take the difference between the 2nd and 1st envelope
        % then find the envelope of that difference to find the key points
        % to keep and add them back to the scalars
        %
        newnegvals =  mposenv(origlowloc) - origlowval; % difference to orginal lower values
        newposvals =  posenv(origuprloc) - origuprval; % difference to the orginal upper values
        
        if envlplot == 9
            figure(1000); plot(itpslocsin,itpsval,'-ob'); hold on
            plot(origuprloc,newposvals,'-om')
            plot(origlowloc,origlowval,'-or')
            plot(mitpslocsin,mitpsval,'-ob')
            plot(origuprloc,origuprval,'-og')
            plot(trim_data(1:noofrealsamps,ckk),'-k')
            plot(origlowloc,newnegvals,'--or')
        end
        
        
        % calc the envelope of the difference
        max_1st_deriv = diff(newposvals);
        max_2nd_deriv = diff(newposvals,2);
        sign_1_deriv = sign(max_1st_deriv);
        sign_1_deriv(sign_1_deriv == 0) = 1;
        diffsign = diff(sign_1_deriv);
        diffsign(sign(max_2nd_deriv) > 0) = 0;
        diffsign = [1;diffsign];
        updifval = origuprval(diffsign < 0);
        updifval = updifval + abs(newposvals(diffsign < 0).*nanperwhtnoiseb);
        updiflocs = origuprloc(diffsign < 0);
        % make sure the start and end do not get lost
        if isempty(updiflocs) ~= 1
        if updiflocs(end) ~= intrlen
            updiflocs = [updiflocs; intrlen];
            updifval = [updifval; endpos];
        end
        if updiflocs(1) ~= 1
            updiflocs = [1; updiflocs];
            updifval = [firstpos; updifval];
        end
        
        if addback == 1
            % add the two sets of points together
            tmpupper = origcount;
            tmpupper(itpslocsin) = itpsval;  % populate times sequence with the orginal point values
            tmpupper(updiflocs) = updifval;  % populate times sequence with the orginal point values
            itpslocsin = itpslocstest(tmpupper ~= itpslocstest);
            itpsval = tmpupper(tmpupper ~= itpslocstest);
        end
        end
        %
        %==========================================================================
        %test to see if any points have been chopped off in the envelope
        posenv = double(makefastinterp1(double(itpslocsin),double(itpsval),double(origcount)));
        newposvals =  posenv(origuprloc);
        tmpupper = origcount;
        tmpupper(itpslocsin) = itpsval;
        tmpupper(origuprloc(newposvals < origuprval)) = origuprval(newposvals < origuprval);
        itpslocsin = itpslocstest(tmpupper ~= itpslocstest);
        itpsval = tmpupper(tmpupper ~= itpslocstest);
        %posenv = double(interp1q(itpslocsin,itpsval,origcount));
        orig2uprval = itpsval;
        orig2uprlocs = itpslocsin;
        
        %==========================================================================
        
        if envlplot == 9
            figure(1001); plot(itpslocsin,itpsval,'--ob'); hold on
            %plot(origuprloc,newposvals,'-ob')
            plot(posenv,'-r')
            %plot(origlowloc,origlowval,'-or')
            %plot(mitpslocsin,mitpsval,'-or')
            plot(origuprloc,origuprval,'-og')
            plot(trim_data(1:noofrealsamps,ckk),'-k')
            %plot(origlowloc,newnegvals,'--ob')
        end
        
        %==========================================================================
        % calc the envelope of the revised 2nd envelope (3rd envelope)
        max_1st_deriv = diff(itpsval);
        max_2nd_deriv = diff(itpsval,2);
        sign_1_deriv = sign(max_1st_deriv);
        sign_1_deriv(sign_1_deriv == 0) = 1;
        diffsign = diff(sign_1_deriv);
        diffsign(sign(max_2nd_deriv) > 0) = 0;
        diffsign = [1;diffsign];
        itpsval = itpsval(diffsign < 0);
        itpslocsin = itpslocsin(diffsign < 0);
        
        % make sure the start and end do not get lost
        if itpslocsin(end) ~= intrlen
            itpslocsin = [itpslocsin; intrlen];
            itpsval = [itpsval; endpos];
        end
        if itpslocsin(1) ~= 1
            itpslocsin = [1; itpslocsin];
            itpsval = [firstpos; itpsval];
        end
        
        if envlplot == 9
            figure(1002); plot(itpslocsin,itpsval,'-ob'); hold on
            %plot(origuprloc,newposvals,'-ob')
            plot(orig2uprlocs,orig2uprval,'-or')
            %plot(origlowloc,origlowval,'-or')
            %plot(mitpslocsin,mitpsval,'-or')
            plot(origuprloc,origuprval,'-og')
            plot(trim_data(1:noofrealsamps,ckk),'-k')
            %plot(origlowloc,newnegvals,'--ob')
        end
        
        %posenv = double(interp1q(itpslocsin,itpsval,origcount));
        posenv = double(makefastinterp1(double(itpslocsin),double(itpsval),double(origcount)));
        %==========================================================================
        %test to see if any points have been chopped off in the envelope
        newposvals =  posenv(origuprloc);
        tmpupper = origcount;
        tmpupper(itpslocsin) = itpsval;
        tmpupper(origuprloc(newposvals < origuprval)) = origuprval(newposvals < origuprval);
        itpslocsin = itpslocstest(tmpupper ~= itpslocstest);
        itpsval = tmpupper(tmpupper ~= itpslocstest);
        
        %==========================================================================
        posenv = double(makefastinterp1(double(itpslocsin),double(itpsval),double(origcount)));
        
        
        %=========================================================================
        % take the difference between the 3rd and 2nd envelope
        % then find the envelope of that difference to find the key points
        % to keep and add them back to the scalars
        %
        %newnegvals =  mposenv(origlowloc) - origlowval; % difference to orginal lower values
        newposvals =  posenv(orig2uprlocs) - orig2uprval; % difference to the orginal upper values
        
        % find the total distance between envelopes and therefore find the
        % % difference
        distenv = double(makefastinterp1(double(origlowloc),double(origlowval),double(origcount)));
        totalenvdist = posenv(orig2uprlocs) - distenv(orig2uprlocs);
        
        
        if envlplot == 9
            figure(1004); plot(itpslocsin,itpsval,'-ob'); hold on
            plot(orig2uprlocs,newposvals,'-ob')
            plot(orig2uprlocs,orig2uprval,'-og')
            plot(trim_data(1:noofrealsamps,ckk),'-k')
            plot(distenv,'-m');
        end
        
        
        % calc the envelope of the difference
        max_1st_deriv = diff(newposvals);
        max_2nd_deriv = diff(newposvals,2);
        sign_1_deriv = sign(max_1st_deriv);
        sign_1_deriv(sign_1_deriv == 0) = 1;
        diffsign = diff(sign_1_deriv);
        diffsign(sign(max_2nd_deriv) > 0) = 0;
        diffsign = [1;diffsign];
        updifval = orig2uprval(diffsign < 0);
        updifval = updifval + abs(newposvals(diffsign < 0).*nanperwhtnoise);
        updiflocs = orig2uprlocs(diffsign < 0);
        totalenvdistval = abs(newposvals(diffsign < 0))./totalenvdist(diffsign < 0);
        updiflocs = updiflocs(totalenvdistval > 0.75);
        updifval = updifval(totalenvdistval > 0.75);
        
        
        % make sure the start and end do not get lost
        if isempty(updiflocs) ~= 1
        if updiflocs(end) ~= intrlen
            updiflocs = [updiflocs; intrlen];
            updifval = [updifval; endpos];
        end
        if updiflocs(1) ~= 1
            updiflocs = [1; updiflocs];
            updifval = [firstpos; updifval];
        end
        if addback > 1
            % add the two sets of points together
            tmpupper = origcount;
            tmpupper(itpslocsin) = itpsval;  % populate times sequence with the orginal point values
            tmpupper(updiflocs) = updifval;  % populate times sequence with the orginal point values
            itpslocsin = itpslocstest(tmpupper ~= itpslocstest);
            itpsval = tmpupper(tmpupper ~= itpslocstest);
        end
        end
        
        if envlplot == 9
            figure(1005); plot(itpslocsin,itpsval,'-ob'); hold on
            %plot(origuprloc,newposvals,'-ob')
            plot(posenv,'-r')
            %plot(mposenv,'-m')
            plot(origlowloc,origlowval,'-om')
            %plot(mitpslocsin,mitpsval,'-or')
            plot(orig2uprlocs,orig2uprval,'-og')
            plot(trim_data(1:noofrealsamps,ckk),'-k')
            %plot(origlowloc,newnegvals,'--ob')
        end
        
        %===========================================================================
        % check to see that no points were below the orginal points, ie very
        % low freq trend with high freq signal on it, if so do difference of
        % negative difference and choose peaks and add them back in
        
        posenv = double(makefastinterp1(double(itpslocsin),double(itpsval),double(origcount)));
        newposvals =  origuprval - posenv(origuprloc) ; % difference to orginal lower values
        
        newposlocs = origuprloc(newposvals > 0);
        origuprvaltmp = origuprval(newposvals > 0);
        newposvals = newposvals(newposvals > 0);
        
        
        % find the total distance between envelopes and therefore find the
        % % difference
        %         distenv = double(makefastinterp1(double(origuprloc),double(origuprval),double(origcount)));
        %         totalenvdist = distenv(orig2lowlocs) - mposenv(orig2lowlocs);
        
        if envlplot == 9
            figure(1014); plot(itpslocsin,itpsval,'-ob'); hold on
            plot(newposlocs,newposvals,'-om')
            plot(origuprloc,origuprval,'-og')
            plot(trim_data(1:noofrealsamps,ckk),'-k')
        end
        
        
        % calc the envelope of the difference
        max_1st_deriv = diff(newposvals);
        max_2nd_deriv = diff(newposvals,2);
        sign_1_deriv = sign(max_1st_deriv);
        sign_1_deriv(sign_1_deriv == 0) = 1;
        diffsign = diff(sign_1_deriv);
        diffsign(sign(max_2nd_deriv) > 0) = 0;
        diffsign = [1;diffsign];
        updifval = origuprvaltmp(diffsign < 0) + newposvals(diffsign < 0).*clipshift;
        updiflocs = newposlocs(diffsign < 0);
        %         totalenvdistval = abs(newnegvals(mdiffsign < 0))./abs(totalenvdist(mdiffsign < 0));
        %         lowdiflocs = lowdiflocs(totalenvdistval > 0.75);
        %         lowdifval = lowdifval(totalenvdistval > 0.75);
        
        if isempty(updiflocs) ~= 1
        if addback > 1
            % add the two sets of points together
            % need to
            tmpupper = origcount;
            tmpupper(itpslocsin) = itpsval;  % populate times sequence with the orginal point values
            tmpupper(updiflocs) = updifval;  % populate times sequence with the orginal point values
            itpslocsin = itpslocstest(tmpupper ~= itpslocstest);
            itpsval = tmpupper(tmpupper ~= itpslocstest);
        end
        end
        
        if envlplot == 9
            figure(1015); plot(itpslocsin,itpsval,'-ob'); hold on
            plot(updiflocs,updifval,'-om')
            plot(posenv,'-r')
            %plot(origlowloc,origlowval,'-or')
            %plot(mitpslocsin,mitpsval,'-or')
            plot(origuprloc,origuprval,'-og')
            plot(trim_data(1:noofrealsamps,ckk),'-k')
            %plot(origlowloc,newnegvals,'--ob')
        end
        
        
        %===========================================================================
        
        % final test to remove points that are tiny and repeating, ie noise
        %should really be a trim mean to drop the extreme points, but too
        %slow and the limit is set really really small
        finallocs_uppertmp = (itpslocsin -[0;itpslocsin(1:(end-1))]).*abs(itpsval -[0;itpsval(1:(end-1))]) + (abs(([itpslocsin(2:end);0]-itpslocsin)).*abs(itpsval -[itpsval(2:(end));0]));
        finallocs_upper =  finallocs_uppertmp > (mean(finallocs_uppertmp) * finaldroptri);
        finallocs_upper(1:2) = 1;
        finallocs_upper(end) = 1;
        itpslocsin = itpslocsin(finallocs_upper);
        itpsval = itpsval(finallocs_upper);
        %
        %==========================================================================
        %test to see if any points have been chopped off in the envelope
        posenv = double(makefastinterp1(double(itpslocsin),double(itpsval),double(origcount)));
        newposvals =  posenv(origuprloc);
        tmpupper = origcount;
        tmpupper(itpslocsin) = itpsval;
        origuprvalwht = origuprval + abs(origuprval.*nanperwhtnoise);
        tmpupper(origuprloc(newposvals < origuprval)) = origuprvalwht(newposvals < origuprval);
        itpslocsin = itpslocstest(tmpupper ~= itpslocstest);
        itpsval = tmpupper(tmpupper ~= itpslocstest);
        %posenv = double(interp1q(itpslocsin,itpsval,origcount));
        orig3uprval = itpsval;
        orig3uprlocs = itpslocsin;
        posenv = double(makefastinterp1(double(itpslocsin),double(itpsval),double(origcount)));
        %========================================================================
        
        if envlplot == 9
            figure(1006); plot(itpslocsin,itpsval,'-ob'); hold on
            %plot(origuprloc,newposvals,'-ob')
            plot(posenv,'-r')
            %plot(origlowloc,origlowval,'-or')
            %plot(mitpslocsin,mitpsval,'-or')
            plot(origuprloc,origuprval,'-og')
            plot(trim_data(1:noofrealsamps,ckk),'-k')
            %plot(origlowloc,newnegvals,'--ob')
        end
        
        %===========================================================================
        % now refine the lower envelope
        %=========================================================================
        % take the difference between the 2nd and 1st envelope
        % then find the envelope of that difference to find the key points
        % to keep and add them back to the scalars
        %
        newnegvals =  mposenv(origlowloc) - origlowval; % difference to orginal lower values
        %newposvals =  posenv(origuprloc) - origuprval; % difference to the orginal upper values
        
        if envlplot == 9
            figure(2000); plot(mitpslocsin,mitpsval,'-ob'); hold on
            %plot(origuprloc,newposvals,'-ob')
            plot(origlowloc,origlowval,'-og')
            plot(mitpslocsin,mitpsval,'-or')
            %plot(origuprloc,origuprval,'-og')
            plot(trim_data(1:noofrealsamps,ckk),'-k')
            plot(origlowloc,newnegvals,'--ob')
        end
        
        % calc the envelope of the envelope of the envelope
        max_1st_deriv = diff(newnegvals);
        max_2nd_deriv = diff(newnegvals,2);
        sign_1_deriv = sign(max_1st_deriv);
        sign_1_deriv(sign_1_deriv == 0) = 1;
        mdiffsign = diff(sign_1_deriv);
        mdiffsign(sign(max_2nd_deriv) <= 0) = 0;
        mdiffsign = [1;mdiffsign];
        lowdifval = origlowval(mdiffsign > 0);
        lowdifval = lowdifval - abs(newnegvals(mdiffsign > 0).*nanperwhtnoiseb);
        lowdiflocs = origlowloc(mdiffsign > 0);
        % make sure the start and end do not get lost
        if isempty(lowdiflocs) ~= 1
        if lowdiflocs(end) ~= intrlen
            lowdiflocs = [lowdiflocs; intrlen];
            lowdifval = [lowdifval; endneg];
        end
        if lowdiflocs(1) ~= 1
            lowdiflocs = [1; lowdiflocs];
            lowdifval = [firstneg; lowdifval];
        end
        
        if addback == 1
            % add the two sets of points together
            tmpupper = origcount;
            tmpupper(mitpslocsin) = mitpsval;  % populate times sequence with the orginal point values
            tmpupper(lowdiflocs) = lowdifval;  % populate times sequence with the orginal point values
            mitpslocsin = itpslocstest(tmpupper ~= itpslocstest);
            mitpsval = tmpupper(tmpupper ~= itpslocstest);
        end
        end
        %==========================================================================
        %test to see if any points have been chopped off in the envelope
        mposenv = double(makefastinterp1(double(mitpslocsin),double(mitpsval),double(origcount)));
        newnegvals =  mposenv(origlowloc);
        tmpupper = origcount;
        tmpupper(mitpslocsin) = mitpsval;
        tmpupper(origlowloc(newnegvals > origlowval)) = origlowval(newnegvals > origlowval);
        mitpslocsin = itpslocstest(tmpupper ~= itpslocstest);
        mitpsval = tmpupper(tmpupper ~= itpslocstest);
        orig2lowval = mitpsval;
        orig2lowlocs = mitpslocsin;
        
        if envlplot == 9
            figure(2001); plot(mitpslocsin,mitpsval,'-ob'); hold on
            %plot(origuprloc,newposvals,'-ob')
            plot(mposenv,'-r')
            plot(origlowloc,origlowval,'-og')
            %plot(mitpslocsin,mitpsval,'-or')
            %plot(origuprloc,origuprval,'-og')
            plot(trim_data(1:noofrealsamps,ckk),'-k')
            %plot(origlowloc,newnegvals,'--ob')
        end
        
        %==========================================================================
        % calc the envelope of the revised 2nd envelope (3rd envelope)
        max_1st_deriv = diff(mitpsval);
        max_2nd_deriv = diff(mitpsval,2);
        sign_1_deriv = sign(max_1st_deriv);
        sign_1_deriv(sign_1_deriv == 0) = 1;
        mdiffsign = diff(sign_1_deriv);
        mdiffsign(sign(max_2nd_deriv) <= 0) = 0;
        mdiffsign = [1;mdiffsign];
        mitpsval = mitpsval(mdiffsign > 0);
        mitpslocsin = mitpslocsin(mdiffsign > 0);
        
        % make sure the start and end do not get lost
        if mitpslocsin(end) ~= intrlen
            mitpslocsin = [mitpslocsin; intrlen];
            mitpsval = [mitpsval; endpos];
        end
        if mitpslocsin(1) ~= 1
            mitpslocsin = [1; mitpslocsin];
            mitpsval = [firstpos; mitpsval];
        end
        
        if envlplot == 9
            figure(2002); plot(mitpslocsin,mitpsval,'-ob'); hold on
            %plot(origuprloc,newposvals,'-ob')
            %plot(orig2uprlocs,orig2uprval,'-or')
            plot(orig2lowlocs,orig2lowval,'-or')
            %plot(mitpslocsin,mitpsval,'-or')
            plot(origlowloc,origlowval,'-og')
            plot(trim_data(1:noofrealsamps,ckk),'-k')
            %plot(origlowloc,newnegvals,'--ob')
        end
        
        %==========================================================================
        %test to see if any points have been chopped off in the envelope
        mposenv = double(makefastinterp1(double(mitpslocsin),double(mitpsval),double(origcount)));
        newnegvals =  mposenv(origlowloc);
        tmpupper = origcount;
        tmpupper(mitpslocsin) = mitpsval;
        tmpupper(origlowloc(newnegvals > origlowval)) = origlowval(newnegvals > origlowval);
        mitpslocsin = itpslocstest(tmpupper ~= itpslocstest);
        mitpsval = tmpupper(tmpupper ~= itpslocstest);
        %orig2lowval = mitpsval;
        %orig2lowlocs = mitpslocsin;
        mposenv = double(makefastinterp1(double(mitpslocsin),double(mitpsval),double(origcount)));
        
        %=========================================================================
        % take the difference between the 3rd and 2nd envelope
        % then find the envelope of that difference to find the key points
        % to keep and add them back to the scalars
        %
        newnegvals =  mposenv(orig2lowlocs) - orig2lowval; % difference to orginal lower values
        %newposvals =  posenv(orig2uprlocs) - orig2uprval; % difference to the orginal upper values
        
        % find the total distance between envelopes and therefore find the
        % % difference
        distenv = double(makefastinterp1(double(origuprloc),double(origuprval),double(origcount)));
        totalenvdist = distenv(orig2lowlocs) - mposenv(orig2lowlocs);
        
        if envlplot == 9
            figure(2004); plot(mitpslocsin,mitpsval,'-ob'); hold on
            plot(orig2lowlocs,newnegvals,'-ob')
            plot(orig2lowlocs,orig2lowval,'-og')
            plot(trim_data(1:noofrealsamps,ckk),'-k')
        end
        
        
        % calc the envelope of the difference
        max_1st_deriv = diff(newnegvals);
        max_2nd_deriv = diff(newnegvals,2);
        sign_1_deriv = sign(max_1st_deriv);
        sign_1_deriv(sign_1_deriv == 0) = 1;
        mdiffsign = diff(sign_1_deriv);
        mdiffsign(sign(max_2nd_deriv) <= 0) = 0;
        mdiffsign = [1;mdiffsign];
        lowdifval = orig2lowval(mdiffsign > 0);
        lowdifval = lowdifval - abs(newnegvals(mdiffsign > 0).*nanperwhtnoiseb);
        lowdiflocs = orig2lowlocs(mdiffsign > 0);
        totalenvdistval = abs(newnegvals(mdiffsign > 0))./abs(totalenvdist(mdiffsign > 0));
        lowdiflocs = lowdiflocs(totalenvdistval > 0.75);
        lowdifval = lowdifval(totalenvdistval > 0.75);
        
        
        % make sure the start and end do not get lost
        if isempty(lowdiflocs) ~= 1
        if lowdiflocs(end) ~= intrlen
            lowdiflocs = [lowdiflocs; intrlen];
            lowdifval = [lowdifval; endneg];
        end
        if lowdiflocs(1) ~= 1
            lowdiflocs = [1; lowdiflocs];
            lowdifval = [firstneg; lowdifval];
        end
        
        if addback > 1
            % add the two sets of points together
            % need to
            tmpupper = origcount;
            tmpupper(mitpslocsin) = mitpsval;  % populate times sequence with the orginal point values
            tmpupper(lowdiflocs) = lowdifval;  % populate times sequence with the orginal point values
            mitpslocsin = itpslocstest(tmpupper ~= itpslocstest);
            mitpsval = tmpupper(tmpupper ~= itpslocstest);
        end
        end
        if envlplot == 9
            figure(2005); plot(mitpslocsin,mitpsval,'-ob'); hold on
            plot(lowdiflocs,lowdifval,'-om')
            plot(mposenv,'-r')
            %plot(origlowloc,origlowval,'-or')
            %plot(mitpslocsin,mitpsval,'-or')
            plot(origlowloc,origlowval,'-og')
            plot(trim_data(1:noofrealsamps,ckk),'-k')
            %plot(origlowloc,newnegvals,'--ob')
        end
        
        
        %===========================================================================
        % check to see that no points were above the orginal points, ie very
        % low freq trend with high freq signal on it, if so do difference of
        % positive difference and choose peaks and add them back in
        
        mposenv = double(makefastinterp1(double(mitpslocsin),double(mitpsval),double(origcount)));
        newnegvals =  mposenv(origlowloc) - origlowval; % difference to orginal lower values
        
        newneglocs = origlowloc(newnegvals > 0);
        origlowvaltmp = origlowval(newnegvals > 0);
        newnegvals = newnegvals(newnegvals > 0);
        
        
        % find the total distance between envelopes and therefore find the
        % % difference
        %         distenv = double(makefastinterp1(double(origuprloc),double(origuprval),double(origcount)));
        %         totalenvdist = distenv(orig2lowlocs) - mposenv(orig2lowlocs);
        
        if envlplot == 9
            figure(2004); plot(mitpslocsin,mitpsval,'-ob'); hold on
            plot(newneglocs,newnegvals,'-om')
            plot(origlowloc,origlowval,'-og')
            plot(trim_data(1:noofrealsamps,ckk),'-k')
        end
        
        
        % calc the envelope of the difference
        max_1st_deriv = diff(newnegvals);
        max_2nd_deriv = diff(newnegvals,2);
        sign_1_deriv = sign(max_1st_deriv);
        sign_1_deriv(sign_1_deriv == 0) = 1;
        mdiffsign = diff(sign_1_deriv);
        mdiffsign(sign(max_2nd_deriv) > 0) = 0;
        mdiffsign = [1;mdiffsign];
        lowdifval = origlowvaltmp(mdiffsign < 0) - newnegvals(mdiffsign < 0).*clipshift;
        lowdiflocs = newneglocs(mdiffsign < 0);
        %         totalenvdistval = abs(newnegvals(mdiffsign < 0))./abs(totalenvdist(mdiffsign < 0));
        %         lowdiflocs = lowdiflocs(totalenvdistval > 0.75);
        %         lowdifval = lowdifval(totalenvdistval > 0.75);
        
        if isempty(lowdiflocs) ~= 1
        if addback > 1
            % add the two sets of points together
            % need to
            tmpupper = origcount;
            tmpupper(mitpslocsin) = mitpsval;  % populate times sequence with the orginal point values
            tmpupper(lowdiflocs) = lowdifval;  % populate times sequence with the orginal point values
            mitpslocsin = itpslocstest(tmpupper ~= itpslocstest);
            mitpsval = tmpupper(tmpupper ~= itpslocstest);
        end
        end
        if envlplot == 9
            figure(2015); plot(mitpslocsin,mitpsval,'-ob'); hold on
            plot(lowdiflocs,lowdifval,'-om')
            plot(mposenv,'-r')
            %plot(origlowloc,origlowval,'-or')
            %plot(mitpslocsin,mitpsval,'-or')
            plot(origlowloc,origlowval,'-og')
            plot(trim_data(1:noofrealsamps,ckk),'-k')
            %plot(origlowloc,newnegvals,'--ob')
        end
        
        
        %===========================================================================
        
        % final test to remove points that are tiny and repeating, ie noise
        %should really be a trim mean to drop the extreme points, but too
        %slow and the limit is set really really small
        finallocs_lowertmp = (mitpslocsin -[0;mitpslocsin(1:(end-1))]).*abs(mitpsval -[0;mitpsval(1:(end-1))]) + (abs(([mitpslocsin(2:end);0]-mitpslocsin)).*abs(mitpsval -[mitpsval(2:(end));0]));
        %finallocs_upper = ((itpsval.*(abs(itpsval -[0;itpsval(1:(end-1))]) + abs(itpsval -[itpsval(2:(end));0])))./itpsval) > smalldrop;
        finallocs_lower =  finallocs_lowertmp > (mean(finallocs_lowertmp) * finaldroptri);
        finallocs_lower(1:2) = 1;
        finallocs_lower(end) = 1;
        mitpslocsin = mitpslocsin(finallocs_lower);
        mitpsval = mitpsval(finallocs_lower);
        
        
        %========================================================================
        %test to see if any points have been chopped off in the envelope
        mposenv = double(makefastinterp1(double(mitpslocsin),double(mitpsval),double(origcount)));
        newnegvals =  mposenv(origlowloc);
        tmpupper = origcount;
        tmpupper(mitpslocsin) = mitpsval;
        origlowvalwht = origlowval - abs(origlowval.*nanperwhtnoise);
        tmpupper(origlowloc(newnegvals > origlowval)) = origlowvalwht(newnegvals > origlowval);
        mitpslocsin = itpslocstest(tmpupper ~= itpslocstest);
        mitpsval = tmpupper(tmpupper ~= itpslocstest);
        orig3lowval = mitpsval;
        orig3lowlocs = mitpslocsin;
        mposenv = double(makefastinterp1(double(mitpslocsin),double(mitpsval),double(origcount)));
        
        if envlplot == 9
            figure(2006); plot(mitpslocsin,mitpsval,'-ob'); hold on
            %plot(origuprloc,newposvals,'-ob')
            plot(mposenv,'-r')
            plot(origlowloc,origlowval,'-og')
            %plot(mitpslocsin,mitpsval,'-or')
            %plot(origuprloc,origuprval,'-og')
            plot(trim_data(1:noofrealsamps,ckk),'-k')
            %plot(origlowloc,newnegvals,'--ob')
        end
        
        %=========================================================================
        % calculate the mid points of the upper and lower envelopes from the
        % interpolated envelopes
        midpoints = posenv+(((posenv.*-1) - (mposenv.*-1)).*0.5);
        
        if envlplot == 3
            figure(5); plot(midpoints,'-b'); hold on
            %plot(midpoints_red_t(:,1),midpoints_red_t(:,2),'or');
            plot(posenv,'-r')
            %plot(midpoints_red_t(:,1),mposenv(midpoints_red_t(:,1)),'-or');
            plot(mposenv,'-g');
            plot(trim_data(1:noofrealsamps,ckk),'-k')
        end
        
        %decimate the mid points and then reinterpolate same as the
        %uncompression would do
        %if morecompress < 3
        % make the mid points for all the points on up and lower envelope
        itpslocs(itpslocsin) = itpsval;
        itpslocs(mitpslocsin) = mitpsval;
        points_all = itpslocstest(itpslocs ~= itpslocstest);
        %else
        %    points_all = mitpslocsin;
        %end
        
        % make the sets of points to store
        midpoints_red = single(midpoints(points_all));
        mitpsval_red = single(mposenv(points_all));
        
        %calculate the grdients along the mid point curve
        ygrad = ([midpoints_red(2:end);midpoints_red(end)] - midpoints_red);
        xgrad = ( [points_all(2:end);points_all(end)]  - points_all   );
        
        % ====================================================================
        % decimate mid points to just those points which are not too close,
        
        % but keep start and end
        %       points_all = points_all([999;999;diff(points_all(2:end-1));999]>4);
        % workout the distance between the points and replace those too close to
        % each other with the average, ie on do test for those point less than 10 samples apart
        mid_lens = (ygrad.*ygrad) + (xgrad.*xgrad);
        mean_mid_lens = mean(mid_lens);
        %mean_mid_lens = (sum(mid_lens))/size(mid_lens,1);
        pointlogic =or([999;999;diff(points_all(3:end-1));999;999]>6, mid_lens > (mean_mid_lens*smalldrop));
        points_all = points_all(pointlogic);
        ygrad = ygrad(pointlogic);
        xgrad = xgrad(pointlogic);
        
        midpoints_red_grad = ygrad./xgrad;
        
        %bob = [midpoints_red [1;midpoints_red_grad(1:(end-1))] ([1;midpoints_red_grad(1:(end-1))]-[midpoints_red_grad(1:(end-1));1])  abs([1;midpoints_red_grad(1:(end-1))]-[midpoints_red_grad(1:(end-1));1])  ];
        top15grads = sortrows([abs([9999999;9999999;midpoints_red_grad(2:(end-2));9999999]-[0;midpoints_red_grad(2:(end-2));9999999;0])  points_all ],-1);
        
        % check to see if the first point in the time series has been included or not
        if top15grads(1,2) ~= 1
            top15grads = [[9999999 1];top15grads];
        end
        
        %populate the fixed size array to hold the top n points
        if tpgrad > size(top15grads,1);
            tpgrad = size(top15grads,1);
        end
        midpoints_red_t(1:tpgrad,:) = [top15grads(1:tpgrad,2) single(midpoints(top15grads(1:tpgrad,2)))];
        midpoints_red_t = sortrows(midpoints_red_t);
        
        % set the points to use and remove any duplication with diff not equal
        % to zero
        points_all = midpoints_red_t(:,1);
        %midpoints_red = midpoints_red_t(:,2);
        %midpoints_red = midpoints_red([diff(points_all);1] ~= 0);
        points_all = points_all([diff(points_all);1] ~= 0);
        midpoints_red = single(midpoints(points_all));
        mitpsval_red = single(mposenv(points_all));
        mitpsupr_red = single(midpoints(points_all)-(mposenv(points_all)-midpoints(points_all)));
        
        if envlplot == 3
            figure(1); plot(points_all,midpoints_red,'-ob'); hold on
            %plot(midpoints_red_t(:,1),midpoints_red_t(:,2),'or');
            plot(points_all,mitpsval_red,'-or')
            %plot(midpoints_red_t(:,1),mposenv(midpoints_red_t(:,1)),'-or');
            plot(points_all,mitpsupr_red,'-og');
            plot(trim_data(1:noofrealsamps,ckk),'-k')
        end
        
        %===================================================================
        %test to see if any points have been chopped off in the envelope
        % lower
        mposenv_red = double(makefastinterp1(double(points_all),double(mitpsval_red),double(origcount)));
        mposenv_red(isnan(mposenv_red)) = 0;
        % upper
        posenv_red = double(makefastinterp1(double(points_all),double(mitpsupr_red),double(origcount)));
        posenv_red(isnan(posenv_red)) = 0;
        %
        newnegvals =  mposenv_red(origlowloc); % grab the orginal lower values
        newposvals =  posenv_red(origuprloc); % grab the orginal upper values
        tmpupper = origcount;
        tmpupper(points_all) = mitpsval_red;  % populate times sequence with the orginal point values
        if envlplot == 3
            figure(111); plot(origuprloc,newposvals,'-ob'); hold on
            plot(origlowloc,origlowval,'-or')
            plot(origuprloc,origuprval,'-og')
            plot(trim_data(1:noofrealsamps,ckk),'-k')
            plot(origlowloc,newnegvals,'--ob')
        end
        %fprintf('trace %d \n',ckk);
        tmpupper(origlowloc(newnegvals > origlowval)) = origlowval(newnegvals > origlowval); % test to see if the orginal peaks are below the peaks from the reduced dataset
        tmpupper(origuprloc(newposvals < origuprval)) = origuprval(newposvals < origuprval); % test to see if the orginal peaks are below the peaks from the reduced dataset
        points_all_extra = itpslocstest(tmpupper ~= itpslocstest); % test to see what is not a time sample, and take those as the points to keep
        %mitpsval_red_extra = tmpupper(tmpupper ~= itpslocstest);
        mitpsval_red_extra = single(mposenv(points_all_extra));
        posenv_red_extra = single(posenv(points_all_extra));
        %mposenv = double(interp1q(mitpslocsin,mitpsval,origcount));
        
        %     midpoints_red = midpoints_red_extra;
        %     mitpsval_red = mitpsval_red_extra;
        %     points_all = points_all_extra;
        if size(points_all_extra,1) > size(points_all,1)
            %fprintf('%d extra points needed ', size(points_all_extra,1) - size(points_all,1));
            % workout the difference in the values between the orginal lower points
            % (mitpsval_red_extra) and the decimated ones (mposenv_red)
            %extradiff = sortrows([(mitpsval_red_extra - mposenv_red(points_all_extra)) points_all_extra],1);
            % workout the difference in the values between the decimated and the orginal upper points
            %extradiffupr = sortrows([(posenv_red(points_all_extra) - posenv_red_extra) points_all_extra],1);
            % do both together
            extradiff = sortrows([[(mitpsval_red_extra - mposenv_red(points_all_extra));(posenv_red(points_all_extra) - posenv_red_extra)] [points_all_extra;points_all_extra] [mitpsval_red_extra;posenv_red_extra]],1);
            
            %take the top extrapoints values and add to the previous set, do
            %this by writting the previous values into the samples set of all
            %samples times and the writting the new points to that one as well,
            %the values are very unlikely to the same values as the sample numbers
            tmpupper = origcount; % set up just the incresing sequence of time samples, which is always just integers as they have to be array indexes
            tmpupper(points_all) = mitpsval_red; % populate times seqeuce with the original point values
            %tmpupper(extradiff(1:extrapoints,2)) = single(mposenv(extradiff(1:extrapoints,2)));  % add the extra n points that lie below
            tmpupper(extradiff(1:extrapoints,2)) = single(extradiff(1:extrapoints,3));  % add the extra n points that lie below
            
            points_all = itpslocstest(tmpupper ~= itpslocstest); % test to see what is not a time sample, and take those as the points to keep
            points_all_blk(1:size(points_all,1)) = points_all;
            points_all = points_all_blk;
            points_all = points_all([1;diff(points_all)] > 0);
            mitpsval_red = single(mposenv(points_all));
            midpoints_red = single(midpoints(points_all));
        end
        
        %=====================================================================
        % re interp to be consistent with decompression
        %    midpoints = double(interp1q(points_all,midpoints_red,origcount));
        %    mposenv = double(interp1q(points_all,mitpsval_red,origcount));
        %
        % a different version using a mex file for the interp
        % also drop any duplicate time smaples, using diff not equal to zero
        
        midpoints = double(makefastinterp1(double(points_all),double(midpoints_red),double(origcount)));
        midpoints(isnan(midpoints)) = 0;
        mposenv = double(makefastinterp1(double(points_all),double(mitpsval_red),double(origcount)));
        mposenv(isnan(mposenv)) = 0;
        
        % now make the scaler to make envlope all fit the value 2000
        %scalepos = 2000 ./ maxenv;
        %scalepos = bsxfun(@rdivide,2000,posenv);
        
        if envlplot == 3
            figure(97); plot(trim_data(1:noofrealsamps,ckk),'-k');
            hold on;
            plot(mposenv,'-r');
            plot((midpoints-(mposenv-midpoints)),'-g');
            %plot(posenv,'-m');
            plot(midpoints,'-b');
            %plot((midpoints - mposenv),'-m');
        end
        
        
        %Apply the scaling to the input data
        scaleval = scalepeak./(midpoints - mposenv);
        scaleval(isnan(scaleval)) = 1;
        scaleval(isinf(scaleval)) = 1;
        
        if morecompress < 3
            trim_data_filt(firstreal:lastreal,ckk) = int8((trim_data(1:noofrealsamps,ckk)-midpoints).*scaleval);
        else
            trim_data_filt(firstreal:lastreal,ckk) = int16((trim_data(1:noofrealsamps,ckk)-midpoints).*scaleval);
        end
    else % traces are entirely zeros
        if morecompress < 3
            trim_data_filt(:,ckk) = int8(trim_data(:,ckk));
        else
            trim_data_filt(:,ckk) = int16(trim_data(:,ckk));
        end
    end
    if envlplot == 3
        figure(99); plot(trim_data_filt(:,ckk),'-k');
        figure(999); plot(trim_data(:,ckk),'-ok');
        hold on;
        plot(mposenv,'-r');
        plot((midpoints-(mposenv-midpoints)),'-g');
    end
    %=====================================================================
    % write out the outputs
    scalars_out(1,1:size(midpoints_red,1),ckk) = midpoints_red;
    scalars_out(2,1:size(mitpsval_red,1),ckk) = mitpsval_red;
    % add on the first live sample numder tot he points for recompression
    points_all = points_all+nooffzeros;
    zlocs_out(1:size(points_all,1),ckk) = uint16(points_all);
    %orig_nsamples(ckk) = samples_arr;
    
    %=====================================================================
    %uncompress the data to compare
    % for production just use the previous value rather than recomputing,
    % this is just code to put in a decompress function
    
    % need to have saved
    %     1) midpoints_red
    %     2) mitpsval_red
    %     3) scalepeak
    %     4) points_all
    
    %get the number of samples from the input
    %intrlength = size(trim_data,1);
    %intrlength = (intrlen_orig- tpgrad_orig);
    intrlength = intrlen_orig;
    %samples_arr = single(1:intrlength)';
    %samples_arr = origcount;
    
    %now remember to remove the scalars from the bottom of the trace
    %trim_data_filt(:,ckk) = trim_data_filt(1:intrlength,ckk);
    
    %get the value to scale to from the trace header
    %scalepeak = double(scalepeak);
    
    % read the scaling points and samples from the trace removing dupliates
    %     points_all = single(zlocs_out(:,ckk));
    %     midpoints_red = single(scalars_out(1,:,ckk));
    %     midpoints_red = midpoints_red([1;diff(points_all)] > 0);
    %     mitpsval_red = single(scalars_out(2,:,ckk));
    %     mitpsval_red = mitpsval_red([1;diff(points_all)] > 0);
    %     points_all = points_all([1;diff(points_all)] > 0);
    
    % before interpolating need to add extra points at the start and end of
    % the trace as the scalars can be anywhere along the trace
    %     if(points_all(1) ~= 1)
    %         points_all = [1;points_all];
    %         mitpsval_red = [mitpsval_red(1);mitpsval_red];
    %         midpoints_red = [midpoints_red(1);midpoints_red];
    %     end
    
    resmposenv = mposenv;
    %%resmposenv = double(interp1q(points_all,mitpsval_red,samples_arr));
    %resmposenv = double(makefastinterp1(double(points_all),double(mitpsval_red),double(samples_arr)));
    
    res_midpoints = midpoints;
    %%res_midpoints = double(interp1q(points_all,midpoints_red,samples_arr));
    %res_midpoints = double(makefastinterp1(double(points_all),double(midpoints_red),double(samples_arr)));
    
    
    %scaleval_restmp = (res_midpoints - resmposenv)./scalepeak;
    scaleval_restmp = (midpoints - mposenv)./scalepeak;
    scaleval_restmp(isnan(scaleval_res)) = 1;
    % this expansion is just for this code, the decompression needs to just add the points into a set array of blanks or ones
    scaleval_res = [ones(nooffzeros,1,'double');scaleval_restmp;ones(nooflzeros,1,'double')];
    res_midpoints = [zeros(nooffzeros,1,'double');midpoints;zeros(nooflzeros,1,'double')];
    
    diffout = single((single(trim_data_filt(:,ckk)).*scaleval_res)+res_midpoints);
    
    if envlplot > 2
        figure(101); plot([zeros(nooffzeros,1,'single');trim_data(1:noofrealsamps,ckk);zeros(nooflzeros,1,'single')],'-k');
        hold on;
        plot(diffout,'-r');
        %figure(103); hist(single(trim_data_filt(:,ckk)),255);
        %figure(103); hist(single(trim_data_filt(:,ckk)),65536);
        %       figure(102); plot((abs(double([zeros(nooffzeros,1,'single');trim_data(1:noofrealsamps,ckk);zeros(nooflzeros,1,'single')]) - double(diffout)))./abs(double([zeros(nooffzeros,1,'single');trim_data(1:noofrealsamps,ckk);zeros(nooflzeros,1,'single')])),'-k');
        %          hold on;
        %          figure(103); plot((abs((trim_data(:,ckk) - diffout)))./abs((trim_data(:,ckk))),'-g');
        
    end
    
    % added a 2% skip on error check on start and end of trace incase it is
    % a truncated trace which needs error checking with input samples
    % (which will take time) and they do not matter vey much as just the
    % ends of the traces
    errsskip = ceil(noofrealsamps*0.02);
    percenterr(ckk) = single((abs(sum(abs(double(trim_data((1+errsskip):(noofrealsamps-errsskip),ckk)))) - sum( abs( double(diffout((firstreal+errsskip):(lastreal-errsskip))))))/sum(abs(double(trim_data((1+errsskip):(noofrealsamps-errsskip),ckk)))))*100);
    
    %percenterr(ckk) = single((abs(sum(abs(double(trim_data(1:noofrealsamps,ckk)))) - sum( abs( double(diffout))))/sum(abs(double(trim_data(1:noofrealsamps,ckk)))))*100);
    
    %     summoferror = sum(abs((trim_data(:,ckk) - diffout)));
    %     summofinput = sum(abs(trim_data(:,ckk)));
    %%if or(and( (summoferror/summofinput) > 0.0001, morecompress > 2), and( (summoferror/summofinput) > 0.01, morecompress == 2))
    if or(and( percenterr(ckk) > 0.25, morecompress > 2), and( percenterr(ckk) > 0.5, morecompress <= 2))
    bytes_to_store = ((size(scalars_out,1)*4) + ((size(zlocs_out,1)*8) + 4));
    if morecompress < 3
        compression_ratio = (intrlength*4) / ((intrlength) + bytes_to_store);
    else
        compression_ratio = (intrlength*4) / ((intrlength*2) + bytes_to_store);
    end
    
    fprintf('trace %d ; %-10.8f percent error in reconstruction of dataset, one in %d, using %d bytes of scalars compression ratio %-5.2f \n',ckk,percenterr(ckk),round((100/percenterr(ckk))),bytes_to_store,compression_ratio);
    end
%
end


end
