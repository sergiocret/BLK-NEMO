MODULE p4zprod
   !!======================================================================
   !!                         ***  MODULE p4zprod  ***
   !! TOP :  Growth Rate of the two phytoplankton groups of PISCES 
   !!======================================================================
   !! History :   1.0  !  2004     (O. Aumont) Original code
   !!             2.0  !  2007-12  (C. Ethe, G. Madec)  F90
   !!             3.4  !  2011-05  (O. Aumont, C. Ethe) New parameterization of light limitation
   !!----------------------------------------------------------------------
   !!   p4z_prod       : Compute the growth Rate of the two phytoplanktons groups
   !!   p4z_prod_init  : Initialization of the parameters for growth
   !!   p4z_prod_alloc : Allocate variables for growth
   !!----------------------------------------------------------------------
   USE oce_trc         ! shared variables between ocean and passive tracers
   USE trc             ! passive tracers common variables 
   USE sms_pisces      ! PISCES Source Minus Sink variables
   USE p2zlim          ! Co-limitations of different nutrients
   USE p4zlim          ! Co-limitations of differents nutrients
   USE prtctl          ! print control for debugging
   USE iom             ! I/O manager

   IMPLICIT NONE
   PRIVATE

   PUBLIC   p4z_prod         ! called in p4zbio.F90
   PUBLIC   p4z_prod_init    ! called in trcsms_pisces.F90
   PUBLIC   p4z_prod_alloc   ! called in trcini_pisces.F90

   REAL(wp), PUBLIC ::   pislopen     !:  P-I slope of nanophytoplankton
   REAL(wp), PUBLIC ::   pisloped     !:  P-I slope of diatoms
   REAL(wp), PUBLIC ::   excretn      !:  Excretion ratio of nanophyto
   REAL(wp), PUBLIC ::   excretd      !:  Excretion ratio of diatoms
   REAL(wp), PUBLIC ::   bresp        !:  Basal respiration rate
   REAL(wp), PUBLIC ::   chlcmin      !:  Minimum Chl/C ratio of phytoplankton
   REAL(wp), PUBLIC ::   fecnm        !:  Maximum Fe/C ratio of nano
   REAL(wp), PUBLIC ::   fecdm        !:  Maximum Fe/C ratio of diatoms
   REAL(wp), PUBLIC ::   grosip       !:  Mean Si/C ratio of diatoms

   REAL(wp), PUBLIC, ALLOCATABLE, SAVE, DIMENSION(:,:,:) ::   quotan   !: proxy of N quota in Nanophyto
   REAL(wp), PUBLIC, ALLOCATABLE, SAVE, DIMENSION(:,:,:) ::   quotad   !: proxy of N quota in diatoms
   
   REAL(wp) ::   r1_rday    ! 1 / rday
   REAL(wp) ::   texcretn   ! 1 - excretn 
   REAL(wp) ::   texcretd   ! 1 - excretd        

   LOGICAL  :: l_dia_ppphy, l_dia_ppnew, l_dia_ppbfe, l_dia_ppbsi
   LOGICAL  :: l_dia_mu, l_dia_light, l_dia_lprod
   !! * Substitutions
#  include "do_loop_substitute.h90"
#  include "domzgr_substitute.h90"
   !!----------------------------------------------------------------------
   !! NEMO/TOP 4.0 , NEMO Consortium (2018)
   !! $Id: p4zprod.F90 15459 2021-10-29 08:19:18Z cetlod $ 
   !! Software governed by the CeCILL license (see ./LICENSE)
   !!----------------------------------------------------------------------
CONTAINS

   SUBROUTINE p4z_prod( kt , knt, Kbb, Kmm, Krhs )
      !!---------------------------------------------------------------------
      !!                     ***  ROUTINE p4z_prod  ***
      !!
      !! ** Purpose :   Computes phytoplankton production depending on
      !!                light, temperature and nutrient availability
      !!                Computes also the uptake of Iron and Si as well 
      !!                as the chlorophyll content of the cells
      !!                PISCES relies on a mixed Monod-Quota formalism 
      !!---------------------------------------------------------------------
      INTEGER, INTENT(in) ::   kt, knt   !
      INTEGER, INTENT(in) ::   Kbb, Kmm, Krhs  ! time level indices
      !
      INTEGER  ::   ji, jj, jk
      REAL(wp) ::   zsilfac, znanotot, zdiattot
      REAL(wp) ::   zratio, zmax, zsilim, zlim, zsiborn
      REAL(wp) ::   zpptot, zpnewtot, zpregtot, zprochln, zprochld
      REAL(wp) ::   zproddoc, zprodsil, zprodfer, zprodlig, zprod1
      REAL(wp) ::   zpislopen, zpisloped, zfact
      REAL(wp) ::   zratiosi, zmaxsi, zlimfac, zsizetmp, zfecnm, zfecdm
      REAL(wp) ::   zprod, zval, zmxl_fac, zmxl_chl, zpronewn, zpronewd
      CHARACTER (len=25) :: charout
      REAL(wp), DIMENSION(A2D(0),jpk) :: zprmax, zmxl
      REAL(wp), DIMENSION(A2D(0),jpk) :: zpislopeadn, zpislopeadd, zysopt  
      REAL(wp), DIMENSION(A2D(0),jpk) :: zprdia, zprbio, zprchld, zprchln   
      REAL(wp), DIMENSION(A2D(0),jpk) :: zprorcan, zprorcad
      REAL(wp), DIMENSION(A2D(0),jpk) :: zprofed, zprofen
      REAL(wp), ALLOCATABLE, DIMENSION(:,:,:) :: zw3d
      !!---------------------------------------------------------------------
      !
      IF( ln_timing )   CALL timing_start('p4z_prod')
      !
      IF( kt == nittrc000 ) THEN
         l_dia_ppphy = iom_use( "PPPHYN" ) .OR. iom_use( "PPPHYD" ) .OR. iom_use( "TPP"  ) 
         l_dia_ppnew = iom_use( "PPNEWN" ) .OR. iom_use( "PPNEWD" ) .OR. iom_use( "TPNEW")
         l_dia_ppbfe = iom_use( "PFeN"   ) .OR. iom_use( "PFeD"   ) .OR. iom_use( "TPBFE") 
         l_dia_ppbsi = iom_use( "PBSi"   ) 
         l_dia_mu    = iom_use( "Mumax"  ) .OR. iom_use( "MuN"    ) .OR. iom_use( "MuD") 
         l_dia_light = iom_use( "LNlight") .OR. iom_use( "LDlight") 
         l_dia_lprod = ln_ligand .AND. ( iom_use( "LPRODP") .OR. iom_use( "LDETP") )
      ENDIF

      ! Initialize the local arrays
      zprorcan(:,:,:) = 0._wp    ;    zprorcad(:,:,:) = 0._wp
      zprofen (:,:,:) = 0._wp    ;    zprofed (:,:,:) = 0._wp
      zprchld (:,:,:) = 0._wp    ;    zprchln (:,:,:) = 0._wp 
      zprbio  (:,:,:) = 0._wp    ;    zprdia  (:,:,:) = 0._wp 
      zmxl    (:,:,:) = 0._wp    ;    zysopt  (:,:,:) = 0._wp

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
            zmxl_chl = zmxl(ji,jj,jk) / 24.
            zprbio(ji,jj,jk) = zprmax(ji,jj,jk) * zmxl_fac
            zprdia(ji,jj,jk) = zprmax(ji,jj,jk) * zmxl_fac
            !
            ! The initial slope of the PI curve can be increased for nano
            ! to account for photadaptation, for instance in the DCM
            ! This parameterization is adhoc and should be either 
            ! improved or removed in future versions of the model

            ! Nanophytoplankton
            zpislopeadn(ji,jj,jk) = pislopen * tr(ji,jj,jk,jpnch,Kbb)  &
            &                   /( tr(ji,jj,jk,jpphy,Kbb) * 12. + rtrn)

            ! Diatoms
            zpislopeadd(ji,jj,jk) = pisloped * tr(ji,jj,jk,jpdch,Kbb)   &
            &                   /( tr(ji,jj,jk,jpdia,Kbb) * 12. + rtrn)
            !
            ! Computation of production function for Carbon
            ! Actual light levels are used here 
            ! ----------------------------------------------
            zpislopen = zpislopeadn(ji,jj,jk) / ( zprmax(ji,jj,jk) * xlimphy(ji,jj,jk) &
            &            * zmxl_fac * rday + rtrn)
            zpisloped = zpislopeadd(ji,jj,jk) / ( zprmax(ji,jj,jk) * xlimdia(ji,jj,jk) &
            &            * zmxl_fac * rday + rtrn)
            zprbio(ji,jj,jk) = zprbio(ji,jj,jk) * ( 1.- EXP( -zpislopen * enano(ji,jj,jk) )  )
            zprdia(ji,jj,jk) = zprdia(ji,jj,jk) * ( 1.- EXP( -zpisloped * ediat(ji,jj,jk) )  )

            !  Computation of production function for Chlorophyll
            !  Mean light level in the mixed layer (when appropriate)
            !  is used here (acclimation is in general slower than 
            !  the characteristic time scales of vertical mixing)
            !  ------------------------------------------------------
            zpislopen = zpislopen * zmxl_fac / ( zmxl_chl + rtrn )
            zpisloped = zpisloped * zmxl_fac / ( zmxl_chl + rtrn )
            zprchln(ji,jj,jk) = ( 1.- EXP( -zpislopen * enanom(ji,jj,jk) ) )
            zprchld(ji,jj,jk) = ( 1.- EXP( -zpisloped * ediatm(ji,jj,jk) ) )
         ENDIF
      END_3D

      !  Computation of a proxy of the N/C quota from nutrient limitation 
      !  and light limitation. Steady state is assumed to allow the computation
      !  ----------------------------------------------------------------------
      DO_3D( 0, 0, 0, 0, 1, jpkm1)
          zval = MIN( xnanopo4(ji,jj,jk), ( xnanonh4(ji,jj,jk) + xnanono3(ji,jj,jk) ) )   &
          &      * zprmax(ji,jj,jk) / ( zprbio(ji,jj,jk) + rtrn )
          quotan(ji,jj,jk) = MIN( 1., 0.3 + 0.7 * zval )
          zval = MIN( xdiatpo4(ji,jj,jk), ( xdiatnh4(ji,jj,jk) + xdiatno3(ji,jj,jk) ) )   &
          &      * zprmax(ji,jj,jk) / ( zprdia(ji,jj,jk) + rtrn )
          quotad(ji,jj,jk) = MIN( 1., 0.3 + 0.7 * zval )
      END_3D


      DO_3D( 0, 0, 0, 0, 1, jpkm1)
          IF( etot_ndcy(ji,jj,jk) > 1.E-3 ) THEN
             ! Si/C of diatoms
             ! ------------------------
             ! Si/C increases with iron stress and silicate availability
             ! Si/C is arbitrariliy increased for very high Si concentrations
             ! to mimic the very high ratios observed in the Southern Ocean (zsilfac)
             ! A parameterization derived from Flynn (2003) is used for the control
             ! when Si is not limiting which is similar to the parameterisation
             ! proposed by Gurney and Davidson (1999).
             ! -----------------------------------------------------------------------
            zlim  = tr(ji,jj,jk,jpsil,Kbb) / ( tr(ji,jj,jk,jpsil,Kbb) + xksi1 )
            zsilim = xlimdia(ji,jj,jk) * zprdia(ji,jj,jk) / ( zprmax(ji,jj,jk) + rtrn )
            zsiborn = tr(ji,jj,jk,jpsil,Kbb) * tr(ji,jj,jk,jpsil,Kbb) * tr(ji,jj,jk,jpsil,Kbb)
            IF (gphit(ji,jj) < -30 ) THEN
              zsilfac = 1. + 2. * zsiborn / ( zsiborn + xksi2**3 )
            ELSE
              zsilfac = 1. +      zsiborn / ( zsiborn + xksi2**3 )
            ENDIF
            zratiosi = 1.0 - tr(ji,jj,jk,jpdsi,Kbb) / ( tr(ji,jj,jk,jpdia,Kbb) + rtrn ) / ( zsilfac * grosip * 3.0 + rtrn )
            zratiosi = MAX(0., MIN(1.0, zratiosi) )
            zmaxsi  = (1.0 + 0.1**4) * zratiosi**4 / ( zratiosi**4 + 0.1**4 )
            IF( xlimsi(ji,jj,jk) /= xlimdia(ji,jj,jk) ) THEN
               zysopt(ji,jj,jk) = zlim * zsilfac * grosip * 1.0 * zmaxsi
            ELSE
               zysopt(ji,jj,jk) = zlim * zsilfac * grosip * 1.0 * zsilim**0.7 * zmaxsi
            ENDIF
        ENDIF
      END_3D

      ! Sea-ice effect on production
      ! No production is assumed below sea ice
      ! -------------------------------------- 
      DO_3D( 0, 0, 0, 0, 1, jpkm1)
         zprbio(ji,jj,jk) = zprbio(ji,jj,jk) * ( 1. - fr_i(ji,jj) )
         zprdia(ji,jj,jk) = zprdia(ji,jj,jk) * ( 1. - fr_i(ji,jj) )
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
            zlimfac = xlimphy(ji,jj,jk) * zprchln(ji,jj,jk)
            zsizetmp = 1.0 + 1.3 * ( xsizern - 1.0 ) * zlimfac**3/(0.3 + zlimfac**3)
            sizena(ji,jj,jk) = min(xsizern, max( sizena(ji,jj,jk), zsizetmp ) )

            ! Iron uptake rates of nanophytoplankton. Upregulation is  
            ! not parameterized at low iron concentrations as observations
            ! do not suggest it for accimated cells. Uptake is
            ! downregulated when the quota is close to the maximum quota
            zfecnm = xqfuncfecn(ji,jj,jk) + ( fecnm - xqfuncfecn(ji,jj,jk) ) * ( xnanono3(ji,jj,jk) + xnanonh4(ji,jj,jk) )
            zratio = 1.0 - MIN(1.0,tr(ji,jj,jk,jpnfe,Kbb) / ( tr(ji,jj,jk,jpphy,Kbb) * zfecnm + rtrn ) )
            zmax   = MAX( 0., MIN( 1.0, zratio**2/ (0.05**2+zratio**2) ) ) 
            zprofen(ji,jj,jk) = zfecnm * zprmax(ji,jj,jk) * ( 1.0 - fr_i(ji,jj) )  &
            &          * (1. + 0.8 * xnanono3(ji,jj,jk) / ( rtrn + xnanono3(ji,jj,jk)  &
            &          + xnanonh4(ji,jj,jk) ) * (1. - xnanofer(ji,jj,jk) ) )   &
            &          * xnanofer(ji,jj,jk) * zmax * tr(ji,jj,jk,jpphy,Kbb) * rfact2
            ! production terms of diatoms (C)
            zprorcad(ji,jj,jk) = zprdia(ji,jj,jk) * xlimdia(ji,jj,jk) * tr(ji,jj,jk,jpdia,Kbb) * rfact2

            ! Size computation
            ! Size is made a function of the limitation of of phytoplankton growth
            ! Strongly limited cells are supposed to be smaller. sizeda is
            ! size at time step t+1 and is thus updated at the end of the 
            ! current time step. 
            ! --------------------------------------------------------------------
            zlimfac = zprchld(ji,jj,jk) * xlimdia(ji,jj,jk)
            zsizetmp = 1.0 + 1.3 * ( xsizerd - 1.0 ) * zlimfac**3/(0.3 + zlimfac**3)
            sizeda(ji,jj,jk) = min(xsizerd, max( sizeda(ji,jj,jk), zsizetmp ) )

            ! Iron uptake rates of diatoms. Upregulation is  
            ! not parameterized at low iron concentrations as observations
            ! do not suggest it for accimated cells. Uptake is
            ! downregulated when the quota is close to the maximum quota
            zfecdm = xqfuncfecd(ji,jj,jk) + ( fecdm - xqfuncfecd(ji,jj,jk) ) * ( xdiatno3(ji,jj,jk) + xdiatnh4(ji,jj,jk) )
            zratio = 1.0 - MIN(1.0, tr(ji,jj,jk,jpdfe,Kbb) / ( tr(ji,jj,jk,jpdia,Kbb) * zfecdm + rtrn ) )
            zmax   = MAX( 0., MIN( 1.0, zratio**2/ (0.05**2+zratio**2) ) ) 
            zprofed(ji,jj,jk) = zfecdm * zprmax(ji,jj,jk) * (1.0 - fr_i(ji,jj) )  &
            &          * (1. + 0.8 * xdiatno3(ji,jj,jk) / ( rtrn + xdiatno3(ji,jj,jk)  &
            &          + xdiatnh4(ji,jj,jk) ) * (1. - xdiatfer(ji,jj,jk) ) )   &
            &          * xdiatfer(ji,jj,jk) * zmax * tr(ji,jj,jk,jpdia,Kbb) * rfact2
         ENDIF
      END_3D

      ! Computation of the chlorophyll production terms
      ! The parameterization is taken from Geider et al. (1997)
      ! -------------------------------------------------------
      DO_3D( 0, 0, 0, 0, 1, jpkm1)
         IF( etot_ndcy(ji,jj,jk) > 1.E-3 ) THEN
            zmxl_chl = zmxl(ji,jj,jk)  / 24.
            !  production terms for nanophyto. ( chlorophyll )
            znanotot = enanom(ji,jj,jk) / ( zmxl_chl + rtrn )
            zprod1   = zprorcan(ji,jj,jk) * texcretn / ( tr(ji,jj,jk,jpphy,Kbb) + rtrn )
            zprod = zprod1 / ratchl * ( pislopen * znanotot / ( zprmax(ji,jj,jk) * rday )   &
            &   * ( 1.0 - zprchln(ji,jj,jk) ) * MAX(0.0, (1.0 - ratchl * tr(ji,jj,jk,jpnch,Kbb)    &
            &   / ( 12. * tr(ji,jj,jk,jpphy,Kbb) + rtrn ) / (xlimphy(ji,jj,jk) + rtrn ) ) )     &
            &   - ratchl * zprchln(ji,jj,jk) ) + zprod1
            zprochln = MAX(zprod * tr(ji,jj,jk,jpnch,Kbb) , chlcmin * 12 * zprorcan(ji,jj,jk) )

            !  production terms for diatoms ( chlorophyll )
            zdiattot = ediatm(ji,jj,jk) / ( zmxl_chl + rtrn )
            zprod1   = zprorcad(ji,jj,jk) * texcretd / ( tr(ji,jj,jk,jpdia,Kbb) + rtrn )
            zprod = zprod1 / ratchl * ( pisloped * zdiattot / ( zprmax(ji,jj,jk) * rday )   &
            &   * ( 1.0 - zprchld(ji,jj,jk) ) * MAX(0.0, (1.0 - ratchl * tr(ji,jj,jk,jpdch,Kbb)    &
            &   / ( 12. * tr(ji,jj,jk,jpdia,Kbb) + rtrn ) / (xlimdia(ji,jj,jk) + rtrn ) ) )     &
            &   - ratchl * zprchld(ji,jj,jk) ) + zprod1
            zprochld = MAX(zprod * tr(ji,jj,jk,jpdch,Kbb) , chlcmin * 12 * zprorcad(ji,jj,jk) )

            !   Update the arrays TRA which contain the Chla sources and sinks
            tr(ji,jj,jk,jpnch,Krhs) = tr(ji,jj,jk,jpnch,Krhs) + zprochln
            tr(ji,jj,jk,jpdch,Krhs) = tr(ji,jj,jk,jpdch,Krhs) + zprochld
         ENDIF
      END_3D

      !   Update the arrays TRA which contain the biological sources and sinks
      DO_3D( 0, 0, 0, 0, 1, jpkm1)
        IF( etot_ndcy(ji,jj,jk) > 1.E-3 ) THEN
           ! New production (uptake of NO3)
           zpronewn = zprorcan(ji,jj,jk) * xnanono3(ji,jj,jk) / ( xnanono3(ji,jj,jk) + xnanonh4(ji,jj,jk) + rtrn )
           zpronewd = zprorcad(ji,jj,jk) * xdiatno3(ji,jj,jk) / ( xdiatno3(ji,jj,jk) + xdiatnh4(ji,jj,jk) + rtrn )
           !
           zpptot   = zprorcan(ji,jj,jk) + zprorcad(ji,jj,jk)
           zpnewtot = zpronewn + zpronewd
           zpregtot = zpptot - zpnewtot
           zprodsil  = zprmax(ji,jj,jk) * zysopt(ji,jj,jk) * rfact2 * tr(ji,jj,jk,jpdia,Kbb)
           zproddoc  = excretd * zprorcad(ji,jj,jk) + excretn * zprorcan(ji,jj,jk)
           zprodfer  = texcretn * zprofen(ji,jj,jk) + texcretd * zprofed(ji,jj,jk)
           !
           tr(ji,jj,jk,jppo4,Krhs) = tr(ji,jj,jk,jppo4,Krhs) - zpptot
           tr(ji,jj,jk,jpno3,Krhs) = tr(ji,jj,jk,jpno3,Krhs) - zpnewtot
           tr(ji,jj,jk,jpnh4,Krhs) = tr(ji,jj,jk,jpnh4,Krhs) - zpregtot
           tr(ji,jj,jk,jpphy,Krhs) = tr(ji,jj,jk,jpphy,Krhs) + zprorcan(ji,jj,jk) * texcretn
           tr(ji,jj,jk,jpnfe,Krhs) = tr(ji,jj,jk,jpnfe,Krhs) + zprofen(ji,jj,jk)  * texcretn
           tr(ji,jj,jk,jpdia,Krhs) = tr(ji,jj,jk,jpdia,Krhs) + zprorcad(ji,jj,jk) * texcretd
           tr(ji,jj,jk,jpdfe,Krhs) = tr(ji,jj,jk,jpdfe,Krhs) + zprofed(ji,jj,jk)  * texcretd
           tr(ji,jj,jk,jpdsi,Krhs) = tr(ji,jj,jk,jpdsi,Krhs) + zprodsil
           tr(ji,jj,jk,jpsil,Krhs) = tr(ji,jj,jk,jpsil,Krhs) - zprodsil
           tr(ji,jj,jk,jpdoc,Krhs) = tr(ji,jj,jk,jpdoc,Krhs) + zproddoc
           tr(ji,jj,jk,jpoxy,Krhs) = tr(ji,jj,jk,jpoxy,Krhs) + o2ut * zpregtot + ( o2ut + o2nit ) * zpnewtot
           !
           tr(ji,jj,jk,jpfer,Krhs) = tr(ji,jj,jk,jpfer,Krhs) - zprodfer
           consfe3(ji,jj,jk)   = zprodfer * 75.0 / ( rtrn + ( plig(ji,jj,jk) + 75.0 * (1.0 - plig(ji,jj,jk) ) )   &
           &                   * tr(ji,jj,jk,jpfer,Kbb) ) / rfact2
           !
           tr(ji,jj,jk,jpdic,Krhs) = tr(ji,jj,jk,jpdic,Krhs) - zpptot
           tr(ji,jj,jk,jptal,Krhs) = tr(ji,jj,jk,jptal,Krhs) + rno3 * ( zpnewtot - zpregtot )
        ENDIF
      END_3D

     ! Production and uptake of ligands by phytoplankton. This part is activated 
     ! when ln_ligand is set to .true. in the namelist. Ligand uptake is small 
     ! and based on the FeL model by Morel et al. (2008) and on the study of
     ! Shaked et al. (2020)
     ! -------------------------------------------------------------------------
     IF( ln_ligand ) THEN
         DO_3D( 0, 0, 0, 0, 1, jpkm1)
           IF( etot_ndcy(ji,jj,jk) > 1.E-3 ) THEN
              zproddoc = excretd * zprorcad(ji,jj,jk) + excretn * zprorcan(ji,jj,jk)
              zprodfer = texcretn * zprofen(ji,jj,jk) + texcretd * zprofed(ji,jj,jk)
              zprodlig = plig(ji,jj,jk) / ( rtrn + plig(ji,jj,jk) + 75.0 * (1.0 - plig(ji,jj,jk) ) ) * lthet
              !
              tr(ji,jj,jk,jplgw,Krhs) = tr(ji,jj,jk,jplgw,Krhs) + zproddoc * ldocp - zprodfer * zprodlig
           ENDIF
         END_3D
     ENDIF

    ! Total primary production per year
    IF( l_dia_ppphy .OR. ( ln_check_mass .AND. kt == nitend .AND. knt == nrdttrc )  )  THEN
       ALLOCATE( zw3d(A2D(0),jpk) )  ;  zw3d(A2D(0),jpk) = 0._wp
       DO_3D( 0, 0, 0, 0, 1, jpkm1)
          zw3d(ji,jj,jk) = ( zprorcan(ji,jj,jk) + zprorcad(ji,jj,jk) ) * cvol(ji,jj,jk)
       END_3D
       tpp = glob_sum( 'p4zprod', zw3d )
       DEALLOCATE ( zw3d )
    ENDIF
    
    IF( lk_iomput .AND.  knt == nrdttrc ) THEN
       !
       IF( l_dia_ppphy ) THEN
          zfact = 1.e+3 * rfact2r  !  conversion from mol/l/kt to  mol/m3/s
          ALLOCATE( zw3d(A2D(0),jpk) )  ;  zw3d(A2D(0),jpk) = 0._wp  
          ! primary production by nanophyto
          zw3d(A2D(0),1:jpkm1) = zprorcan(A2D(0),1:jpkm1) * zfact * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "PPPHYN", zw3d )  
          ! primary production by diatomes
          zw3d(A2D(0),1:jpkm1) = zprorcad(A2D(0),1:jpkm1) * zfact * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "PPPHYD", zw3d )  
          ! total primary production
          zw3d(A2D(0),1:jpkm1) = ( zprorcan(A2D(0),1:jpkm1) +  zprorcad(A2D(0),1:jpkm1) ) * zfact * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "TPP", zw3d )  
          CALL iom_put( "tintpp"  , tpp * zfact )  !  global total integrated primary production molC/s
          DEALLOCATE ( zw3d ) 
       ENDIF
       !
       IF( l_dia_ppnew ) THEN
          zfact = 1.e+3 * rfact2r  !  conversion from mol/l/kt to  mol/m3/s
          ALLOCATE( zw3d(A2D(0),jpk) )  ;  zw3d(A2D(0),jpk) = 0._wp  
          ! new primary production by nano
          zw3d(A2D(0),1:jpkm1) = ( zprorcan(A2D(0),1:jpkm1) * xnanono3(A2D(0),1:jpkm1) &
                &              / ( xnanono3(A2D(0),1:jpkm1) + xnanonh4(A2D(0),1:jpkm1) + rtrn ) ) &
                &                  * zfact * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "PPNEWN", zw3d )  
          ! new primary production by diatomes
          zw3d(A2D(0),1:jpkm1) = ( zprorcad(A2D(0),1:jpkm1) * xdiatno3(A2D(0),1:jpkm1) &
                &              / ( xdiatno3(A2D(0),1:jpkm1) + xdiatnh4(A2D(0),1:jpkm1) + rtrn ) ) &
                &                  * zfact * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "PPNEWD", zw3d )  
          ! total new production 
          zw3d(A2D(0),1:jpkm1) = (    ( zprorcan(A2D(0),1:jpkm1) * xnanono3(A2D(0),1:jpkm1) &
                &                   / ( xnanono3(A2D(0),1:jpkm1) + xnanonh4(A2D(0),1:jpkm1) + rtrn ) ) &
                &                +    ( zprorcad(A2D(0),1:jpkm1) * xdiatno3(A2D(0),1:jpkm1) &
                &                   / ( xdiatno3(A2D(0),1:jpkm1) + xdiatnh4(A2D(0),1:jpkm1) + rtrn ) )   )  &
                &                  * zfact * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "TPNEW", zw3d )  
          DEALLOCATE ( zw3d ) 
       ENDIF
       !
       IF( l_dia_ppbsi ) THEN
          zfact = 1.e+3 * rfact2r  !  conversion from mol/l/kt to  mol/m3/s
          ALLOCATE( zw3d(A2D(0),jpk) )  ;  zw3d(A2D(0),jpk) = 0._wp  
          !  biogenic silica production
          zw3d(A2D(0),1:jpkm1) = zprorcad(A2D(0),1:jpkm1) * zysopt(A2D(0),1:jpkm1) * zfact * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "PBSi", zw3d )  
          DEALLOCATE ( zw3d ) 
       ENDIF
       !
       IF( l_dia_ppbfe ) THEN
          zfact = 1.e+3 * rfact2r  !  conversion from mol/l/kt to  mol/m3/s
          ALLOCATE( zw3d(A2D(0),jpk) )  ;  zw3d(A2D(0),jpk) = 0._wp  
          ! biogenic iron production by nanophyto
          zw3d(A2D(0),1:jpkm1) = zprofen(A2D(0),1:jpkm1) * zfact * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "PFeN", zw3d )  
          ! biogenic iron production by diatomes
          zw3d(A2D(0),1:jpkm1) = zprofed(A2D(0),1:jpkm1) * zfact * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "PFeD", zw3d )  
          ! total biogenic iron production
          zw3d(A2D(0),1:jpkm1) = ( zprofen(A2D(0),1:jpkm1) +  zprofed(A2D(0),1:jpkm1) ) * zfact * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "TPBFE", zw3d )  
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
          ! Realized growth rate for diatoms
          zw3d(A2D(0),1:jpkm1) = zprdia(A2D(0),1:jpkm1) * xlimdia(A2D(0),1:jpkm1) * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "MuD", zw3d )  
          DEALLOCATE ( zw3d ) 
       ENDIF
       !
       IF( l_dia_light ) THEN
          zfact = 1.e+3 * rfact2r  !  conversion from mol/l/kt to  mol/m3/s
          ALLOCATE( zw3d(A2D(0),jpk) )  ;  zw3d(A2D(0),jpk) = 0._wp  
          ! light limitation term for nano
          zw3d(A2D(0),1:jpkm1) = zprbio(A2D(0),1:jpkm1) / ( zprmax(A2D(0),1:jpkm1) + rtrn ) * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "LNlight", zw3d )  
          ! light limitation term for diatomes
          zw3d(A2D(0),1:jpkm1) = zprdia(A2D(0),1:jpkm1) / ( zprmax(A2D(0),1:jpkm1) + rtrn ) * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "LDlight", zw3d )  
          DEALLOCATE ( zw3d ) 
       ENDIF
       !
       IF( l_dia_lprod ) THEN
          zfact = 1.e+3 * rfact2r  !  conversion from mol/l/kt to  mol/m3/s
          ALLOCATE( zw3d(A2D(0),jpk) )  ;  zw3d(A2D(0),jpk) = 0._wp  
          zw3d(A2D(0),1:jpkm1) = ( excretd * zprorcad(A2D(0),1:jpkm1) + excretn * zprorcan(A2D(0),1:jpkm1) ) &
             &                   * zfact * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "LPRODP"  , zw3d * ldocp * 1e9 )
          !
          zw3d(A2D(0),1:jpkm1) = ( texcretn * zprofen(A2D(0),1:jpkm1) + texcretd * zprofed(A2D(0),1:jpkm1) ) & 
            &                  * plig(A2D(0),1:jpkm1) / ( rtrn + plig(A2D(0),1:jpkm1) + 75.0 * (1.0 - plig(A2D(0),1:jpkm1) ) )  &
            &                  * zfact * tmask(A2D(0),1:jpkm1) 
          CALL iom_put( "LDETP"   , zw3d * lthet * 1e9 )
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
      IF( ln_timing )  CALL timing_stop('p4z_prod')
      !
   END SUBROUTINE p4z_prod


   SUBROUTINE p4z_prod_init
      !!----------------------------------------------------------------------
      !!                  ***  ROUTINE p4z_prod_init  ***
      !!
      !! ** Purpose :   Initialization of phytoplankton production parameters
      !!
      !! ** Method  :   Read the namp4zprod namelist and check the parameters
      !!      called at the first timestep (nittrc000)
      !!
      !! ** input   :   Namelist namp4zprod
      !!----------------------------------------------------------------------
      INTEGER ::   ios   ! Local integer
      !
      ! Namelist block
      NAMELIST/namp4zprod/ pislopen, pisloped, bresp, excretn, excretd,  &
         &                 chlcmin, fecnm, fecdm, grosip
      !!----------------------------------------------------------------------
      !
      IF(lwp) THEN                         ! control print
         WRITE(numout,*)
         WRITE(numout,*) 'p4z_prod_init : phytoplankton growth'
         WRITE(numout,*) '~~~~~~~~~~~~~'
      ENDIF
      !
      READ  ( numnatp_ref, namp4zprod, IOSTAT = ios, ERR = 901)
901   IF( ios /= 0 )   CALL ctl_nam ( ios , 'namp4zprod in reference namelist' )

      READ  ( numnatp_cfg, namp4zprod, IOSTAT = ios, ERR = 902 )
902   IF( ios >  0 )   CALL ctl_nam ( ios , 'namp4zprod in configuration namelist' )
      IF(lwm) WRITE( numonp, namp4zprod )

      IF(lwp) THEN                         ! control print
         WRITE(numout,*) '   Namelist : namp4zprod'
         WRITE(numout,*) '      mean Si/C ratio                           grosip       =', grosip
         WRITE(numout,*) '      P-I slope                                 pislopen     =', pislopen
         WRITE(numout,*) '      excretion ratio of nanophytoplankton      excretn      =', excretn
         WRITE(numout,*) '      excretion ratio of diatoms                excretd      =', excretd
         WRITE(numout,*) '      basal respiration in phytoplankton        bresp        =', bresp
         WRITE(numout,*) '      Maximum Chl/C in phytoplankton            chlcmin      =', chlcmin
         WRITE(numout,*) '      P-I slope  for diatoms                    pisloped     =', pisloped
         WRITE(numout,*) '      Maximum Fe/C in nanophytoplankton         fecnm        =', fecnm
         WRITE(numout,*) '      Minimum Fe/C in diatoms                   fecdm        =', fecdm
      ENDIF
      !
      r1_rday   = 1._wp / rday 
      texcretn  = 1._wp - excretn
      texcretd  = 1._wp - excretd
      tpp       = 0._wp
      !
   END SUBROUTINE p4z_prod_init

   INTEGER FUNCTION p4z_prod_alloc()
      !!----------------------------------------------------------------------
      !!                     ***  ROUTINE p4z_prod_alloc  ***
      !!----------------------------------------------------------------------
      ALLOCATE( quotan(A2D(0),jpk), quotad(A2D(0),jpk), STAT = p4z_prod_alloc )
      !
      IF( p4z_prod_alloc /= 0 ) CALL ctl_stop( 'STOP', 'p4z_prod_alloc : failed to allocate arrays.' )
      !
   END FUNCTION p4z_prod_alloc

   !!======================================================================
END MODULE p4zprod
