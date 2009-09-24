function[x_new, time_new] = lorenz_96_adv_1step(x, time)
% Does a single time step advance for lorenz_96 40-variable model using four step runge-kutta time step
%
% x is the 40-vector state, time is the 2-vector days and seconds time

% Data Assimilation Research Testbed -- DART
% Copyright 2004-2009, Data Assimilation Research Section
% University Corporation for Atmospheric Research
% Licensed under the GPL -- www.gpl.org/licenses/gpl.html
%
% <next few lines under version control, do not edit>
% $URL$
% $Id$
% $Revision$
% $Date$

global DELTA_T

% Compute first intermediate step
dx = comp_dt(x);
x1 = DELTA_T * dx;
inter = x + x1 / 2;

% Compute second intermediate step
dx = comp_dt(inter);
x2 = DELTA_T * dx;
inter = x + x2 / 2;

% Compute third intermediate step
dx = comp_dt(inter);
x3 = DELTA_T * dx;
inter = x + x3;

% Compute fourth intermediate step
dx = comp_dt(inter);
x4 = DELTA_T * dx;

% Compute new value for x
x_new = x + x1/6 + x2/3 + x3/3 + x4/6;

% Increment time step
time_new = time + 1;


end

%------------------------------------------------------------------------------

function[dt] = comp_dt(x)

global FORCING
global MODEL_SIZE

for j = 1:MODEL_SIZE
   jp1 = j + 1;
   if(jp1 > MODEL_SIZE) jp1 = 1; end
   jm2 = j - 2;
   if(jm2 < 1) jm2 = MODEL_SIZE + jm2; end
   jm1 = j - 1;
   if(jm1 < 1) jm1 = MODEL_SIZE; end

   dt(j) = (x(jp1) - x(jm2)) * x(jm1) - x(j) + FORCING;
end

end
