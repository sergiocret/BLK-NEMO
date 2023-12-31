MODULE p2zprod
   !!======================================================================
   !!                         ***  MODULE p2zprod  ***
   !! TOP :  Growth Rate of phytoplankton 
   !!======================================================================
   !! History :   1.0  !  2004     (O. Aumont) Original code
   !!             2.0  !  2007-12  (C. Ethe, G. Madec)  F90
   !!             3.4  !  2011-05  (O. Aumont, C. Ethe) New parameterization of light limitation
   !!----------------------------------------------------------------------
   !!   p2z_prod       : Compute the growth Rate of the two phytoplanktons groups
   !!   p2z_prod_init  : Initialization of the parameters for growth
   !!   p2z_prod_alloc : Allocate variables for growth
   !!----------------------------------------------------------------------
   USE oce_trc         ! shared variables between ocean and passive tracers
   USE trc             ! passive tracers common variables 
   USE sms_pisces      ! PISCES Source Minus Sink variables
   USE p2zlim          ! Co-limitations of differents nutrients
   USE prtctl          ! print control for debugging
   USE iom             ! I/O manager

   IMPLICIT NONE
   PRIVATE

   PUBLIC   p2z_prod         ! called in p4zbio.F90
   PUBLIC   p2z_prod_init    ! called in trcsms_pisces.F90
   PUBLIC   p2z_prod_alloc   ! called in trcini_pisces.F90

   REAL(wp), PUBLIC ::   pislopen     !:  P-I slope of nanophytoplankton
   REAL(wp), PUBLIC ::   xadap        !:  Adaptation factor to low light 
   REAL(wp), PUBLIC ::   excretn      !:  Excretion ratio of nanophyto
   REAL(wp), PUBLIC ::   bresp        !:  Basal respiration rate
   REAL(wp), PUBLIC ::   chlcnm       !:  Maximum Chl/C ratio of nano
   REAL(wp), PUBLIC ::   chlcmin      !:  Minimum Chl/C ratio of phytoplankton

   REAL(wp), PUBLIC, ALLOCATABLE, SAVE, DIMENSION(:,:,:) ::   quotan   !: proxy of N quota in Nanophyto
   
   REAL(wp) ::   r1_rday    ! 1 / rday
   REAL(wp) ::   texcretn   ! 1 - excretn 

   LOGICAL  :: l_dia_ppphy
   LOGICAL  :: l_dia_mu, l_dia_light, l_dia_lprod
   !! * Substitutions
#  include "do_loop_substitute.h90"
#  include "domzgr_substitute.h90"
   !!----------------------------------------------------------------------
   !! NEMO/TOP 4.0 , NEMO Consortium (2018)
   !! $Id: p2zprod.F90 15459 2021-10-29 08:19:18Z cetlod $ 
   !! Software governed by the CeCILL license (see ./LICENSE)
   !!----------------------------------------------------------------------
CONTAINS

   SUBROUTINE p2z_prod( kt , knt, Kbb, Kmm, Krhs )
      !!---------------------------------------------------------------------
      !!                     ***  ROUTINE p2z_prod  ***
      !!
      !! ** Purpose :   Computes phytoplankton production depending on
      !!                light, temperature and nutrient availability
      !!                Computes also the chlorophyll content 
      !!---------------------------------------------------------------------
      INTEGER, INTENT(in) ::   kt, knt   !
      INTEGER, INTENT(in) ::   Kbb, Kmm, Krhs  ! time level indices
      !
      INTEGER  ::   ji, jj, jk
      REAL(wp) ::   znanotot, zpislopen, zfact
      REAL(wp) ::   zlimfac, zsizetmp, zprodfer, zprprod
      REAL(wp) ::   zprod, zval, zmxl_fac
      CHARACTER (len=25) :: charout
      REAL(wp), DIMENSION(A2D(0),jpk) :: zprmax, zmxl
      REAL(wp), DIMENSION(A2D(0),jpk) :: zprbio, zprchln
      REAL(wp), DIMENSION(A2D(0),jpk) :: zprorcan
      REAL(wp), ALLOCATABLE, DIMENSION(:,:,:) :: zw3d
      !!---------------------------------------------------------------------
      !
      IF( ln_timing )   CALL timing_start('p2z_prod')
      !
      IF( kt == nittrc000 ) THEN
         l_dia_ppphy = iom_use( "PPPHYN" ) .OR. iom_use( "TPP"  ) 
         l_dia_mu    = iom_use( "Mumax"  ) .OR. iom_use( "MuN"    )
         l_dia_light = iom_use( "LNlight")
      ENDIF

      ! Initialize the local arrays
      zprorcan(:,:,:) = 0._wp
      zprbio  (:,:,:) = 0._wp
      zmxl    (:,:,:) = 0._wp

      ! Computation of the maximimum production. Based on a Q10 description
      ! of the thermal dependency. Parameters are taken from Bissinger et al. (2008)
      zprmax(:,:,:) = 0.65_wp * r1_rday * tgfunc(:,:,:)

      ! Intermittency is supposed to have a similar effect on production as 
      ! day length (Shatwell et al., 2012). The correcting factor is zmxl_fac. 
      ! zmxl_chl is the fractional day length and is used to compute the mean
      ! PAR during daytime. The effect of mixing is computed using the 
      ! absolute light level definition of the euphotic zone
      ! ------------------------------------------------------------------------- 
      IF ( ln_p4z_dcyc ) THEN    ! Diurnal cycle in PISCES
         DO_3D( 0, 0, 0, 0, 1, jpkm1)
            IF( etot_ndcy(ji,jj,jk) > 1.E-3 ) THEN
               zval = 24.0
               IF( gdepw(ji,jj,jk+1,Kmm) <= hmld(ji,jj) ) THEN
                  zval = zval * MIN(1., heup_01(ji,jj) / ( hmld(ji,jj) + rtrn ))
               ENDIF
               zmxl(ji,jj,jk) = zval
            ENDIF
         END_3D
      ELSE ! No diurnal cycle in PISCES
         DO_3D( 0, 0, 0, 0, 1, jpkm1)
            IF( etot_ndcy(ji,jj,jk) > 1.E-3 ) THEN
               zval = MAX( 1., strn(ji,jj) )
               IF( gdepw(ji,jj,jk+1,Kmm) <= hmld(ji,jj) ) THEN
                  zval = zval * MIN(1., heup_01(ji,jj) / ( hmld(ji,jj) + rtrn ))
               ENDIF
               zmxl(ji,jj,jk) = zval
            ENDIF
         END_3D
      ENDIF

      ! The formulation proposed by Geider et al. (1997) has been modified 
      ! to exclude the effect of nutrient limitation and temperature in the PI
      ! curve following Vichi et al. (2007)
      ! -----------------------------------------------------------------------
      DO_3D( 0, 0, 0, 0, 1, jpkm1)
         IF( etot_ndcy(ji,jj,jk) > 1.E-3 ) THEN
            zmxl_fac = 1.0 - EXP( -0.26 * zmxl(ji,jj,jk) )
            zprprod = zprmax(ji,jj,jk) * zmxl_fac
            !
            ! The initial slope of the PI curve can be increased for nano
            ! to account for photadaptation, for instance in the DCM
            ! This parameterization is adhoc and should be either 
            ! improved or removed in future versions of the model
            ! Nanophytoplankton
            ! Computation of production function for Carbon
            ! Actual light levels are used here 
            ! ----------------------------------------------
            zpislopen = pislopen * thetanano(ji,jj,jk) / ( zprprod * rday * xlimphy(ji,jj,jk) + rtrn )
            zprchln(ji,jj,jk) = zprprod * ( 1.- EXP( -zpislopen * enanom(ji,jj,jk) )  )
            zprbio(ji,jj,jk)  = zprprod * ( 1.- EXP( -zpislopen * enano(ji,jj,jk) )  )
         ENDIF
      END_3D

      !  Computation of a proxy of the N/C quota from nutrient limitation 
      !  and light limitation. Steady state is assumed to allow the computation
      !  ----------------------------------------------------------------------
!      thetanano(:,:,:) = chlcnm
      DO_3D( 0, 0, 0, 0, 1, jpkm1)
          zval = xnanono3(ji,jj,jk) * zprmax(ji,jj,jk) / ( zprbio(ji,jj,jk) + rtrn )
          quotan(ji,jj,jk) = MIN( 1., 0.3 + 0.7 * zval )

          ! Diagnostic Chl/C ratio according to Geider et al. (1997)
          ! --------------------------------------------------------
          zmxl_fac = 1.0 - EXP( -0.26 * zmxl(ji,jj,jk) )
          thetanano(ji,jj,jk) = chlcnm / ( 1.0 + pislopen * chlcnm * enanom(ji,jj,jk)   &
             &                  / ( 2.0 * zprmax(ji,jj,jk) * zmxl_fac * xlimphy(ji,jj,jk) * rday + rtrn ) )
          thetanano(ji,jj,jk) = MAX( chlcmin, thetanano(ji,jj,jk) )
      END_3D

      ! Sea-ice effect on production
      ! No production is assumed below sea ice
      ! -------------------------------------- 
      DO_3D( 0, 0, 0, 0, 1, jpkm1)
         zprbio(ji,jj,jk) = zprbio(ji,jj,jk) * ( 1. - fr_i(ji,jj) )
      END_3D

      ! Computation of the various production  and nutrient uptake terms
      ! ---------------------------------------------------------------
      DO_3D( 0, 0, 0, 0, 1, jpkm1)
         IF( etot_ndcy(ji,jj,jk) > 1.E-3 ) THEN
            !  production terms for nanophyto. (C)
            zprorcan(ji,jj,jk) = zprbio(ji,jj,jk)  * xlimphy(ji,jj,jk) * tr(ji,jj,jk,jpphy,Kbb) * rfact2
            !
            ! Size computation
            ! Size is made a function of the limitation of of phytoplankton growth
            ! Strongly limited cells are supposed to be smaller. sizena is the 
            ! size at time step t+1 and is thus updated at the end of the 
            ! current time step
            ! --------------------------------------------------------------------
            zlimfac = xlimphy(ji,jj,jk) * zprchln(ji,jj,jk) / ( zprmax(ji,jj,jk) + rtrn )
            zsizetmp = 1.0 + 1.3 * ( xsizern - 1.0 ) * zlimfac**3/(0.3 + zlimfac**3)
            sizena(ji,jj,jk) = min(xsizern, max( sizena(ji,jj,jk), zsizetmp ) )
         ENDIF
      END_3D

      !   Update the arrays TRA which contain the biological sources and sinks
      DO_3D( 0, 0, 0, 0, 1, jpkm1)
         IF( etot_ndcy(ji,jj,jk) > 1.E-3 ) THEN
            zprodfer = zprorcan(ji,jj,jk) * feratz * texcretn
            !
            tr(ji,jj,jk,jpno3,Krhs) = tr(ji,jj,jk,jpno3,Krhs) - zprorcan(ji,jj,jk)
            tr(ji,jj,jk,jpfer,Krhs) = tr(ji,jj,jk,jpfer,Krhs) - zprorcan(ji,jj,jk) * feratz * texcretn
            consfe3(ji,jj,jk)   = zprodfer * 75.0 / ( rtrn + ( plig(ji,jj,jk) + 75.0 * (1.0 - plig(ji,jj,jk) ) )   &
            &                   * tr(ji,jj,jk,jpfer,Kbb) ) / rfact2
            !
            tr(ji,jj,jk,jpphy,Krhs) = tr(ji,jj,jk,jpphy,Krhs) + zprorcan(ji,jj,jk) * texcretn
            tr(ji,jj,jk,jpdoc,Krhs) = tr(ji,jj,jk,jpdoc,Krhs) + excretn * zprorcan(ji,jj,jk)
            tr(ji,jj,jk,jpoxy,Krhs) = tr(ji,jj,jk,jpoxy,Krhs) + ( o2ut + o2nit ) * zprorcan(ji,jj,jk)
            !
            tr(ji,jj,jk,jpdic,Krhs) = tr(ji,jj,jk,jpdic,Krhs) - zprorcan(ji,jj,jk)
            tr(ji,jj,jk,jptal,Krhs) = tr(ji,jj,jk,jptal,Krhs) + rno3 * zprorcan(ji,jj,jk)
         ENDIF
      END_3D

    ! Total primary production per year
    IF( l_dia_ppphy .OR. ( ln_check_mass .AND. kt == nitend .AND. knt == nrdttrc )  )  THEN
       ALLOCATE( zw3d(A2D(0),jpk) )  ;  zw3d(A2D(0),jpk) = 0._wp
       DO_3D( 0, 0, 0, 0, 1, jpkm1)
          zw3d(ji,jj,jk) = zprorcan(ji,jj,jk) * cvol(ji,jj,jk)
       END_3D
       tpp = glob_sum( 'p2zprod', zw3d )
       DEALLOCATE ( zw3d )
    ENDIF
    
    IF( lk_iomput .AND.  knt == nrdttrc ) THEN
       !
       ! Diagnostic Chl:C ratio
       CALL iom_put( "THETANANO", thetanano(:,:,:) )
       IF( l_dia_ppphy ) THEN
          zfact = 1.e+3 * rfact2r  !  conversion from mol/l/kt to  mol/m3/s
          ALLOCATE( zw3d(A2D(0),jpk) )  ;  zw3d(A2D(0),jpk) = 0._wp  
          ! primary production by nanophyto
          zw3d(A2D(0),1:jpkm1) = zprorcan(A2D(0),1:jpkm1) * zfact * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "PPPHYN", zw3d )  
          ! total primary production
          zw3d(A2D(0),1:jpkm1) = zprorcan(A2D(0),1:jpkm1) * zfact * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "TPP", zw3d )  
          CALL iom_put( "tintpp"  , tpp * zfact )  !  global total integrated primary production molC/s
          DEALLOCATE ( zw3d ) 
       ENDIF
       !
       IF( l_dia_mu ) THEN
          zfact = 1.e+3 * rfact2r  !  conversion from mol/l/kt to  mol/m3/s
          ALLOCATE( zw3d(A2D(0),jpk) )  ;  zw3d(A2D(0),jpk) = 0._wp  
          zw3d(A2D(0),1:jpkm1) = zprmax(A2D(0),1:jpkm1)  * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "Mumax", zw3d )  
          ! Realized growth rate for nanophyto
          zw3d(A2D(0),1:jpkm1) = zprbio(A2D(0),1:jpkm1) * xlimphy(A2D(0),1:jpkm1) * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "MuN", zw3d )  
          DEALLOCATE ( zw3d ) 
       ENDIF
       !
       IF( l_dia_light ) THEN
          zfact = 1.e+3 * rfact2r  !  conversion from mol/l/kt to  mol/m3/s
          ALLOCATE( zw3d(A2D(0),jpk) )  ;  zw3d(A2D(0),jpk) = 0._wp  
          ! light limitation term for nano
          zw3d(A2D(0),1:jpkm1) = zprbio(A2D(0),1:jpkm1) / ( zprmax(A2D(0),1:jpkm1) + rtrn ) * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "LNlight", zw3d )  
          DEALLOCATE ( zw3d ) 
       ENDIF
       !
     ENDIF

     IF(sn_cfctl%l_prttrc)   THEN  ! print mean trends (used for debugging)
         WRITE(charout, FMT="('prod')")
         CALL prt_ctl_info( charout, cdcomp = 'top' )
         CALL prt_ctl(tab4d_1=tr(:,:,:,:,Krhs), mask1=tmask, clinfo=ctrcnm)
     ENDIF
      !
      IF( ln_timing )  CALL timing_stop('p2z_prod')
      !
   END SUBROUTINE p2z_prod


   SUBROUTINE p2z_prod_init
      !!----------------------------------------------------------------------
      !!                  ***  ROUTINE p2z_prod_init  ***
      !!
      !! ** Purpose :   Initialization of phytoplankton production parameters
      !!
      !! ** Method  :   Read the namp2zprod namelist and check the parameters
      !!      called at the first timestep (nittrc000)
      !!
      !! ** input   :   Namelist namp2zprod
      !!----------------------------------------------------------------------
      INTEGER ::   ios   ! Local integer
      !
      ! Namelist block
      NAMELIST/namp2zprod/ pislopen, bresp, excretn,  &
         &                 chlcnm, chlcmin
      !!----------------------------------------------------------------------
      !
      IF(lwp) THEN                         ! control print
         WRITE(numout,*)
         WRITE(numout,*) 'p2z_prod_init : phytoplankton growth'
         WRITE(numout,*) '~~~~~~~~~~~~~'
      ENDIF
      !
      READ  ( numnatp_ref, namp2zprod, IOSTAT = ios, ERR = 901)
901   IF( ios /= 0 )   CALL ctl_nam ( ios , 'namp2zprod in reference namelist' )

      READ  ( numnatp_cfg, namp2zprod, IOSTAT = ios, ERR = 902 )
902   IF( ios >  0 )   CALL ctl_nam ( ios , 'namp2zprod in configuration namelist' )
      IF(lwm) WRITE( numonp, namp2zprod )

      IF(lwp) THEN                         ! control print
         WRITE(numout,*) '   Namelist : namp2zprod'
         WRITE(numout,*) '      P-I slope                                 pislopen     =', pislopen
         WRITE(numout,*) '      excretion ratio of nanophytoplankton      excretn      =', excretn
         WRITE(numout,*) '      basal respiration in phytoplankton        bresp        =', bresp
         WRITE(numout,*) '      Maximum Chl/C in phytoplankton            chlcmin      =', chlcmin
         WRITE(numout,*) '      Minimum Chl/C in nanophytoplankton        chlcnm       =', chlcnm
      ENDIF
      !
      r1_rday   = 1._wp / rday 
      texcretn  = 1._wp - excretn
      tpp       = 0._wp
      !
   END SUBROUTINE p2z_prod_init

   INTEGER FUNCTION p2z_prod_alloc()
      !!----------------------------------------------------------------------
      !!                     ***  ROUTINE p2z_prod_alloc  ***
      !!----------------------------------------------------------------------
      ALLOCATE( quotan(A2D(0),jpk), STAT = p2z_prod_alloc )
      !
      IF( p2z_prod_alloc /= 0 ) CALL ctl_stop( 'STOP', 'p2z_prod_alloc : failed to allocate arrays.' )
      !
   END FUNCTION p2z_prod_alloc

   !!======================================================================
END MODULE p2zprod
