! DART software - Copyright 2004 - 2013 UCAR. This open source software is
! provided by UCAR, "as is", without charge, subject to all terms of use at
! http://www.image.ucar.edu/DAReS/DART/DART_download
!
! $Id$

!> Correct covariances for fixed ensemble sizes.
!> See Anderson, J. L., 2011: Localization and Sampling Error Correction
!>   in Ensemble Kalman Filter Data Assimilation. 
!> Submitted for publication, Jan 2011.  Contact author.

!> this version is a sparse array - the ens_index array lists the ensemble
!> sizes that have been computed, using the unlimited dimension.  to generate
!> a new ensemble size, it can be added at the end of the existing arrays.

!> the initial table has the 40 sizes that the previous release of DART
!> came with.  to generate other ensemble sizes, run this program with
!> the desired ensemble sizes listed in the namelist.
!> the output file is named 'sampling_error_correction_table.nc'
!> and if one already exists, it will be appended to instead of
!> created from scratch.

!> this takes an excessive amount of time to compute for large numbers
!> of ensemble members.  it needs a couple changes - first, it could
!> be made an mpi program and compute different ensemble sizes in parallel
!> or, we could create the output only if it doesn't already exist, and
!> have it fill in specific ensemble sizes so we could generate the final
!> output file with multiple runs of this executable.
!>
!> add a namelist for min, max, or explicit ensemble size lists
!> for an 'insert a single size into an existing array' version
!> might need additional namelist values for min/max overall if making
!> the file for the first time, and setting the data for the array to
!> undefined.
!>
!> nothing to prevent this from doing both - making it an mpi program
!> and also insert into an existing table.
!>
!> code should look at nbins (which i think it already does) so that 200
!> is never hardcoded.  the SEC table could then have more or fewer entries
!> for each ensemble size.
!>

program gen_sampling_err_table

use types_mod,      only : r8
use utilities_mod,  only : error_handler, E_ERR, nc_check, file_exist,  &
                           initialize_utilities, finalize_utilities, &
                           find_namelist_in_file, check_namelist_read, &
                           do_nml_file, do_nml_term, nmlfileunit
use random_seq_mod, only : random_seq_type, init_random_seq, random_gaussian, &          
                           twod_gaussians, random_uniform

use netcdf

implicit none

! version controlled file description for error handling, do not edit
character(len=256), parameter :: source   = &
   "$URL$"
character(len=32 ), parameter :: revision = "$Revision$"
character(len=128), parameter :: revdate  = "$Date$"


integer, parameter :: num_times   = 1
! FIXME BEFORE COMMITTING, 1 of 2:
integer, parameter :: num_samples = 100000  ! for developement/debugging
!integer, parameter :: num_samples = 100000000   ! real value which should be used

! FIXME BEFORE COMMITTING, 2 of 2:
!character(len=128) :: output_filename = 'sampling_error_correction_table.nc'
! for debugging, make this short:
character(len=128) :: output_filename = 'sec.nc'
integer, parameter :: nentries = 200

integer, parameter :: MAX_LIST_LEN = 500
integer, parameter :: UNSET = -1


type (random_seq_type) :: ran_id

real(r8) :: alpha(nentries), true_correl_mean(nentries)
integer  :: bin_count(0:nentries+1)

integer, allocatable :: index_array(:)

integer  :: ncid, num_ens, esize, next_slot
integer  :: count_id, corrmean_id, alpha_id, index_id
integer  :: iunit, io

character(len=512) :: msgstring

!----------------------------------------------------------------
! namelist item(s)


integer :: ens_sizes(MAX_LIST_LEN) = UNSET
logical :: debug = .false.

namelist /gen_sampling_error_table_nml/ ens_sizes, debug


!----------------------------------------------------------------
! start of executable code

call initialize_utilities('gen_sampling_err_table')

! Read the namelist entry
call find_namelist_in_file("input.nml", "gen_sampling_error_table_nml", iunit)
read(iunit, nml = gen_sampling_error_table_nml, iostat = io)
call check_namelist_read(iunit, io, "gen_sampling_error_table_nml")

! Record the namelist values used for the run 
if (do_nml_file()) write(nmlfileunit, nml=gen_sampling_error_table_nml)
if (do_nml_term()) write(     *     , nml=gen_sampling_error_table_nml)


call init_random_seq(ran_id)

num_ens = valid_entries(ens_sizes, 3)
if (num_ens < 1) then
   call error_handler(E_ERR, 'gen_sampling_err_table', 'no valid ensemble sizes specified', &
                      source, revision, revdate, text2='check values of namelist item "ens_sizes"')
endif

if (file_exist(output_filename)) then
   ncid = setup_to_append_output_file(nentries, num_samples, count_id, corrmean_id, alpha_id, index_id, next_slot)
else
   ncid = create_output_file(nentries, num_samples, count_id, corrmean_id, alpha_id, index_id, next_slot)
endif

call validate_list(ncid, index_id, next_slot-1, index_array, num_ens, ens_sizes)

do esize=1, num_ens

   call compute_table(ens_sizes(esize), nentries, bin_count, true_correl_mean, alpha)
   call addto_output_file(ncid, next_slot, &
                          count_id, bin_count(1:nentries), &
                          corrmean_id, true_correl_mean, &
                          alpha_id, alpha, &
                          index_id, ens_sizes(esize))

   next_slot = next_slot + 1
enddo

call close_output_file(ncid)

call finalize_utilities()

! end of main program
!----------------------------------------------------------------

contains

!----------------------------------------------------------------
! main computational routine
!----------------------------------------------------------------

subroutine compute_table(this_size, nentries, bin_count, true_correl_mean, alpha)
integer,  intent(in)  :: this_size
integer,  intent(in)  :: nentries
integer,  intent(out) :: bin_count(0:nentries+1)
real(r8), intent(out) :: true_correl_mean(nentries)
real(r8), intent(out) :: alpha(nentries)


real(r8), allocatable  :: pairs(:,:), temp(:)

real(r8) :: zero_2(2) = 0.0, cov(2, 2)
real(r8) :: t_correl, sample_correl, beta
real(r8) :: s_mean(2), s_var(2), reg_mean, reg_sd, t_sd1, t_sd2
real(r8) :: tcorrel_sum(nentries), reg_sum(nentries), reg_2_sum(nentries)

integer  :: i, j, k, bin_num


write(*,*) 'computing for ensemble size of ', this_size
allocate(pairs(2, this_size), temp(this_size))

bin_count   = 0
tcorrel_sum = 0.0_r8
reg_sum     = 0.0_r8
reg_2_sum   = 0.0_r8

! Uniformly distributed sequence of true correlations  
do j = 1, num_samples
   ! Assume that true correlation is uniform [-1,1]
   t_correl = -1.0_r8 + 2.0_r8 * ((j - 1) / (num_samples - 1.0_r8))
   if(j > num_samples) t_correl = 0.0_r8

   do k = 1, num_times

      t_sd1 = 1.0_r8
      t_sd2 = 1.0_r8

      ! Generate the covariance matrix for this correlation
      cov(1, 1) = t_sd1**2
      cov(2, 2) = t_sd2**2
      cov(1, 2) = t_correl * t_sd1 * t_sd2
      cov(2, 1) = cov(1, 2)
   
      ! Loop to generate an ensemble size sample from this correl
      ! Generate a random sample of size ens_size from something with this correlation
      do i = 1, this_size
         call twod_gaussians(ran_id, zero_2, cov, pairs(:, i))
      end do
   
      ! Compute the sample correlation
      call comp_correl(pairs, this_size, sample_correl)

      ! Bin statistics for each 0.01 sample correlation bin; 
      !  start with just mean true correlation
      bin_num = (sample_correl + 1.0_r8) / 0.01_r8   + 1
      if (bin_num < 1) then
         bin_count(0) = bin_count(0) + 1
         cycle
      endif
      if (bin_num > nentries) then
         bin_count(nentries+1) = bin_count(nentries+1) + 1
         cycle
      endif

      ! Keep a sum of the sample_correl and squared to compute standard deviation
      tcorrel_sum(bin_num) = tcorrel_sum(bin_num) + t_correl
      !-----------------
      ! Also interested in finding out what the spurious variance reduction factor is
      ! First need to compute sample s.d. for the obs and unobs variable
      do i = 1, 2
         temp = pairs(i, :)
         call sample_mean_var(temp, this_size, s_mean(i), s_var(i))
      end do

      !-----------------
      reg_sum(bin_num) = reg_sum(bin_num) + t_correl * sqrt(s_var(2) / s_var(1))
      reg_2_sum(bin_num) = reg_2_sum(bin_num) + (t_correl * sqrt(s_var(2) / s_var(1)))**2

      bin_count(bin_num) = bin_count(bin_num) + 1

   end do
end do

! print out just to stdout how many counts, if any, fell below bin 0
if (debug) write(*, *) 'bin, count, mean, alpha ', 0, bin_count(0), 0, 0

! always generate exactly 'nentries' entries in the output file
do i = 1, nentries
   ! must have at least 2 counts to compute a std dev
   if(bin_count(i) <= 1) then
      write(*, *) 'Bin ', i, ' has ', bin_count(i), ' counts'
      cycle
      write(msgstring, *) 'Bin ', i, ' has ', bin_count(i), ' counts'
      call error_handler(E_ERR,'gen_sampling_err_table', msgstring, &
         source, revision, revdate, text2='All bins must have at least 2 counts')
   endif
   
   ! Compute the standard deviation of the true correlations
   true_correl_mean(i) = tcorrel_sum(i) / bin_count(i)
   reg_mean = reg_sum(i) / bin_count(i)
   reg_sd = sqrt((reg_2_sum(i) - bin_count(i) * reg_mean**2) / (bin_count(i) - 1))

   if(reg_sd <= 0.0_r8) then
      alpha(i) = 1.0_r8
   else
      !!!beta = reg_mean**2 / reg_sd**2
   ! Correct for bias in the standard deviation for very small ensembles, too 
      beta = reg_mean**2 / (reg_sd**2 * (1.0_r8 + 1.0_r8 / this_size))
      alpha(i) = beta / (1.0_r8 + beta)
   endif

   if (debug) write(*, *) 'bin, count, mean, alpha ', i, bin_count(i), true_correl_mean(i), alpha(i)
!      write(iunit, 10)   i, bin_count(i), true_correl_mean(i), alpha(i)
10 format (I4,I9,2G25.14)
end do

! print out just to stdout how many counts, if any, fell beyond bin 'nentries'
if (debug) write(*, *) 'bin, count, mean, alpha ', nentries+1, bin_count(nentries+1), 0, 0

deallocate(pairs, temp)


end subroutine

!----------------------------------------------------------------
! stat routines
!----------------------------------------------------------------

subroutine comp_correl(ens, n, correl)

integer,  intent(in)  :: n
real(r8), intent(in)  :: ens(2, n)
real(r8), intent(out) :: correl

real(r8) :: sum_x, sum_y, sum_xy, sum_x2, sum_y2


sum_x  = sum(ens(2, :))
sum_y  = sum(ens(1, :))
sum_xy = sum(ens(2, :) * ens(1, :))
sum_x2 = sum(ens(2, :) * ens(2, :))

! Computation of correlation
sum_y2 = sum(ens(1, :) * ens(1, :))

correl = (n * sum_xy - sum_x * sum_y) / &
   sqrt((n * sum_x2 - sum_x**2) * (n * sum_y2 - sum_y**2))

end subroutine comp_correl

!----------------------------------------------------------------

subroutine sample_mean_var(x, n, mean, var)

integer,  intent(in)  :: n
real(r8), intent(in)  :: x(n)
real(r8), intent(out) :: mean, var

real(r8) :: sx, s_x2

sx   = sum(x)
s_x2 = sum(x * x)
mean = sx / n
var  = (s_x2 - sx**2 / n) / (n - 1)

end subroutine sample_mean_var

!----------------------------------------------------------------
! netcdf i/o routines
!----------------------------------------------------------------

!> create a netcdf file and add some global attributes

function create_output_file(nentries, num_samples, count_id, corrmean_id, alpha_id, index_id, unlimlenp1)
integer, intent(in)  :: nentries
integer, intent(in)  :: num_samples
integer, intent(out) :: count_id
integer, intent(out) :: corrmean_id
integer, intent(out) :: alpha_id
integer, intent(out) :: index_id
integer, intent(out) :: unlimlenp1

integer :: create_output_file

integer :: rc, fid


rc = nf90_create(output_filename, NF90_CLOBBER, fid)
call nc_check(rc, 'create_output_file', 'creating '//trim(output_filename))

write(msgstring, *) 'each ensemble size entry has ', nentries, ' bins'
rc = nf90_put_att(fid, NF90_GLOBAL, 'bin_info', trim(msgstring))
call nc_check(rc, 'create_output_file', 'adding global attribute "bin_info"')

rc = nf90_put_att(fid, NF90_GLOBAL, 'num_samples', num_samples)
call nc_check(rc, 'create_output_file', 'adding global attribute "num_samples"')

call setup_output_file(fid, count_id, corrmean_id, alpha_id, index_id)

! unlimited dim initially empty, the next to be added is going to be 1
unlimlenp1 = 1

create_output_file = fid

end function create_output_file

!----------------------------------------------------------------

!> open an existing file and prepare to append to it

function setup_to_append_output_file(nentries, num_samples, count_id, corrmean_id, alpha_id, index_id, unlimlenp1)
integer, intent(in)  :: nentries
integer, intent(in)  :: num_samples
integer, intent(out) :: count_id
integer, intent(out) :: corrmean_id
integer, intent(out) :: alpha_id
integer, intent(out) :: index_id
integer, intent(out) :: unlimlenp1

integer :: setup_to_append_output_file

integer :: rc, fid, nbins, nsamp

! for netcdf, write means update 
rc = nf90_open(output_filename, NF90_WRITE, fid)
call nc_check(rc, 'setup_to_append_output_file', 'opening '//trim(output_filename))

! before we start to update this file, make sure nbins and nentries
! match the existing values in the file.
  
call get_sec_dim_info(fid, 'bins', l1=nbins)
if (nbins /= nentries) then
   write(msgstring, *) 'existing file has ', nbins, ' bins, the program has ', nentries, ' bins.'
   call error_handler(E_ERR, 'setup_to_append_output_file', 'existing file used a different bin size', &
                      source, revision, revdate, text2=msgstring)
endif

! also make sure num_samples matches
  
rc = nf90_get_att(fid, NF90_GLOBAL, 'num_samples', nsamp)
call nc_check(rc, 'open_input_file', 'getting global attribute "num_samples"')
if (nsamp /= num_samples) then
   write(msgstring, *) 'existing file uses ', nsamp, ' samples, the program has ', num_samples, ' samples.'
   call error_handler(E_ERR, 'setup_to_append_output_file', 'existing file used a different number of samples', &
                      source, revision, revdate, text2=msgstring)
endif

call get_sec_var_id(fid, 'count',          count_id)
call get_sec_var_id(fid, 'true_corr_mean', corrmean_id)
call get_sec_var_id(fid, 'alpha',          alpha_id)
call get_sec_var_id(fid, 'ens_index',      index_id)

! and finally, get the current size of the unlimited dimension and add 1
! this will be the next open slot for the unlimited dimension.
call get_sec_dim_info(fid, 'ens', l1=unlimlenp1)
unlimlenp1 = unlimlenp1 + 1


setup_to_append_output_file = fid

end function setup_to_append_output_file

!----------------------------------------------------------------

! define 2 dims and 4 arrays in output file
! counts on knowing global info
! returns 3 handles to use for the 3 arrays

subroutine setup_output_file(ncid, id1, id2, id3, id4)

integer, intent(in)  :: ncid
integer, intent(out) :: id1, id2, id3, id4

integer :: rc
integer :: nbinsDimID, nensDimID

call setup_sec_dim(ncid, 'bins', nentries, nbinsDimID)
call setup_sec_unlimdim(ncid, 'ens', nensDimID)

call setup_sec_data_int (ncid, 'count',          nbinsDimID, nensDimID, id1)
call setup_sec_data_real(ncid, 'true_corr_mean', nbinsDimID, nensDimID, id2)
call setup_sec_data_real(ncid, 'alpha',          nbinsDimID, nensDimID, id3)

call setup_sec_data_int1d (ncid, 'ens_index',                nensDimID, id4)

rc = nf90_enddef(ncid)
call nc_check(rc, 'setup_output_file', 'enddef')

end subroutine setup_output_file

!----------------------------------------------------------------

! write 3 arrays to file

subroutine addto_output_file(ncid, slot, id1, a1, id2, a2, id3, a3, id4, a4)

integer,  intent(in)  :: ncid
integer,  intent(in)  :: slot
integer,  intent(in)  :: id1
integer,  intent(in)  :: a1(:)
integer,  intent(in)  :: id2
real(r8), intent(in)  :: a2(:)
integer,  intent(in)  :: id3
real(r8), intent(in)  :: a3(:)
integer,  intent(in)  :: id4
integer,  intent(in)  :: a4

call write_sec_data_int   (ncid, slot, 'count',          id1, a1)
call write_sec_data_real  (ncid, slot, 'true_corr_mean', id2, a2)
call write_sec_data_real  (ncid, slot, 'alpha',          id3, a3)
call write_sec_data_int1d (ncid, slot, 'ens_index',      id4, a4)

end subroutine addto_output_file

!----------------------------------------------------------------

subroutine close_output_file(ncid)

integer, intent(in) :: ncid

integer :: rc

rc = nf90_sync(ncid)
call nc_check(rc, 'close_output_file', 'syncing '//trim(output_filename))

rc = nf90_close(ncid)
call nc_check(rc, 'close_output_file', 'closing '//trim(output_filename))

end subroutine close_output_file

!----------------------------------------------------------------

!----------------------------------------------------------------
! helper routines for above code
!----------------------------------------------------------------

!----------------------------------------------------------------

! define a dimension with name and a length and return the id

subroutine setup_sec_dim(ncid, c1, n1, id1)

integer,          intent(in)  :: ncid
character(len=*), intent(in)  :: c1
integer,          intent(in)  :: n1
integer,          intent(out) :: id1

integer :: rc

rc = nf90_def_dim(ncid, name=c1, len=n1, dimid=id1)
call nc_check(rc, 'setup_sec_dim', 'adding dimension '//trim(c1))

end subroutine setup_sec_dim

!----------------------------------------------------------------

! define an unlimited dimension and return the id

subroutine setup_sec_unlimdim(ncid, c1, id1)

integer,          intent(in)  :: ncid
character(len=*), intent(in)  :: c1
integer,          intent(out) :: id1

integer :: rc

rc = nf90_def_dim(ncid, name=c1, len=NF90_UNLIMITED, dimid=id1)
call nc_check(rc, 'setup_sec_unlimdim', 'adding dimension '//trim(c1))

end subroutine setup_sec_unlimdim

!----------------------------------------------------------------

! given a name, return id for a 2d integer array

subroutine setup_sec_data_int(ncid, c1, d1, d2, id1)

integer,          intent(in)  :: ncid
character(len=*), intent(in)  :: c1
integer,          intent(in)  :: d1, d2
integer,          intent(out) :: id1

integer :: rc

rc = nf90_def_var(ncid, name=c1, xtype=nf90_int, dimids=(/ d1, d2 /), varid=id1)
call nc_check(rc, 'setup_sec_data', 'defining variable '//trim(c1))

end subroutine setup_sec_data_int

!----------------------------------------------------------------

! given a name, return id for a 1d integer array

subroutine setup_sec_data_int1d(ncid, c1, d1, id1)

integer,          intent(in)  :: ncid
character(len=*), intent(in)  :: c1
integer,          intent(in)  :: d1
integer,          intent(out) :: id1

integer :: rc

rc = nf90_def_var(ncid, name=c1, xtype=nf90_int, dimids=(/ d1 /), varid=id1)
call nc_check(rc, 'setup_sec_data', 'defining variable '//trim(c1))

end subroutine setup_sec_data_int1d

!----------------------------------------------------------------

! given a name, return id for a 2d real array

subroutine setup_sec_data_real(ncid, c1, d1, d2, id1)

integer,          intent(in)  :: ncid
character(len=*), intent(in)  :: c1
integer,          intent(in)  :: d1, d2
integer,          intent(out) :: id1

integer :: rc

rc = nf90_def_var(ncid, name=c1, xtype=nf90_double, dimids=(/ d1, d2 /), varid=id1)
call nc_check(rc, 'setup_sec_data', 'defining variable '//trim(c1))

end subroutine setup_sec_data_real

!----------------------------------------------------------------

subroutine write_sec_data_int(ncid, col, c1, id1, a1)

integer,          intent(in) :: ncid
integer,          intent(in) :: col
character(len=*), intent(in) :: c1
integer,          intent(in) :: id1
integer,          intent(in) :: a1(:)

integer :: rc

rc = nf90_put_var(ncid, id1, a1, start=(/ 1, col /), count=(/ size(a1), 1 /) )
call nc_check(rc, 'write_sec_data', 'writing variable "'//trim(c1)//'"')

end subroutine write_sec_data_int

!----------------------------------------------------------------

subroutine write_sec_data_int1d(ncid, col, c1, id1, a1)

integer,          intent(in) :: ncid
integer,          intent(in) :: col
character(len=*), intent(in) :: c1
integer,          intent(in) :: id1
integer,          intent(in) :: a1

integer :: rc

rc = nf90_put_var(ncid, id1, a1, start=(/ col /))
call nc_check(rc, 'write_sec_data', 'writing variable "'//trim(c1)//'"')

end subroutine write_sec_data_int1d

!----------------------------------------------------------------

subroutine write_sec_data_real(ncid, col, c1, id1, a1) 
integer,          intent(in) :: ncid
integer,          intent(in) :: col
character(len=*), intent(in) :: c1
integer,          intent(in) :: id1
real(r8),         intent(in) :: a1(:)

integer :: rc

rc = nf90_put_var(ncid, id1, a1, start=(/ 1, col /), count=(/ size(a1), 1 /) )
call nc_check(rc, 'write_sec_data', 'writing variable "'//trim(c1)//'"')

end subroutine write_sec_data_real

!----------------------------------------------------------------

subroutine read_sec_data_int(ncid, col, c1, id1, a1)

integer,          intent(in)  :: ncid
integer,          intent(in)  :: col
character(len=*), intent(in)  :: c1
integer,          intent(in)  :: id1
integer,          intent(out) :: a1(:)

integer :: rc

rc = nf90_get_var(ncid, id1, a1, start=(/ 1, col /), count=(/ size(a1), 1 /) )
call nc_check(rc, 'read_sec_data', 'reading variable "'//trim(c1)//'"')

end subroutine read_sec_data_int

!----------------------------------------------------------------

subroutine read_sec_data_real(ncid, col, c1, id1, a1) 
integer,          intent(in)  :: ncid
integer,          intent(in)  :: col
character(len=*), intent(in)  :: c1
integer,          intent(in)  :: id1
real(r8),         intent(out) :: a1(:)

integer :: rc

rc = nf90_get_var(ncid, id1, a1, start=(/ 1, col /), count=(/ size(a1), 1 /) )
call nc_check(rc, 'read_sec_data', 'reading variable "'//trim(c1)//'"')

end subroutine read_sec_data_real

!----------------------------------------------------------------

! retrieve either the length of a dimension, the dim id, or both

subroutine get_sec_dim_info(ncid, c1, l1, id1)

integer,           intent(in)  :: ncid
character(len=*),  intent(in)  :: c1
integer, optional, intent(out) :: l1
integer, optional, intent(out) :: id1

integer :: rc, ll1, lid1

rc = nf90_inq_dimid(ncid, c1, lid1)
call nc_check(rc, 'get_sec_dim_info', 'querying dimension '//trim(c1))

rc = nf90_inquire_dimension(ncid, lid1, len=ll1)
call nc_check(rc, 'get_sec_dim_info', 'querying dimension '//trim(c1))

if (present(l1)) l1 = ll1
if (present(id1)) id1 = lid1

end subroutine get_sec_dim_info


!----------------------------------------------------------------

! retrieve the variable id

subroutine get_sec_var_id(ncid, c1, id1)

integer,           intent(in)  :: ncid
character(len=*),  intent(in)  :: c1
integer,           intent(out) :: id1

integer :: rc

rc = nf90_inq_varid(ncid, c1, id1)
call nc_check(rc, 'get_sec_var_id', 'querying variable '//trim(c1))

end subroutine get_sec_var_id


!----------------------------------------------------------------
! misc utility routines
!----------------------------------------------------------------

! figure out the list length.  -1 means no entries; a minimum
! valid value can be specfied and is a fatal error if an entry
! is below the threshold.

function valid_entries(list, min_valid)
integer, intent(in) :: list(:)
integer, intent(in) :: min_valid
integer :: valid_entries

integer :: i, val

val = -1
do i=1, MAX_LIST_LEN
   if (list(i) == UNSET) exit

   if (list(i) < min_valid) then
      write(msgstring, *) 'minimum valid value is ', min_valid
      call error_handler(E_ERR, 'valid_entries', 'illegal value found in list', &
                         source, revision, revdate, text2=msgstring)
   endif

   val = i
enddo

valid_entries = val

end function valid_entries

!----------------------------------------------------------------

! if this routine returns, index_array is allocated and filled
! and none of the new ens_sizes() values are already in the list.
! any errors here are fatal.

subroutine validate_list(fid, indx_id, current_size, index_array, num_ens, ens_sizes)
integer,              intent(in) :: fid
integer,              intent(in) :: indx_id
integer,              intent(in) :: current_size
integer, allocatable, intent(out) :: index_array(:)
integer,              intent(in) :: num_ens
integer,              intent(in) :: ens_sizes(:)

integer :: i, j

! if there's no existing list, no chance of duplicated values.
! just copy over the requested size list and return.

if (current_size == 0) then
   allocate(index_array(num_ens))
   index_array(:) = ens_sizes(1:num_ens)
   return
endif

! ok, there's an existing list.  make sure there are no
! replicated sizes.  we could skip or replace them, but for
! now it's an error to respecify an existing size.

! allocate it large enough to hold the eventual output size
allocate(index_array(current_size+num_ens))
call read_sec_data_int(fid, current_size, 'ens_index', indx_id, index_array(1:current_size))

do i = 1, current_size
   do j = 1, num_ens
      if (index_array(i) == ens_sizes(j)) then
         write(msgstring, *) 'existing index ', i, ' and new list index ', j, ' both have ensemble size ', index_array(i)
         call error_handler(E_ERR, 'validate list', 'duplicate ensemble size found', &
                            source, revision, revdate, text2=msgstring)
      endif
   enddo
enddo

! add the new sizes to the end of the list and return
index_array(current_size+1:current_size+num_ens) = ens_sizes(1:num_ens)

end subroutine validate_list

!----------------------------------------------------------------

end program gen_sampling_err_table

! <next few lines under version control, do not edit>
! $URL$
! $Id$
! $Revision$
! $Date$
