function x = stylesheet
% Sets the background colors and fonts, etc. in a structure 
% that can be used by everyone
%
%% DART software - Copyright 2004 - 2013 UCAR. This open source software is
% provided by UCAR, "as is", without charge, subject to all terms of use at
% http://www.image.ucar.edu/DAReS/DART/DART_download
%
% DART $Id$

x.white       = [255/255 255/255 255/255];
x.red         = [215/255  10/255  83/255];
x.green       = [  0/255 128/255   0/255];
x.blue        = [  0/255   0/255 255/255];
x.background  = [225/255 225/255 225/255];
x.lightblue   = [0.678 0.922 1.000];

% to use a fixed-width font that looks good in any locale,
% use the case-sensitive string 'FixedWidth'
% Font names available:
% x.fontname   = 'FixedWidth';
% x.fontname   = 'Verdana';
% x.fontname   = 'Times New Roman';
% x.fontname   = 'Helvetica';  % Default
% x.fontname   = 'Verdana';

x.fontname   = 'Helvetica';
x.fontsize   = 14;  % points

% <next few lines under version control, do not edit>
% $URL$
% $Revision$
% $Date$

