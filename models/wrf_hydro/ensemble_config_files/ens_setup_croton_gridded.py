
# m=wrf_hydro_ens_sim.members[0]
# dir(m)

# Change restart frequency to hourly in hydro namelist
att_tuple = ('base_hydro_namelist', 'hydro_nlist', 'rst_dt')
# The values can be a scalar (uniform across the ensemble) or a list of length N (ensemble size).
values = 60
wrf_hydro_ens_sim.set_member_diffs(att_tuple, values)
wrf_hydro_ens_sim.member_diffs # wont report any values uniform across the ensemble
# but this will:
[mm.base_hydro_namelist['hydro_nlist']['rst_dt'] for mm in wrf_hydro_ens_sim.members]

# Change restart frequency to hourly in hrldas namelist
att_tuple = ('base_hrldas_namelist', 'noahlsm_offline', 'restart_frequency_hours')
values = 1
wrf_hydro_ens_sim.set_member_diffs(att_tuple, values)
[mm.base_hrldas_namelist['noahlsm_offline']['restart_frequency_hours'] for mm in wrf_hydro_ens_sim.members]

# Change model advance to 1 hour in hrldas namelist
# This is governed by the configuration namelist setting:
# run_experiment:  time:  advance_model_hours: 



# No other differences across the ensemble, only the FORCING dir for each
# will be set at run time by the noise_model.

# We could to parameter differences here.
