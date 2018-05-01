function [] = build_shorelineset()

    clear variables; 
    close all;

    % directory of the data folder (relative or absolute path to the folder)
    % alternatively use cd <path to location> to execute elsewhere
    directory = '../data';

    % create the list of folders to loop through
    listing = dir(directory); % all items in directory
    listing(ismember( {listing.name}, {'.', '..'})) = [];  % dont want . or ..
    direcoriesBool = [listing.isdir]; % logical of directories only
    folders = cellstr(  vertcat( listing(direcoriesBool).name )  ); % list of folder names only
    countfolders = length(folders);
    
    % initialize some lists
    names = cell(countfolders,1);       % name of images
    dates = cell(countfolders,1);       % dates of images
    clouds = NaN(countfolders,1);       % cloud % of images
    outputs = NaN(countfolders,8);      % output dataset
    
    deltaULcoord = [633497, 4236964]; % apex of the delta for cropping
    deltacropDim = [3975, 3790];
    deltaLRcoord = [713380, 4162227];
    deltaLLcoord = [deltaULcoord(1), deltaLRcoord(2)];

    % loop through all the folder first to generate some metadata for sorting
    % sort is important for making a movie
    [sortidx, meta_sort] = get_sortorder(folders, countfolders, directory);
    folders_sort = folders(sortidx); % rearange folders into this order for main loop
    
    % main image --> shoreline processing code
    for i = 1:countfolders
        disp( ['operating on image folder: ', num2str(i), ' of ', num2str(countfolders)] )
        
        clear shoreline
        
        meta = meta_sort{i};
        [bandset] = set_bandset(meta.mission); % return bands to use as [thresh, R, G, B]
        
        thresh_img = imread(char(strcat('./', imagefolder, '_B', bandset(1), '.TIF')));
        
        [shoreline_idx, thresh_crop] = process(thresh_img,meta.ULcoord, deltaULcoord, deltaLRcoord, meta.res);       
        
        ymax = max(shoreline_idx(:,2));
        shoreline(:, 1) = (shoreline_idx(:, 1).*meta.res) + repmat(deltaLLcoord(1), size(shoreline_idx, 1), 1);
        shoreline(:, 2) = ((ymax - shoreline_idx(:, 2)).*meta.res) + repmat(deltaLLcoord(2), size(shoreline_idx, 1), 1);
        
        [fig] = make_plot(thresh_crop, shoreline_idx, i, meta);
        savename = sprintf('./fig_output/fig%03d.png', i);
        pause(0.2)
        print(fig, savename, '-dpng', '-r200', '-opengl') % save file
        close(fig)
        
        outputname = strcat('/home/andrew/Dropbox/yellow_river/data/shorelines/auto_shoreline/shoreline_', datestr(meta.date, 'YYYY-mm-dd'), '.csv');
        fid = fopen(outputname, 'w');
        fprintf(fid, 'X, Y\n');
        fclose(fid);
        dlmwrite(outputname, ...
            shoreline, '-append', 'precision', '%f');
    end
    
    save('/home/andrew/Dropbox/yellow_river/data/shorelines/deltaLLcoord.mat', 'deltaLLcoord')
end

function [sortidx, meta_sort] = get_sortorder(folders, countfolders, directory)
    % sort the folders for processing in order,
    % this is needed for making a movie while processing if desired
    
    % initialize
    dates = NaN(countfolders, 1); 
    
    % loop through to get metadata
    for i = 1:countfolders
        % concatenate to build the present folder and metadata file info
        imagefolder = fullfile(directory, folders(i)); 
        imagemetafile = fullfile(imagefolder, strcat(folders(i), '_MTL.txt'));
        fidmetadata = fopen(char(imagemetafile)); % fid of metadata file
        
        % process the file to extract the metadata
        [meta{i, 1}] = get_metadata(fidmetadata);
        
        % date is what we're after for sorting
        dates(i) = meta{i}.date;
    end
    
    % perform the sort
    [~, sortidx] = sort(dates);
    [meta_sort] = meta(sortidx);
end

function  [fig] = make_plot(thresh_img, shoreline, i, meta)
    fig = figure();
    imshow(thresh_img)
    hold on
    plot(shoreline(:, 1), shoreline(:, 2), '.', 'Color', [1 0 0])
    title(datestr(meta.date));
    drawnow
end

function [shoreline, thresh_crop] = process(thresh_image,  ULcoord, cropULcoord, cropLRcoord, resolution)
    [cropDim] =  get_cropDim(cropULcoord, cropLRcoord, resolution);
    [thresh_crop_raw] = crop_image(thresh_image, ULcoord, cropULcoord, cropDim, resolution);
    thresh_crop = imadjust(thresh_crop_raw, stretchlim(thresh_crop_raw), [0 1], 1);
    [thresh] = get_threshold(thresh_crop);
    [crop_close, crop_edge] = find_shoreline(thresh_crop, thresh);
    [row, col] = find(crop_edge);
    shoreline = horzcat(col, row);
end

function [cropDim] = get_cropDim(ULcoord, LRcoord, res)
    xDim = (LRcoord(1) - ULcoord(1)) / res; % x
    yDim = (ULcoord(2) - LRcoord(2)) / res; % y
    cropDim = [xDim yDim];
end

function [crop_img] = crop_image(image, ULcoord, cropULcoord, cropDim, resolution)
    ULidx = [(cropULcoord(1)-ULcoord(1)), (ULcoord(2)-cropULcoord(2))] ./ resolution; % WILL NOT WORK BECAUSE SPACING CHANGES???
    crop_img = imcrop(image, [ULidx(1) ULidx(2) cropDim(1) cropDim(2)]);
end

function [img_close, img_edge] = find_shoreline(img, thresh)
    % main shoreline extraction method descibed in Moodie et al.

    img_bw = im2bw(img, thresh);                        % threshold image
    img_fill = imfill(img_bw, 'holes');                 % fill it from the outside
    img_rms = ~bwareaopen(~img_fill, 30000);            % remove small isolated water-on-land objects
    img_rms2 = bwareaopen(img_rms, 500);                % remove small isolated land-in-water objects %%%%%%%% 2000
    img_structel = strel('disk', 5);                    % build structural object (something like a filter) of ('shape', size)
    img_open = imopen(img_rms2, img_structel);          % morphological closure with structure
    img_structel2 = strel('disk', 50);                  % build structural object (something like a filter) of ('shape', size)
    img_close = imclose(img_open, img_structel2);       % morphological closure with structure
    img_rms3 = bwareaopen(img_close, 10000);            % remove small isolated land-in-water objects
    img_pad = padarray(img_rms3, [1 0], 1, 'post');     % add row to end
    img_pad = padarray(img_pad, [0 1], 1, 'pre');       % add col to front
    img_fill2 = imfill(img_pad, 'holes');               % fill it from the outside
    img_unpad = img_fill2(1:end-1, 2:end);
    img_fill3 = bwareafilt(img_unpad, 1, 'largest');    % retain only largest 
    img_edge = edge(img_fill3, 'sobel');                % find edge
    
    fig = figure();
    subplot(2,3,1)
    name = 'raw image';
        imshow(img)
        title(name)
    subplot(2,3,2)
    name = 'apply threshold';
        imshow(img_bw)
        title(name)
    subplot(2,3,3)
    name = 'flood pixels';
        imshowpair(img_bw, img_fill)
        title(name)
    subplot(2,3,4)
    name = 'remove small objects';
        imshowpair(img_fill, img_rms2)
        title(name)
    subplot(2,3,5)
    name = 'morphological open and close';
        imshowpair(img_rms2, img_close)
        title(name)
    subplot(2,3,6)
    name = 'extract shoreline';
        imshow(img)
        hold on
        [row, col] = find(img_edge);
        shoreline = horzcat(col, row);
        plot(shoreline(:,1), shoreline(:,2), 'r.')
        title(name)
end

function [bandset] = set_bandset(mission)
    switch mission
        case {'LANDSAT_1', 'LANDSAT_2', 'LANDSAT_3'}
            bandset = ['7' '6' '5' '4'];
        case {'LANDSAT_4', 'LANDSAT_5'}
            bandset = ['7' '3' '2' '1'];
        case 'LANDSAT_7'
            bandset = ['7' '3' '2' '1'];
        case 'LANDSAT_8'
            bandset = ['7' '4' '3' '2'];
    end
%     bandset = ['4' '4' '3' '2'];
end

function [meta] = get_metadata(fidmetadata)
    metadata = textscan(fidmetadata, '%s','delimiter', '\n');
    
    date.idx = find(~cellfun(@isempty,strfind(metadata{1,1}, 'DATE_ACQUIRED')) == 1);
    date.str = metadata{1,1}(date.idx);
    date.splt = strsplit(char(date.str),'=');
    date.val = datenum(date.splt(2));
    meta.date = date.val;
    
    clouds.idx = find(~cellfun(@isempty,strfind(metadata{1,1}, 'CLOUD_COVER')) == 1, 1);
    clouds.str = metadata{1,1}(clouds.idx);
    clouds.splt = strsplit(char(clouds.str),'=');
    clouds.val = str2num(char(clouds.splt(2)));
    meta.clouds = clouds.val; 
    
    ULXcoord.idx = find(~cellfun(@isempty,strfind(metadata{1,1}, 'CORNER_UL_PROJECTION_X_PRODUCT')) == 1);
    ULXcoord.str = metadata{1,1}(ULXcoord.idx);
    ULXcoord.splt = strsplit(char(ULXcoord.str),'=');
    ULXcoord.val = str2num(char(ULXcoord.splt(2)));
    ULYcoord.idx = find(~cellfun(@isempty,strfind(metadata{1,1}, 'CORNER_UL_PROJECTION_Y_PRODUCT')) == 1);
    ULYcoord.str = metadata{1,1}(ULYcoord.idx);
    ULYcoord.splt = strsplit(char(ULYcoord.str),'=');
    ULYcoord.val = str2num(char(ULYcoord.splt(2)));
    meta.ULcoord = [ULXcoord.val, ULYcoord.val];
    
    mission.idx = find(~cellfun(@isempty,strfind(metadata{1,1}, 'SPACECRAFT_ID')) == 1);
    mission.str = metadata{1,1}(mission.idx);
    mission.splt = strsplit(char(mission.str),'=');
    mission.name = strrep(mission.splt(2), '"', '');
    mission.val = char(strrep(mission.name, ' ', ''));
    meta.mission = mission.val;
    
    res.idx = find(~cellfun(@isempty,strfind(metadata{1,1}, 'GRID_CELL_SIZE_REFLECTIVE')) == 1);
    res.str = metadata{1,1}(res.idx);
    res.splt = strsplit(char(res.str),'=');
    res.val = str2double(char(strrep(res.splt(2), ' ', '')));
    meta.res = res.val;
    
    name.idx = find(~cellfun(@isempty,strfind(metadata{1,1}, 'LANDSAT_SCENE_ID')) == 1);
    name.str = metadata{1,1}(name.idx);
    name.splt = strsplit(char(name.str),'=');
    name.name = strrep(name.splt(2), '"', '');
    name.val = char(strrep(name.name, ' ', ''));
    meta.name = name.val;
    
    % need to pass into here the arguments for the folder path. Could pass name too?
    % any way to put this crap into function to take a name and datatype and return that?
end

function [thresh] = get_threshold(img)
    img = im2double(img);
    img_long = reshape(img, size(img,1) * size(img,2), 1);
    [Hcount, Hbin] = histcounts(img_long, 40);
    dx = Hbin(2) - Hbin(1);
    dcdx = (Hcount(2:end) - Hcount(1:end-1)) ./ dx;
    [maxy, maxidx] = max(Hcount);
    range = [maxidx find(dcdx(maxidx:end)>=0, 1, 'first')+maxidx-2];
    m = mean(dcdx(range(1):range(2)));
    maxx = maxidx*dx;
    yint = maxy - (m * (maxx));
    xint = (-1*yint)/m;
    thresh = xint;
end