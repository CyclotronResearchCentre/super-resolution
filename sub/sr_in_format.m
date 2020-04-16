function in = sr_in_format(in,opt)

% ----------------------------
% Convert to cell of contrasts
in = any2cell(in);

slice = cell(1,numel(in));
[slice{:}] = deal(struct('thickest',[],'other',[],'gap',[],'accumulate',[]));
for k=1:numel(in)
    if iscell(opt.slice.thickest)
        slice{k}.thickest = opt.slice.thickest{k};
    else
        slice{k}.thickest = opt.slice.thickest;
    end
    if iscell(opt.slice.other)
        slice{k}.other = opt.slice.other{k};
    else
        slice{k}.other = opt.slice.other;
    end
    if iscell(opt.slice.gap)
        slice{k}.gap = opt.slice.gap{k};
    else
        slice{k}.gap = opt.slice.gap;
    end
    if iscell(opt.slice.accumulate)
        slice{k}.accumulate = opt.slice.accumulate{k};
    else
        slice{k}.accumulate = opt.slice.accumulate;
    end
end

% -----------------------------------------------
% Convert to cell of repeats and format as struct
for k=1:numel(in)
    qin  = any2cell(in{k}); % We pop elements from the top of the queue
    qout = {};              % We push elements to the bottom of the queue
    while ~isempty(qin)
        i                 = numel(qout)+1;
        slice1            = slice{k};
        slice1.thickest   = slice1.thickest(min(numel(slice1.thickest),i));
        slice1.other      = slice1.other(min(numel(slice1.other),i));
        slice1.gap        = slice1.gap(min(numel(slice1.gap),i));
        slice1.accumulate = slice1.accumulate(min(numel(slice1.accumulate),i));
        [elem,qin] = cellpop(qin);                   % Pop first element
        elem       = formatdat(elem, opt, slice1);   % Format as (cell of) struct
        qout       = cellpush(qout, elem);           % Push formatted element
    end
    in{k}  = qout;
end

% ------------
% Estimate SNR
info = [];
for k=1:numel(in)
    for r=1:numel(in{k})
        [s,mu,info1] = sr_noise_estimate(in{k}{r}.dat);
        in{k}{r}.lam = 1./s^2;
        in{k}{r}.mu  = mu;
        if isempty(info)
            info = info1;
        else
            info = horzcat(info, info1);
        end
    end
end
if opt.verbose > 1
    figname = '[sr] noise estimate';
    f = findobj('Type', 'Figure', 'Name', figname);
    if isempty(f)
        f = figure('Name', figname, 'NumberTitle', 'off');
    end
    set(0, 'CurrentFigure', f);   
    clf(f);
    for i=1:numel(info)
        subplot(1,numel(info),i);
        plot(info(i).x(:),info(i).p,'--',info(i).x(:), ...
             info(i).h/sum(info(i).h)/info(i).md,'b.', ...
             info(i).x(:),info(i).sp,'r');
    end
    drawnow
end

% -------------------------------------------------------------------------
function in = any2cell(in)
% Convert any struct-like object to a cell of objects.
if ischar(in)
    in = num2cell(in, 2);
elseif isstring(in) || isa(in, 'nifti')
    in = num2cell(in);
elseif isa(in, 'file_array') || isnumeric(in)
    in = num2cell(in, [1 2 3]);
end
if ~iscell(in), error('Unknown input class %s', class(in)); end
in = in(:)';
% -------------------------------------------------------------------------
function [elem,in] = cellpop(in)
% Pop (= return and delete) first element of a cell array.
elem  = in{1};
in(1) = [];
% -------------------------------------------------------------------------
function in = cellpush(in, sub)
% Push (= append at the end) element in a cell array.
if ~iscell(sub), sub = {sub}; end
in = [in sub];
% -------------------------------------------------------------------------
function out = formatdat(in, opt, slice)
% Convert filename/nifti/array to (cell of) structure with proper fields.
if ischar(in) || isstring(in)
    in = nifti(in);
end
out = {};
if isa(in, 'nifti')
    for n=1:numel(in)
        nii = in(n);
        if numel(in.dat.dim) >= 4 && size(in,4) == 1
            in.dat.dim(4) = [];
        end
        lat = [in.dat.dim 1];
        lat = lat(1:3);
        for k=1:size(in.dat,4)
            elem                = struct;
            elem.dat            = nii.dat;
            elem.dim            = [elem.dat.dim 1];
            elem.dim            = elem.dim(1:3);
            elem.dat.offset     = elem.dat.offset + prod(lat)*(k-1)*dtype2size(elem.dat.dtype);
            elem.dat.permission = 'ro';
            elem.mat0           = nii.mat;
            elem.mat            = elem.mat0;
            elem.mat0           = nii.mat;
            elem.var            = dtype2var(elem.dat.dtype, elem.dat.scl_slope);
            out{end+1}          = elem;
        end
    end
elseif isa(in, 'file_array')
    if numel(in.dim) > 3
        error('Cannot deal with file arrays that are not 3D.');
    end
    elem                = struct;
    elem.dat            = in;
    elem.dim            = [elem.dat.dim 1];
    elem.dim            = elem.dim(1:3);
    elem.dat.permission = 'ro';
    elem.mat0           = opt.input.mat;
    elem.mat            = elem.mat0;
    elem.var            = dtype2var(elem.dat.dtype, elem.dat.scl_slope);
    out{end+1}          = elem;
elseif isnumeric(in)
    in = reshape(in, size(in,1), size(in,2), size(in,3), []);
    for k=1:size(in,4)
        elem                = struct;
        elem.dat            = in(:,:,:,k);
        elem.dim            = [size(in) 1];
        elem.dim            = elem.dim(1:3);
        elem.mat0           = opt.input.mat;
        elem.mat            = elem.mat0;
        elem.var            = dtype2var(class(in));
        out{end+1}          = elem;
        
    end
end
% Set slice profile
if lower(opt.mode(1)) == 's'
    for k=1:numel(out)
        elem = out{k};
        vs = sqrt(sum(elem.mat(1:3,1:3).^2));
        if any(abs(vs-mean(vs))/mean(vs) > 0.1)
            isthick = (vs == max(vs));
        else
            isthick = false(1,3);
        end
        elem.slice.profile           = zeros(1,3);
        elem.slice.profile(isthick)  = slice.thickest;
        elem.slice.profile(~isthick) = slice.other;
        elem.slice.gap               = zeros(1,3);
        elem.slice.gap(isthick)      = slice.gap;
        elem.slice.accumulate        = slice.accumulate;
        out{k} = elem;
    end
end
% -------------------------------------------------------------------------
function n = dtype2size(dtype)
% Guess element size (in bytes ) from data type.
dtype = split(dtype, '-');
dtype = dtype{1};
switch lower(dtype)
    case {'binary'}
        n = 1/8;
    case {'uint8' 'int8' 'unknown'}
        n = 1;
    case {'uint16' 'int16'}
        n = 2;
    case {'uint32' 'int32' 'float32'}
        n = 4;
    case {'uint64' 'int64' 'float64' 'complex64'}
        n = 8;
    case {'float128' 'complex128'}
        n = 16;
    case {'complex256'}
        n = 32;
end
% -------------------------------------------------------------------------
function var = dtype2var(dtype, scl)
% Compute observation uncertainty from data type.
if nargin < 2, scl = 1; end
dtype = split(dtype, '-');
dtype = dtype{1};
switch lower(dtype)
    case {'unknown' 'uint8' 'int8' 'uint16' 'int16' 'uint32' 'int32' 'uint64' 'int64'}
        var = scl^2/12;
    otherwise
        var = 0;
end