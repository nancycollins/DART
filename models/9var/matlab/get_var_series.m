%GET_VAR_SERIES Gets a particular copy of a state variable from netcdf file

% Retrieves a particular copy of a state variable from a file whose
% full or relative path is specified in the file argument.
% NEED TO DEAL WITH ERRORS.

function var_vec = get_var_series(var, copy, fname)

% Need to get a copy with the label copy
copy_meta_data = getnc(fname, 'CopyMetaData');
% For a single copy, the size is nx1, for more k copies, it's kxn
if size(copy_meta_data, 2) == 1
   copy_meta_data = transpose(copy_meta_data);
end
num_copies = size(copy_meta_data, 1);

% Get only the appropriate copy of the state and return
% Should have an error check for bad indices
if num_copies == 1
   var_vec = getnc(fname, 'state', [-1, copy, var], [-1, copy, var]);
else
   var_vec = getnc(fname, 'state', [-1, copy, var], [-1, copy, var]);
end

