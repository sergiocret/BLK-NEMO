MODULE lib_fortran
   !!======================================================================
   !!                       ***  MODULE  lib_fortran  ***
   !! Fortran utilities:  includes some low levels fortran functionality
   !!======================================================================
   !! History :  3.2  !  2010-05  (M. Dunphy, R. Benshila)  Original code
   !!            3.4  !  2013-06  (C. Rousset)  add glob_min, glob_max 
   !!                                           + 3d dim. of input is fexible (jpk, jpl...) 
   !!            4.0  !  2016-06  (T. Lovato)  double precision global sum by default 
   !!----------------------------------------------------------------------

   !!----------------------------------------------------------------------
   !!   glob_sum    : generic interface for global masked summation over
   !!                 the interior domain for 1 or 2 2D or 3D arrays
   !!                 it works only for T points
   !!   SIGN        : generic interface for SIGN to overwrite f95 behaviour
   !!                 of intrinsinc sign function
   !!----------------------------------------------------------------------
   USE par_oce         ! Ocean parameter
   USE dom_oce         ! ocean domain
   USE domutl, ONLY : is_tile
   USE in_out_manager  ! I/O manager
   USE lib_mpp         ! distributed memory computing
   USE lbclnk          ! ocean lateral boundary conditions

   IMPLICIT NONE
   PRIVATE

   PUBLIC   glob_sum      ! used in many places (masked with tmask_i = ssmask * (excludes halo+duplicated points (NP folding)) )
   PUBLIC   local_sum     ! used in trcrad, local operation before glob_sum_delay
   PUBLIC   sum3x3        ! used in trcrad, do a sum over 3x3 boxes
   PUBLIC   DDPDD         ! also used in closea module
   PUBLIC   glob_min, glob_max
   PUBLIC   glob_sum_vec
   PUBLIC   glob_min_vec, glob_max_vec
#if defined key_nosignedzero
   PUBLIC SIGN
#endif

   INTERFACE glob_sum
      MODULE PROCEDURE glob_sum_0d, glob_sum_1d, glob_sum_2d, glob_sum_3d
   END INTERFACE
   INTERFACE local_sum
      MODULE PROCEDURE local_sum_2d, local_sum_3d
   END INTERFACE
   INTERFACE sum3x3
      MODULE PROCEDURE sum3x3_2d, sum3x3_3d
   END INTERFACE
   INTERFACE glob_min
      MODULE PROCEDURE glob_min_2d, glob_min_3d
   END INTERFACE
   INTERFACE glob_max
      MODULE PROCEDURE glob_max_2d, glob_max_3d
   END INTERFACE
   INTERFACE glob_sum_vec
      MODULE PROCEDURE glob_sum_vec_3d, glob_sum_vec_4d
   END INTERFACE
   INTERFACE glob_min_vec
      MODULE PROCEDURE glob_min_vec_3d, glob_min_vec_4d
   END INTERFACE
   INTERFACE glob_max_vec
      MODULE PROCEDURE glob_max_vec_3d, glob_max_vec_4d
   END INTERFACE

#if defined key_nosignedzero
   INTERFACE SIGN
      MODULE PROCEDURE SIGN_SCALAR
   END INTERFACE
#endif

   !! * Substitutions
#  include "do_loop_substitute.h90"
   !!----------------------------------------------------------------------
   !! NEMO/OCE 4.0 , NEMO Consortium (2018)
   !! $Id: lib_fortran.F90 15376 2021-10-14 20:41:23Z clem $
   !! Software governed by the CeCILL license (see ./LICENSE)
   !!----------------------------------------------------------------------
CONTAINS

#  define GLOBSUM_CODE
#     define DIM_0d
#        include "lib_fortran_generic.h90"
#     undef DIM_0d
#     define DIM_1d
#        include "lib_fortran_generic.h90"
#     undef DIM_1d
#     define DIM_2d
#        include "lib_fortran_generic.h90"
#     undef DIM_2d
#     define DIM_3d
#        include "lib_fortran_generic.h90"
#     undef DIM_3d
#  define LOCALONLY
#     define DIM_2d
#        include "lib_fortran_generic.h90"
#     undef DIM_2d
#     define DIM_3d
#        include "lib_fortran_generic.h90"
#     undef DIM_3d
#  undef LOCALONLY
#  define VEC
#     define DIM_3d
#        include "lib_fortran_generic.h90"
#     undef DIM_3d
#     define DIM_4d
#        include "lib_fortran_generic.h90"
#     undef DIM_4d
#  undef VEC
#  undef GLOBSUM_CODE

#  define GLOBMINMAX_CODE
#     define DIM_2d
#        define OPERATION_GLOBMIN
#           include "lib_fortran_generic.h90"
#        undef OPERATION_GLOBMIN
#        define OPERATION_GLOBMAX
#           include "lib_fortran_generic.h90"
#        undef OPERATION_GLOBMAX
#     undef DIM_2d
#     define DIM_3d
#        define OPERATION_GLOBMIN
#           include "lib_fortran_generic.h90"
#        undef OPERATION_GLOBMIN
#        define OPERATION_GLOBMAX
#           include "lib_fortran_generic.h90"
#        undef OPERATION_GLOBMAX
#     undef DIM_3
#  define VEC
#     define DIM_3d
#        define OPERATION_GLOBMIN
#           include "lib_fortran_generic.h90"
#        undef OPERATION_GLOBMIN
#        define OPERATION_GLOBMAX
#           include "lib_fortran_generic.h90"
#        undef OPERATION_GLOBMAX
#     undef DIM_3d
#     define DIM_4d
#        define OPERATION_GLOBMIN
#           include "lib_fortran_generic.h90"
#        undef OPERATION_GLOBMIN
#        define OPERATION_GLOBMAX
#           include "lib_fortran_generic.h90"
#        undef OPERATION_GLOBMAX
#     undef DIM_4d
#  undef VEC
#  undef GLOBMINMAX_CODE

!                          ! FUNCTION sum3x3 !

   SUBROUTINE sum3x3_2d( p2d )
      !!-----------------------------------------------------------------------
      !!                  ***  routine sum3x3_2d  ***
      !!
      !! ** Purpose : sum over 3x3 boxes
      !!----------------------------------------------------------------------
      REAL(wp), DIMENSION (:,:), INTENT(inout) ::   p2d
      !
      INTEGER ::   ji, ji2, jj, jj2     ! dummy loop indices
      !!----------------------------------------------------------------------
      !
      IF( SIZE(p2d,1) /= jpi ) CALL ctl_stop( 'STOP', 'wrong call of sum3x3_2d, the first dimension is not equal to jpi' ) 
      IF( SIZE(p2d,2) /= jpj ) CALL ctl_stop( 'STOP', 'wrong call of sum3x3_2d, the second dimension is not equal to jpj' ) 
      !
      ! work over the whole domain (guarantees all internal cells are set when nn_hls=2)
      !
      DO_2D( nn_hls, nn_hls, nn_hls, nn_hls )
         IF( MOD(mig(ji,nn_hls), 3) == MOD(nn_hls, 3) .AND.   &              ! 1st bottom left corner always at (Nis0-1, Njs0-1)
           & MOD(mjg(jj,nn_hls), 3) == MOD(nn_hls, 3)         ) THEN         ! bottom left corner of a 3x3 box
            ji2 = MIN(mig(ji,nn_hls)+2, jpiglo) - nimpp + 1                  ! right position of the box
            jj2 = MIN(mjg(jj,nn_hls)+2, jpjglo) - njmpp + 1                  ! upper position of the box
            IF( ji2 <= jpi .AND. jj2 <= jpj ) THEN                           ! the box is fully included in the local mpi domain
               p2d(ji:ji2,jj:jj2) = SUM(p2d(ji:ji2,jj:jj2))
            ENDIF
         ENDIF
      END_2D
      CALL lbc_lnk( 'lib_fortran', p2d, 'T', 1.0_wp )

   END SUBROUTINE sum3x3_2d

   SUBROUTINE sum3x3_3d( p3d )
      !!-----------------------------------------------------------------------
      !!                  ***  routine sum3x3_3d  ***
      !!
      !! ** Purpose : sum over 3x3 boxes
      !!----------------------------------------------------------------------
      REAL(wp), DIMENSION (:,:,:), INTENT(inout) ::   p3d
      !
      INTEGER ::   ji, ji2, jj, jj2, jn     ! dummy loop indices
      INTEGER ::   ipn                      ! Third dimension size
      !!----------------------------------------------------------------------
      !
      IF( SIZE(p3d,1) /= jpi ) CALL ctl_stop( 'STOP', 'wrong call of sum3x3_3d, the first dimension is not equal to jpi' ) 
      IF( SIZE(p3d,2) /= jpj ) CALL ctl_stop( 'STOP', 'wrong call of sum3x3_3d, the second dimension is not equal to jpj' ) 
      ipn = SIZE(p3d,3)
      !
      DO jn = 1, ipn
         !
         ! work over the whole domain (guarantees all internal cells are set when nn_hls=2)
         !
         DO_2D( nn_hls, nn_hls, nn_hls, nn_hls )
            IF( MOD(mig(ji,nn_hls), 3) == MOD(nn_hls, 3) .AND.   &              ! 1st bottom left corner always at (Nis0-1, Njs0-1)
              & MOD(mjg(jj,nn_hls), 3) == MOD(nn_hls, 3)         ) THEN         ! bottom left corner of a 3x3 box
               ji2 = MIN(mig(ji,nn_hls)+2, jpiglo) - nimpp + 1                  ! right position of the box
               jj2 = MIN(mjg(jj,nn_hls)+2, jpjglo) - njmpp + 1                  ! upper position of the box
               IF( ji2 <= jpi .AND. jj2 <= jpj ) THEN                           ! the box is fully included in the local mpi domain
                  p3d(ji:ji2,jj:jj2,jn) = SUM(p3d(ji:ji2,jj:jj2,jn))
               ENDIF
            ENDIF
         END_2D
      END DO
      CALL lbc_lnk( 'lib_fortran', p3d, 'T', 1.0_wp )

   END SUBROUTINE sum3x3_3d

   
   ELEMENTAL SUBROUTINE DDPDD( ydda, yddb )
      !!----------------------------------------------------------------------
      !!               ***  ROUTINE DDPDD ***
      !!
      !! ** Purpose : Add a scalar element to a sum
      !!
      !!
      !! ** Method  : The code uses the compensated summation with doublet
      !!              (sum,error) emulated useing complex numbers. ydda is the
      !!               scalar to add to the summ yddb
      !!
      !! ** Action  : This does only work for MPI.
      !!
      !! References : Using Acurate Arithmetics to Improve Numerical
      !!              Reproducibility and Sability in Parallel Applications
      !!              Yun HE and Chris H. Q. DING, Journal of Supercomputing 18, 259-277, 2001
      !!----------------------------------------------------------------------
      COMPLEX(dp), INTENT(in   ) ::   ydda
      COMPLEX(dp), INTENT(inout) ::   yddb
      !
      REAL(dp) :: zerr, zt1, zt2  ! local work variables
      !!-----------------------------------------------------------------------
      !
      ! Compute ydda + yddb using Knuth's trick.
      zt1  = REAL(ydda) + REAL(yddb)
      zerr = zt1 - REAL(ydda)
      zt2  = ( (REAL(yddb) - zerr) + (REAL(ydda) - (zt1 - zerr)) )   &
         &   + AIMAG(ydda)         + AIMAG(yddb)
      !
      ! The result is t1 + t2, after normalization.
      yddb = CMPLX( zt1 + zt2, zt2 - ((zt1 + zt2) - zt1), dp )
      !
   END SUBROUTINE DDPDD

#if defined key_nosignedzero
   !!----------------------------------------------------------------------
   !!   'key_nosignedzero'                                         F90 SIGN
   !!----------------------------------------------------------------------

   ELEMENTAL FUNCTION SIGN_SCALAR( pa, pb )
      !!-----------------------------------------------------------------------
      !!                  ***  FUNCTION SIGN_SCALAR  ***
      !!
      !! ** Purpose : overwrite f95 behaviour of intrinsinc sign function
      !!-----------------------------------------------------------------------
      REAL(wp), INTENT(in) :: pa,pb          ! input
      REAL(wp)             :: SIGN_SCALAR    ! result
      !!-----------------------------------------------------------------------
      IF ( pb >= 0._wp ) THEN   ;   SIGN_SCALAR =  ABS(pa)
      ELSE                      ;   SIGN_SCALAR = -ABS(pa)
      ENDIF
   END FUNCTION SIGN_SCALAR

#endif

   !!======================================================================
END MODULE lib_fortran
