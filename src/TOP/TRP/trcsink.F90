MODULE trcsink
   !!======================================================================
   !!                         ***  MODULE trcsink  ***
   !! TOP :  vertical flux of particulate matter due to gravitational sinking
   !!======================================================================
   !! History :   1.0  !  2004     (O. Aumont) Original code
   !!             2.0  !  2007-12  (C. Ethe, G. Madec)  F90
   !!             3.4  !  2011-06  (O. Aumont, C. Ethe) Change aggregation formula
   !!             3.5  !  2012-07  (O. Aumont) Introduce potential time-splitting
   !!             4.0  !  2018-12  (O. Aumont) Generalize the PISCES code to make it usable by any model
   !!----------------------------------------------------------------------
   !!   trc_sink       :  Compute vertical flux of particulate matter due to gravitational sinking
   !!----------------------------------------------------------------------
   USE oce_trc         !  shared variables between ocean and passive tracers
   USE trc             !  passive tracers common variables 
   USE lib_mpp

   IMPLICIT NONE
   PRIVATE

   PUBLIC trc_sink
   PUBLIC trc_sink_ini

   INTEGER, PUBLIC :: nitermax      !: Maximum number of iterations for sinking

   !! * Substitutions
#  include "do_loop_substitute.h90"
#  include "domzgr_substitute.h90"
   !!----------------------------------------------------------------------
   !! NEMO/TOP 4.0 , NEMO Consortium (2018)
   !! $Id: trcsink.F90 10069 2018-08-28 14:12:24Z nicolasmartin $ 
   !! Software governed by the CeCILL license (see ./LICENSE)
   !!----------------------------------------------------------------------
CONTAINS

   !!----------------------------------------------------------------------
   !!   'standard sinking parameterisation'                  ???
   !!----------------------------------------------------------------------

   SUBROUTINE trc_sink ( kt, Kbb, Kmm, pwsink, psinkflx, jp_tra, rsfact )
      !!---------------------------------------------------------------------
      !!                     ***  ROUTINE trc_sink  ***
      !!
      !! ** Purpose :   Compute vertical flux of particulate matter due to 
      !!                gravitational sinking
      !!
      !! ** Method  : - ???
      !!---------------------------------------------------------------------
      INTEGER , INTENT(in)  :: kt
      INTEGER , INTENT(in)  :: Kbb, Kmm
      INTEGER , INTENT(in)  :: jp_tra    ! tracer index index      
      REAL(wp), INTENT(in)  :: rsfact    ! time step duration
      REAL(wp), INTENT(in)   , DIMENSION(A2D(0),jpk) :: pwsink
      REAL(wp), INTENT(inout), DIMENSION(A2D(0),jpk) :: psinkflx
      INTEGER  ::   ji, jj, jk
      INTEGER, DIMENSION(A2D(0)) ::   iiter
      REAL(wp) ::   zfact, zwsmax, zmax
      REAL(wp), DIMENSION(A2D(0),jpk) :: zwsink
      !!---------------------------------------------------------------------
      !
      IF( ln_timing )   CALL timing_start('trc_sink')
      !
      !
      ! OA This is (I hope) a temporary solution for the problem that may 
      ! OA arise in specific situation where the CFL criterion is broken 
      ! OA for vertical sedimentation of particles. To avoid this, a time
      ! OA splitting algorithm has been coded. A specific maximum
      ! OA iteration number is provided and may be specified in the namelist 
      ! OA This is to avoid very large iteration number when explicit free
      ! OA surface is used (for instance). When niter?max is set to 1, 
      ! OA this computation is skipped. The crude old threshold method is 
      ! OA then applied. This also happens when niter exceeds nitermax.
      IF( nitermax == 1 ) THEN
         iiter(:,:) = 1
      ELSE
         DO_2D( 0, 0, 0, 0 )
            iiter(ji,jj) = 1
            DO jk = 1, jpkm1
               IF( tmask(ji,jj,jk) == 1.0 ) THEN
                   zwsmax =  0.5 * e3t(ji,jj,jk,Kmm) * rday / rsfact
                   iiter(ji,jj) =  MAX( iiter(ji,jj), INT( pwsink(ji,jj,jk) / zwsmax ) + 1 )
               ENDIF
            END DO
         END_2D
         iiter(:,:) = MIN( iiter(:,:), nitermax )
      ENDIF

      DO_3D( 0, 0, 0, 0, 1, jpkm1 )
         zwsmax = 0.5 * e3t(ji,jj,jk,Kmm) * rday / rsfact
         zwsink(ji,jj,jk+1) = -MIN( pwsink(ji,jj,jk), zwsmax * REAL( iiter(ji,jj), wp ) ) / rday
      END_3D

      !  Initializa to zero all the sinking arrays 
      !  -----------------------------------------
      psinkflx(:,:,:) = 0.e0

      !   Compute the sedimentation term using trc_sink2 for the considered sinking particle
      !   -----------------------------------------------------
      CALL trc_sink2( Kbb, Kmm, zwsink, psinkflx, jp_tra, iiter, rsfact )
      !
      IF( ln_timing )   CALL timing_stop('trc_sink')
      !
   END SUBROUTINE trc_sink

   SUBROUTINE trc_sink2( Kbb, Kmm, pwsink, psinkflx, jp_tra, kiter, rsfact )
      !!---------------------------------------------------------------------
      !!                     ***  ROUTINE trc_sink2  ***
      !!
      !! ** Purpose :   Compute the sedimentation terms for the various sinking
      !!     particles. The scheme used to compute the trends is based
      !!     on MUSCL.
      !!
      !! ** Method  : - this ROUTINE compute not exactly the advection but the
      !!      transport term, i.e.  div(u*tra).
      !!---------------------------------------------------------------------
      INTEGER,  INTENT(in   )                         ::   Kbb, Kmm  ! time level indices
      INTEGER,  INTENT(in   )                         ::   jp_tra    ! tracer index index      
      REAL(wp), INTENT(in   )                         ::   rsfact    ! duration of time step
      INTEGER,  INTENT(in   ), DIMENSION(A2D(0))     ::   kiter     ! number of iterations for time-splitting 
      REAL(wp), INTENT(in   ), DIMENSION(A2D(0),jpk) ::   pwsink    ! sinking speed
      REAL(wp), INTENT(inout), DIMENSION(A2D(0),jpk) ::   psinkflx  ! sinking fluxe
      !
      INTEGER  ::   ji, jj, jk, jn, jt
      REAL(wp) ::   zigma,z0w,zign, zflx, zstep, zzwx, zzwy, zalpha
      REAL(wp), DIMENSION(A2D(0),jpk) :: ztraz, zakz, ztrb, zsinking 
      !!---------------------------------------------------------------------
      !
      IF( ln_timing )   CALL timing_start('trc_sink2')
      !
      DO_2D( 0, 0, 0, 0 )
         ! Vertical advective flux
         zstep = rsfact / REAL( kiter(ji,jj), wp ) / 2.
         DO jt = 1, kiter(ji,jj)
            ztraz(ji,jj,:) = 0.e0
            zakz (ji,jj,:) = 0.e0
            ztrb (ji,jj,:) = tr(ji,jj,:,jp_tra,Kbb)
            DO jn = 1, 2
               !              
               DO jk = 2, jpkm1
                  ztraz(ji,jj,jk) = ( tr(ji,jj,jk-1,jp_tra,Kbb) - tr(ji,jj,jk,jp_tra,Kbb) ) * tmask(ji,jj,jk)
               END DO
               ztraz(ji,jj,1  ) = 0.0
               ztraz(ji,jj,jpk) = 0.0

               ! slopes
               DO jk = 2, jpkm1
                  zign = 0.25 + SIGN( 0.25_wp, ztraz(ji,jj,jk) * ztraz(ji,jj,jk+1) )
                  zakz(ji,jj,jk) = ( ztraz(ji,jj,jk) + ztraz(ji,jj,jk+1) ) * zign
               END DO
      
               ! Slopes limitation
               DO jk = 2, jpkm1
                  zakz(ji,jj,jk) = SIGN( 1.0_wp, zakz(ji,jj,jk) ) *        &
                     &             MIN( ABS( zakz(ji,jj,jk) ), 2. * ABS(ztraz(ji,jj,jk+1)), 2. * ABS(ztraz(ji,jj,jk) ) )
               END DO
      
               ! vertical advective flux
               DO jk = 1, jpkm1
                  z0w    = SIGN( 0.5_wp, pwsink(ji,jj,jk+1) )
                  zalpha = 0.5 + z0w 
                  zigma  = z0w - 0.5 * pwsink(ji,jj,jk+1) * zstep / e3w(ji,jj,jk+1,Kmm)
                  zzwx   = tr(ji,jj,jk+1,jp_tra,Kbb) + zigma * zakz(ji,jj,jk+1)
                  zzwy   = tr(ji,jj,jk,jp_tra,Kbb) + zigma * zakz(ji,jj,jk)
                  zsinking(ji,jj,jk+1) = -pwsink(ji,jj,jk+1) * ( zalpha * zzwx + (1.0 - zalpha) * zzwy ) * zstep
               END DO
               !
               ! Boundary conditions
               zsinking(ji,jj,1  ) = 0.e0
               DO jk = 1, jpkm1
                  zflx = ( zsinking(ji,jj,jk) - zsinking(ji,jj,jk+1) ) / e3t(ji,jj,jk,Kmm)
                  tr(ji,jj,jk,jp_tra,Kbb) = tr(ji,jj,jk,jp_tra,Kbb) + zflx * tmask(ji,jj,jk)
               END DO
            END DO
            DO jk = 1, jpkm1
               zflx = ( zsinking(ji,jj,jk) - zsinking(ji,jj,jk+1) ) / e3t(ji,jj,jk,Kmm)
               ztrb(ji,jj,jk) = ztrb(ji,jj,jk) + 2. * zflx * tmask(ji,jj,jk)
            END DO

            tr(ji,jj,:,jp_tra,Kbb) = ztrb(ji,jj,:)
            psinkflx(ji,jj,:)   = psinkflx(ji,jj,:) + 2. * zsinking(ji,jj,:)
         END DO
      END_2D
      !
      IF( ln_timing )  CALL timing_stop('trc_sink2')
      !
   END SUBROUTINE trc_sink2

  SUBROUTINE trc_sink_ini
      !!---------------------------------------------------------------------
      !!                  ***  ROUTINE trc_sink_ini ***
      !!
      !! ** Purpose :   read  namelist options 
      !!----------------------------------------------------------------------
      INTEGER ::   ios   ! Local integer output status for namelist read
      !!
      NAMELIST/namtrc_snk/ nitermax
      !!----------------------------------------------------------------------
      !
      READ  ( numnat_ref, namtrc_snk, IOSTAT = ios, ERR = 907)
907   IF( ios /= 0 )   CALL ctl_nam ( ios , 'namtrc_snk in reference namelist' )
      READ  ( numnat_cfg, namtrc_snk, IOSTAT = ios, ERR = 908 )
908   IF( ios > 0 )   CALL ctl_nam ( ios , 'namtrc_snk in configuration namelist' )
      IF(lwm) WRITE( numont, namtrc_snk )

      IF(lwp) THEN                     !   ! Control print
         WRITE(numout,*)
         WRITE(numout,*) 'trc_sink : Sedimentation of particles '
         WRITE(numout,*) '~~~~~~~ '
         WRITE(numout,*) '   Namelist namtrc_snk : sedimentation of particles'
         WRITE(numout,*) '   Maximum number of iterations   nitermax = ', nitermax
         WRITE(numout,*)
      ENDIF

   END SUBROUTINE trc_sink_ini

   !!======================================================================
END MODULE trcsink
