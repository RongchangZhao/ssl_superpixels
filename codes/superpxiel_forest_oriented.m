% superpxiel_forest_oriented for semi supervised
% learning. This function constructs forest oriented super pixels(voxels) to augment the
%standard random forest classifier, in which super pixels(voxels) are built
%upon the forest based code. 
% Implementation of "Semi-Supervised Learning for Biomedical Image Segmentation
% via Forest Oriented Super Pixels(Voxels)"
%
% Usage:    [l, cSP, Sp] = superpxiel_forest_oriented(est_img,tbc_img, k, m, nIters)
%
% Arguments:  est_img - Initial estimation of image to be segmented.
%             tbc_img - tree based code of image to be segmented.
%              k - Number of desired superpixels. Note that this is nominal
%                  the actual number of superpixels generated will generally
%                  be a bit larger, espiecially if parameter m is small.
%              m - Weighting factor between colour and spatial
%                  differences. Values from about 5 to 40 are useful.  Use a
%                  large value to enforce superpixels with more regular and
%                  smoother shapes. Try a value of 10 to start with.
%              nIter - The number of iteration for generating the
%              superpixels. Emprically, the algorithm would converge at 5. Try
%              a value of 5 to start with.
%              nCandidates - The number of suspicious superpixels to report

%
% Returns:     l - Labeled image of superpixels. Labels range from 1 to k.
%              cSP - confidence of individual super pixel
%              Sp - Superpixel attribute structure array with fields:
%                   confd_SP  - Mean confidence of initial estimation 
%                   std_confd_SP  - Standard deviation of of initial estimation
%                   dist_mask_SP  - Distance to the boundary of image mask
%                   dist_kf_SP  - Distance to the known vessel
%
% Reference: L Gu, Y Zheng, B Bise, I Sato. "Semi-Supervised Learning for
% Biomedical Image Segmentation via Forest Oriented Super Pixels(Voxels),"  MICCAI17
%

% Aug  2017


function [l, cSP,Sp] = superpxiel_forest_oriented(est_img, tbc_img, k, m, nIter)


if ~exist('nItr','var')   || isempty(nIter),     nIter = 10;     end

[rows, cols, n_trees] = size(tbc_img);

% Nominal spacing between grid elements assuming hexagonal grid
S = sqrt(rows*cols / (k * sqrt(3)/2));

% Get nodes per row allowing a half column margin at one end that alternates
% from row to row
nodeCols = round(cols/S - 0.5);
% Given an integer number of nodes per row recompute S
S = cols/(nodeCols + 0.5);

% Get number of rows of nodes allowing 0.5 row margin top and bottom
nodeRows = round(rows/(sqrt(3)/2*S));
vSpacing = rows/nodeRows;

% Recompute k
k = nodeRows * nodeCols;

% Allocate memory and initialise clusters, labels and distances.
wC = zeros(k,3);

% SP_info stores the centroid information of each super pixel

% SP_info = zeros(k,2);

LN = zeros(k,n_trees);

l = -ones(rows, cols);   % Pixel labels.

d = inf(rows, cols);     % Pixel distances from cluster centres.

% Initialise clusters on a hexagonal grid
kk = 1;

r = vSpacing/2;


% set a iteration dependent weight similar to the learning rate that varies
% with the iteration

iteration_based_weight = 1 - exp(1 : nIter) / exp(nIter);

for ri = 1 : nodeRows
    % Following code alternates the starting column for each row of grid
    % points to obtain a hexagonal pattern. Note S and vSpacing are kept
    % as doubles to prevent errors accumulating across the grid.
    if mod(ri,2)
        
        c = S/2;
        
    else
        
        c = S;
        
    end
    
    for ci = 1:nodeCols
        
        cc = round(c);
        
        rr = round(r);
        
        wC(kk,1:2) = [cc,rr];
        
        LN(kk,:) = squeeze(tbc_img(rr,cc,:));
        
        c = c + S;
        
        kk = kk + 1;
        
    end
    
    r = r + vSpacing;
    
end

% Now perform the clustering.  10 iterations is suggested but I suspect n
% could be as small as 4 or even 3
S = round(S);  % We need S to be an integer from now on

C_prev = zeros(k,nIter);

Es = zeros(nIter,1);

for n = 1:nIter
    
    t_iter = tic;
    
    SP_img = zeros(rows, cols);
    
    for kk = 1:k  % for each cluster
        
        % Get subimage around cluster
        rmin = max(wC(kk,2) - S, 1);
        
        rmax = min(wC(kk,2) + S, rows);
        
        cmin = max(wC(kk,1) - S, 1);
        
        cmax = min(wC(kk,1) + S, cols);
        
        subim1 = est_img(rmin:rmax, cmin:cmax);
        
        subim2 = tbc_img(rmin:rmax, cmin:cmax, :);
        
        assert(numel(subim1) > 0)
        
        assert(numel(subim2) > 0)
        
        
        % in the very first 1 or 2 iterations, set an object to leverage or
        % push down the estimation
        
        C_est = est_img(wC(kk, 2),wC(kk, 1));
        
        weight_iteration_factor = iteration_based_weight(n);
        
        if(C_est > 0.5)
           
            C_est = 1 - weight_iteration_factor + weight_iteration_factor * C_est;
            
        else
            
            C_est = weight_iteration_factor * C_est;
            
        end
                
        % Compute distances leaf node distribuiton D between C(kk,:) and subimage
        D = trilateral_dist(wC(kk, :),C_est,LN(kk,:),...
            subim1,subim2,rmin,cmin,S,m);
        
        % If any pixel distance from the cluster centre is less than its
        % previous value update its distance and label
        subd =  d(rmin:rmax, cmin:cmax);
        subl =  l(rmin:rmax, cmin:cmax);
        updateMask = D < subd;
        subd(updateMask) = D(updateMask);
        subl(updateMask) = kk;
        
        Es(n) = Es(n) + sum(updateMask(:));
        
        d(rmin:rmax, cmin:cmax) = subd;
        l(rmin:rmax, cmin:cmax) = subl;
        
        subS = SP_img(rmin:rmax, cmin:cmax);
        
        subS(updateMask) = C_est; 
        
        SP_img(rmin:rmax, cmin:cmax) = subS;
        
    end
    
    % Update cluster centres with mean values
    wC(:) = 0;
    
    for r = 1:rows
        
        for c = 1:cols
            
            tmp = [c,r,1];
            
            wrc = est_img(r,c);
            
            C_est = SP_img(r,c);
            
            wrc = 1 - abs(C_est - wrc);
            
            wrc = max(wrc,0.05);    
            
            tmp = tmp * wrc;
            
            wC(l(r,c),:) = wC(l(r,c),:) + tmp;
            
        end
        
    end
    
    % Divide by number of pixels in each superpixel to get mean values
    for kk = 1 : k
        
        wC(kk,1:2) = round(wC(kk,1:2) / wC(kk,3));
        
        LN(kk,:) = squeeze(tbc_img(wC(kk,2),wC(kk,1),:));
        
        C_prev(kk,n) = est_img(wC(kk,2),wC(kk,1));
        
    end
    
    
    
    
    
    % now merge the superpixels after the SLIC converges which generally
    % happens after 3 iterations
    
    if(n > 3)
        
        % now merge the super pixels
        
        % now starts merging the super pixels that are either too small or too similar
        
        merged_kk_mask = wC(:,3) < 1;
        
        for kk = 1 : k  % for each cluster
            
            if(merged_kk_mask(kk))
                
                continue;
                
            end
            
            % at first search the neighbouring area
            
            curr_sp_idx = find(l == kk);
            
            neigh_l = find_nnlabels(l,curr_sp_idx);
            
            n_neigh = length(neigh_l);
            
            est_kk = est_img(curr_sp_idx);
            
            m_est_curr = mean(est_kk);
            
            ld_est_curr = squeeze(tbc_img(wC(kk,2),wC(kk,1),:));
            
            m_est_nn = zeros(n_neigh,1);
            
            ld_est_nn = zeros(n_neigh,n_trees);
            
            for nn = 1 : n_neigh
                
                kk1 = neigh_l(nn);
                
                m_est_nn(nn) = mean(est_img(l == kk1));
                
                ld_est_nn(nn,:) = squeeze(tbc_img(wC(kk1,2),wC(kk1,1),:));
                
            end
            
            
            % caculate the distance to determine the super pixels to be merged
            
            m_est_dist = abs(m_est_nn - ones(n_neigh,1) * m_est_curr);
            
            ld_dist = ld_est_nn - repmat(ld_est_curr',[n_neigh, 1]);
            
            ld_dist = ld_dist ~= 0;
            
            ld_dist = sum(ld_dist,2);
            
            % temperarily the parameter is set as this 
            
            NN_D = m_est_dist * 100 + ld_dist * 3;
            
            % now attemp to merge the neighbouring super pixels
            
            % now merge two superpixels if their centre are of the same confidence or
            % of the same leaf index distribution
            
            merg_thres = 20;
            
            mergeMask = zeros(size(NN_D));
            
            mergeMask(NN_D < merg_thres) = 1;
            
            kk_merge = neigh_l(mergeMask > 0);
            
            for kk1 = 1 : length(kk_merge)
                
                kk2 = kk_merge(kk1);
                
                l(l == kk2) = kk;
                
            end
            
            kk_merge(kk_merge == kk) = [];
            
            % caculate the new centroid
            
            curr_sp_idx = find(l == kk);
            
            C_est = SP_img(wC(kk,2),wC(kk,1));
            
            [kkx,kky] = ind2sub([rows, cols],curr_sp_idx);
            
            wrc = est_img(curr_sp_idx);
            
            wrc = 1 - abs(C_est - wrc);
            
            wrc = max(wrc,0.05);
            
            wC(kk,:) = [sum(kky .* wrc),sum(kkx .* wrc),sum(wrc)];
            
            wC(kk,1:2) = round(wC(kk,1:2) / sum(wrc));
            
            merged_kk_mask(kk_merge) = 1;
            
        end
        
        % now reorganise the index of  the merged seeds
        
        C2newC = unique(l(:));
        
        newl = zeros(size(l));
        
        newwC = zeros(length(C2newC),3);
        
        newC_prev = zeros(length(C2newC),size(C_prev,2));
        
        
        for kk1 = 1 : length(C2newC)
            
            newl(l == C2newC(kk1)) = kk1;
            
            newwC(kk1,1:3) = wC(C2newC(kk1),:);
            
            newC_prev(kk1,:) = C_prev(C2newC(kk1),:);
            
        end
        
        
        
        wC = newwC;
        
        l = newl;
        
        C_prev = newC_prev;
        
        k = size(wC,1);
        
    end
    
    disp(['Complete Iteration ' num2str(n) ', takes ' num2str(toc(t_iter)) 'seconds']);

end


% now calculate the confidence of indivdiual superpixel

confd_SP = zeros(k,1);

std_confd_SP = zeros(k,1);


% distance to the boundary of image mask 

dist_mask_SP = zeros(k,1);


% distance to the known foreground 

dist_kf_SP = zeros(k,1);



mask = est_img < 0.01;


dist_mask = bwdist(mask);

dist_mb = bwdist(est_img > 0.8);

for kk = 1:k
    
    l_kk = find(l == kk);
    
    confd_SP(kk) = mean(abs(est_img(l_kk) - 0.5));
    
    std_confd_SP(kk) = std(est_img(l_kk));
    
    dist_mask_SP(kk) = mean(dist_mask(l_kk));
    
    dist_kf_SP(kk) = mean(dist_mb(l_kk));
    
end

cSP = confd_SP .* std_confd_SP;

Sp = struct;

Sp.confd_SP = confd_SP;

Sp.std_confd_SP = std_confd_SP;

Sp.dist_mask_SP = dist_mask_SP;

Sp.dist_kf_SP = dist_kf_SP;




end




function [D,dp,ds2] = trilateral_dist(C,C1,LN,img1,img2,r1,c1,S,m)

% Squared spatial distance
%    ds is a fixed 'image' we should be able to exploit this
%    and use a fixed meshgrid for much of the time somehow...
[rows, cols, chan] = size(img1);

[x,y] = meshgrid(c1:(c1+cols-1), r1:(r1+rows-1));

x = x - C(1);  % x and y dist from cluster centre

y = y - C(2);

ds2 = x.^2 + y.^2;


% also aims to get purier segmentation


dp = abs(img1 - C1);


%  Squared Leaf Nodse distance

LN = reshape(LN,[1,1,length(LN)]);

img2 = img2 - repmat(LN,[rows,cols,1]);

img2 = img2 ~= 0;

dl2 = sum(img2,3);



D = sqrt(dp * 100 + dl2 * 3 + ds2 / S ^ 2 * m ^ 2);

end



function neigh_l = find_nnlabels(l,curr_sp_idx)

[rows,cols] = size(l);

[nnx,nny] = ind2sub(size(l),curr_sp_idx);

nnx = repmat(nnx,8);

nny = repmat(nny,8);

nnx(:,1) = nnx(:,1) + 1;

nnx(:,2) = nnx(:,1) - 1;

nny(:,3) = nny(:,3) + 1;

nny(:,4) = nny(:,4) - 1;

nnx(:,5) = nnx(:,5) + 1;

nny(:,5) = nny(:,5) + 1;

nnx(:,6) = nnx(:,6) + 1;

nny(:,6) = nny(:,6) - 1;

nnx(:,7) = nnx(:,7) - 1;

nny(:,7) = nny(:,7) + 1;

nnx(:,8) = nnx(:,8) - 1;

nny(:,8) = nny(:,8) - 1;


nnx = min(nnx,rows);

nnx = max(nnx,1);

nny = min(nny,cols);

nny = max(nny,1);

nn_idx = sub2ind(size(l),nnx(:),nny(:));

neigh_l = l(nn_idx);

neigh_l = unique(neigh_l);


end


