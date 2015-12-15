function [] = int_grad_inv_proj(job_meta_path,i_block)
% -------------------------------------------------------------------------
% INT_GRAD_INV_PROJ: function to run Intercept Gradient Inversion using
% dynamic wavelet set.
%   Inputs:
%       seismic_mat_path = path of metadata .mat file.
%       i_block = current block to be processed.
%       n_blocks = total number of blocks to submit for processing.
%   Outputs:
%       digi_intercept = n_blocks of SEGY files.
%       digi_gradient = n_blocks of SEGY files.
%       digi_minimum_energy_eer_projection = n_blocks of SEGY files.
% Authors: Jonathan Edgar and James Selvage
% -------------------------------------------------------------------------
output_std = 0;
% Load job meta information 
job_meta = load(job_meta_path);

% Make ouput directories and create meta information

% Load wavelet set
wavelets = load(strcat(job_meta.wav_directory,'all_wavelets_time.mat'));

% Some angle stacks do not have data in the shallow etc. so the number of
% time windows on each varies. This finds the common time windows across
% all angle stacks to be used in the inversion
%wavelet_z_grid = unique(wavelets.all_wavelets_time{1}(1,:));
[~,wavelet_tmp_idx] = ismember(wavelets.min_wavelet_z_grid,fliplr(wavelets.all_wavelets_time{1}(1,:)));
wavelet_tmp_idx = size(wavelets.all_wavelets_time{1},2)-wavelet_tmp_idx+1;

% Read traces for 2/3 max angle stack
vol_index_wb = ceil(job_meta.nvols*0.6667);
[~, traces{vol_index_wb}, ilxl_read{vol_index_wb}] = ...
    node_segy_read(job_meta_path,num2str(vol_index_wb),i_block);
% Initial variables

% Pick water bottom
[wb_idx] = water_bottom_picker(traces{vol_index_wb},0);
wb_idx(wb_idx < 0) = 1;
win_sub = bsxfun(@plus,wb_idx,(0:job_meta.n_samples{vol_index_wb}-max(wb_idx))');
win_ind = bsxfun(@plus,win_sub,(0:job_meta.n_samples{vol_index_wb}:...
job_meta.n_samples{vol_index_wb}*(size(traces{vol_index_wb},2)-1)));

% Load block for remaining angle stacks
for i_vol = 1:1:job_meta.nvols 
    if i_vol ~= str2double(vol_index_wb) % don't repeat load for previously read stack
        % Read traces
        [~, traces{i_vol}, ilxl_read{i_vol}, ~] = ...
        node_segy_read(job_meta_path,num2str(i_vol),i_block);
    end   
    % Flatten traces to water bottom
    traces{i_vol} = traces{i_vol}(win_ind);    
    %traces{i_vol} = traces{i_vol}(,:);
    input_angles(i_vol) = (job_meta.angle{i_vol}(2)+job_meta.angle{i_vol}(1))/2;
end
%clearvars traces
i_block = str2double(i_block);
% Initial some variables
ns_wavelet = size(wavelets.all_wavelets_time{1},1)-1;
hns_wavelet = floor(ns_wavelet/2);
[ns,ntraces] = size(traces{1});
alpha = 1; % Weight for EER constraint

% Build blanking matrix used to ensure the convolution operator matrix is correct
IGblank = spdiags(ones(ns,2*hns_wavelet+1),(-hns_wavelet:hns_wavelet),ns,ns);
IGblank = repmat(IGblank,1+job_meta.nvols,2);

% Tikhonov regularisation weight
wsmooth = 0;
% Tikhonov regularisation matrix
smooth = spdiags([-wsmooth*ones(2*ns,1) 2*wsmooth*ones(2*ns,1) -wsmooth*ones(2*ns,1)],[-1 0 1],2*ns,2*ns);

%% Inversion loop

% Set first and last traces to loop over
first_iter = 1;
last_iter = ntraces;

% Begin inversion loop
tic
for kk = first_iter:last_iter
    
    % Read the angle stack data for the inversion of this trace
    for ii = 1:job_meta.nvols
        data(:,ii) = traces{ii}(:,kk);
    end
    
    %         data = bsxfun(@times,data,taper);
    
    % Build the minimum energy chi angle from the chi model for this trace location
    %        chi(:,kk) = (1:1:ns)'.*chi_model_grid(chi_finder(:,kk),4) + chi_model_grid(chi_finder(:,kk),3);
    % chi = seismic.srate*(0:1:ns-1)'.*-1 + 20;
    chi = (job_meta.s_rate/1e6)*(0:1:ns-1)'.*-2 + 19;
    
    
    % Extract the angle of the stack closest to the mean chi angle for this trace
    theta = asind(sqrt(tand(mean(chi))));
    [~, angle_index] = min(abs(input_angles-theta));
    
    if kk == first_iter
        for ii=1:job_meta.nvols
            wavelet_tmp{ii} = wavelets.all_wavelets_time{ii}(2:end,:);
        end
        [IGmatrix] = build_operator(job_meta,input_angles,ns_wavelet,wavelets.min_wavelet_z_grid,wavelet_tmp,wavelet_tmp_idx,ns,hns_wavelet,angle_index,chi,alpha,IGblank,smooth);
    end
    
    IGmatrix_iter = IGmatrix;
    
    
    % Set NaNs to zero
    data(isnan(data)) = 0;
    
    % Get angle fold
    fold = sum(data ~= 0,2);
    
    % Make temporary column vector from data
    data_tmp = data(:);
    
    % Find zones where data is zero (due to mute angle mute functions)
    data_zeros = data_tmp == 0;
    data_zeros = logical([data_zeros;zeros(3*ns,1)]);
    
    % Set operator rows to zero if there are zeros in the data vector
    IGmatrix(data_zeros,:) = 0;
    
    % Model intercept = [near], model gradient = [far-near]/[far_angle - near_angle]
    model_tmp = zeros(2,ns);
    for ii = 1:ns
        model_op = [ones(job_meta.nvols,1),sind(input_angles').*sind(input_angles')];
        model_zeros = data(ii,:) == 0;
        model_op(model_zeros,:) = 0;
        model_tmp(:,ii) = model_op\data(ii,:)';
    end
    model_tmp = model_tmp';
    if output_std == 1;
        Imodel(:,kk) = model_tmp(:,1)/norm(model_tmp(:,1)); %data(:,1)/norm(data(:,1));
        Gmodel(:,kk) = model_tmp(:,2)/norm(model_tmp(:,1)); %-Imodel./tand(chi);
        model = [Imodel(:,kk);Gmodel(:,kk)];
    else
        Imodel = model_tmp(:,1)/norm(model_tmp(:,1)); %data(:,1)/norm(data(:,1));
        Gmodel = model_tmp(:,2)/norm(model_tmp(:,1)); %-Imodel./tand(chi);
        model = [Imodel;Gmodel];
    end
    % Set NaNs to zero
    model(isnan(model)) = 0;
    
    % Make the data a column vector and add zeros on the end for the EER constraint and the Tikhonov regularisation
    data = [data(:);zeros(3*ns,1)];
    
    % Do the inversion
    [ava(:,kk),~] = lsqr(IGmatrix_iter,data,1e-2,100,[],[],model);
    ava([fold;fold]==0,kk)=0;
    
    % Estimate the R^2 confidence in the result. This is the variance ratio:
    % 1-[(sum(data-Gm)^2)/(sum(data-mean)^2)], where the inversion was
    % solving data = Gm.
    data = reshape(data(1:ns*job_meta.nvols,:),[],job_meta.nvols);
    digi_confidence(:,kk) = 1-(sum((data-reshape(IGmatrix_iter(1:job_meta.nvols*ns,:)*ava(:,kk),[],job_meta.nvols)).^2,2)./sum(bsxfun(@minus,data,sum(data,2)./fold).^2,2));
    
    
    % Clear the data ready for the next trace
    clearvars data
    
    % Give a status report
    fprintf('Completed trace %d of %d\n',kk-first_iter+1,last_iter-first_iter+1)
end
toc

digi_confidence(digi_confidence<0)=0;
digi_confidence(digi_confidence>1)=1;
digi_confidence(isnan(digi_confidence))=0;

top_pad = min(wavelets.min_wavelet_z_grid)-mode(diff(wavelets.min_wavelet_z_grid'));
bottom_pad = max(wavelets.min_wavelet_z_grid)+mode(diff(wavelets.min_wavelet_z_grid'));

% Make outputs to be saved to .mat files
digi_intercept = [zeros(top_pad-1,ntraces);ava(1:ns,:);zeros(job_meta.n_samples{vol_index_wb}-bottom_pad,ntraces)];
digi_gradient = [zeros(top_pad-1,ntraces);ava(1+ns:end,:);zeros(job_meta.n_samples{vol_index_wb}-bottom_pad,ntraces)];
digi_minimum_energy_eer_projection = [bsxfun(@times,ava(1:ns,:),cosd(chi))+bsxfun(@times,ava(1+ns:end,:),sind(chi));zeros(job_meta.n_samples{vol_index_wb}-ns,ntraces)];
digi_confidence = [zeros(top_pad-1,ntraces);digi_confidence;zeros(job_meta.n_samples{vol_index_wb}-bottom_pad,ntraces)];
if output_std == 1;
    std_intercept = [Imodel;zeros(job_meta.n_samples{vol_index_wb}-ns,ntraces)];
    std_gradient = [Gmodel;zeros(job_meta.n_samples{vol_index_wb}-ns,ntraces)];
    std_minimum_energy_eer_projection = [bsxfun(@times,Imodel,cosd(chi))+bsxfun(@times,Gmodel,sind(chi));zeros(job_meta.n_samples{vol_index_wb}-ns,ntraces)];
end


% Write slice ordered binary of the minimum energy projection for use in SAS
if exist(strcat(seismic.output_dir,'digi_results/minimum_energy_slices/'),'dir') == 0
    mkdir(strcat(seismic.output_dir,'digi_results/minimum_energy_slices/'));
    fid_out = fopen(strcat(seismic.output_dir,'digi_results/minimum_energy_slices/','digi_minimum_energy_eer_projection','_slices_block_',num2str(i_block),'.bin'),'w');
else
    fid_out = fopen(strcat(seismic.output_dir,'digi_results/minimum_energy_slices/','digi_minimum_energy_eer_projection','_slices_block_',num2str(i_block),'.bin'),'w');
end
fwrite(fid_out,ns,'float32');
fwrite(fid_out,digi_minimum_energy_eer_projection(1:ns,:)','float32');
fclose(fid_out);

% Unflatten data
for kk = 1:length(wb_idx)
    digi_intercept(:,kk) = circshift(digi_intercept(:,kk),wb_idx(kk));
    digi_gradient(:,kk) = circshift(digi_gradient(:,kk),wb_idx(kk));
    digi_minimum_energy_eer_projection(:,kk) = circshift(digi_minimum_energy_eer_projection(:,kk),wb_idx(kk));
    if output_std == 1;
        std_intercept(:,kk) = circshift(std_intercept(:,kk),wb_idx(kk));
        std_gradient(:,kk) = circshift(std_gradient(:,kk),wb_idx(kk));
        std_minimum_energy_eer_projection(:,kk) = circshift(std_minimum_energy_eer_projection(:,kk),wb_idx(kk));
    end
end

% Save outputs into correct structure to be written to SEGY.
results_out{1,1} = 'ilxl numbers';
results_out{1,2} = ilxl_read;
results_out{2,1} = 'digi_intercept';
results_out{2,2} = digi_intercept;
results_out{3,1} = 'digi_gradient';
results_out{3,2} = digi_gradient;
results_out{4,1} = 'digi_minimum_energy_eer_projection'; 
results_out{4,2} = digi_minimum_energy_eer_projection;
if output_std == 1;
%     results_out{5,1} = 'std_intercept';
%     results_out{5,2} = std_intercept;
%     results_out{6,1} = 'std_gradient';
%     results_out{6,2} = std_gradient;
%     %results_out{7,1} = 'std_minimum_energy_eer_projection';
%     %results_out{7,2} = std_minimum_energy_eer_projection;
end


% check segy write functions - many different versions now!
if exist(strcat(seismic.output_dir,'digi_results/','intercept_gradient_segy/'),'dir') == 0
    mkdir(strcat(seismic.output_dir,'digi_results/','intercept_gradient_segy/'));
    output_dir = strcat(seismic.output_dir,'digi_results/','intercept_gradient_segy/');
else
    output_dir = strcat(seismic.output_dir,'digi_results/','intercept_gradient_segy/');
end

%sw_segy_write_clean(results_out,i_block, n_blocks, sample_rate, output_dir);
node_segy_write_traces(results_out,i_block,output_dir)

end

function [IGmatrix] = build_operator(job_meta,input_angles,ns_wavelet,wavelet_z_grid,wavelet_tmp,wavelet_tmp_idx,ns,hns_wavelet,angle_index,chi,alpha,IGblank,smooth)
    % Normalise the wavelets to have constant energy w.r.t. angle. The energy
    % is set to that of the nearest angle wavelets. Wavelet energy still varies
    % w.r.t. time.
    A = cell2mat(wavelet_tmp);
    B = sqrt(sum(A.^2));
    C = reshape(B',length(wavelet_z_grid),[]);
    D = C(:,1);
    for ii=1:job_meta.nvols
        E = A(:,1+(ii-1)*length(wavelet_z_grid):ii*length(wavelet_z_grid));
        F = bsxfun(@rdivide,bsxfun(@times,E,D'),sqrt(sum(E.^2)));
        wavelet_tmp{ii} = F;
    end

%     start_interp = min(wavelet_z_grid)-mode(diff(wavelet_z_grid'));
%     end_interp = max(wavelet_z_grid)+mode(diff(wavelet_z_grid'));
    start_interp = 1;
    end_interp = ns;
    % Build operator
    for ii = 1:job_meta.nvols
        Iwavelet_interp(:,1+(ii-1)*ns_wavelet:ii*ns_wavelet) = interp1(wavelet_z_grid,wavelet_tmp{ii}(:,wavelet_tmp_idx)',start_interp:1:end_interp,'linear','extrap');
        Gwavelet_interp(:,1+(ii-1)*ns_wavelet:ii*ns_wavelet) = interp1(wavelet_z_grid,...
            wavelet_tmp{ii}(:,wavelet_tmp_idx)'*(sind(input_angles(ii)).*sind(input_angles(ii))),start_interp:1:end_interp,'linear','extrap');
    end

    IGdiagnals = sort(reshape([(-hns_wavelet:hns_wavelet)',bsxfun(@plus,(-hns_wavelet:hns_wavelet)',(-ns:-ns:-ns*(job_meta.nvols-1)))],1,[]),'descend');

    Imatrix = spdiags(Iwavelet_interp,IGdiagnals,ns*job_meta.nvols,ns);
    Gmatrix = spdiags(Gwavelet_interp,IGdiagnals,ns*job_meta.nvols,ns);

    EERmatrix = alpha*[bsxfun(@times,Imatrix(1+ns*(angle_index-1):+ns*angle_index,:),cosd(chi)),bsxfun(@times,Imatrix(1+ns*(angle_index-1):+ns*angle_index,:),sind(chi))];

    IGmatrix = [[Imatrix,Gmatrix;EERmatrix].*IGblank;smooth];
end