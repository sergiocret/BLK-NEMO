MODULE sbcblk_algo_ice_lu12
   !!======================================================================
   !!                   ***  MODULE  sbcblk_algo_ice_lu12  ***
   !!       Computes turbulent components of surface fluxes over sea-ice
   !!
   !!  Lüpkes, C., Gryanik, V. M., Hartmann, J., and Andreas, E. L. ( 2012), A parametrization, based on sea ice morphology,
   !!  of the neutral atmospheric drag coefficients for weather prediction and climate models, J. Geophys. Res., 117, D13112,
   !!  doi:10.1029/2012JD017630.
   !!
   !!       => Despite the fact that the sea-ice concentration (frice) must be provided,
   !!          only transfer coefficients, and air temp. + hum. height adjustement
   !!          over ice are returned/performed.
   !!        ==> 'frice' is only here to estimate the form drag caused by sea-ice...
   !!
   !!       Routine turb_ice_lu12 maintained and developed in AeroBulk
   !!                     (https://github.com/brodeau/aerobulk/)
   !!
   !!            Author: Laurent Brodeau, Summer 2020
   !!
   !!----------------------------------------------------------------------
   USE par_kind, ONLY: wp
   USE par_oce,  ONLY: jpi, jpj
   USE phycst          ! physical constants
   USE sbc_phy         ! Catalog of functions for physical/meteorological parameters in the marine boundary layer
   USE sbcblk_algo_ice_cdn

   IMPLICIT NONE
   PRIVATE

   PUBLIC :: turb_ice_lu12

   REAL(wp), PARAMETER :: rz0_i_s_0  = 0.69e-3_wp  ! Eq.(43) of Lupkes & Gryanik (2015) [m] => to estimate CdN10 for skin drag!
   REAL(wp), PARAMETER :: rz0_i_f_0  = 4.54e-4_wp  ! bottom p.562 MIZ [m] (LG15)   

   !! * Substitutions
#  include "do_loop_substitute.h90"
   !!----------------------------------------------------------------------
CONTAINS

   SUBROUTINE turb_ice_lu12( zt, zu, Ts_i, t_zt, qs_i, q_zt, U_zu, frice, &
      &                      Cd_i, Ch_i, Ce_i, t_zu_i, q_zu_i,            &
      &                      CdN, ChN, CeN, xz0, xu_star, xL, xUN10 )
      !!----------------------------------------------------------------------
      !!                      ***  ROUTINE  turb_ice_lu12  ***
      !!
      !! ** Purpose :   Computes turbulent transfert coefficients of surface
      !!                fluxes according to:
      !!                Lüpkes, C., Gryanik, V. M., Hartmann, J., and Andreas, E. L. ( 2012),
      !!                A parametrization, based on sea ice morphology, of the neutral
      !!                atmospheric drag coefficients for weather prediction and climate models,
      !!                J. Geophys. Res., 117, D13112, doi:10.1029/2012JD017630.
      !!
      !! INPUT :
      !! -------
      !!    *  zt   : height for temperature and spec. hum. of air            [m]
      !!    *  zu   : height for wind speed (usually 10m)                     [m]
      !!    *  Ts_i  : surface temperature of sea-ice                         [K]
      !!    *  t_zt : potential air temperature at zt                         [K]
      !!    *  qs_i  : saturation specific humidity at temp. Ts_i over ice    [kg/kg]
      !!    *  q_zt : specific humidity of air at zt                          [kg/kg]
      !!    *  U_zu : scalar wind speed at zu                                 [m/s]
      !!    * frice : sea-ice concentration        (fraction)
      !!
      !! OUTPUT :
      !! --------
      !!    *  Cd_i   : drag coefficient over sea-ice
      !!    *  Ch_i   : sensible heat coefficient over sea-ice
      !!    *  Ce_i   : sublimation coefficient over sea-ice
      !!    *  t_zu_i : pot. air temp. adjusted at zu over sea-ice             [K]
      !!    *  q_zu_i : spec. hum. of air adjusted at zu over sea-ice          [kg/kg]
      !!
      !! OPTIONAL OUTPUT:
      !! ----------------
      !!    * CdN     : neutral-stability drag coefficient
      !!    * ChN     : neutral-stability sensible heat coefficient
      !!    * CeN     : neutral-stability evaporation coefficient
      !!    * xz0     : return the aerodynamic roughness length (integration constant for wind stress) [m]
      !!    * xu_star : return u* the friction velocity                    [m/s]
      !!    * xL      : return the Obukhov length                          [m]
      !!    * xUN10   : neutral wind speed at 10m                          [m/s]
      !!
      !! ** Author: L. Brodeau, January 2020 / AeroBulk (https://github.com/brodeau/aerobulk/)
      !!----------------------------------------------------------------------------------
      REAL(wp), INTENT(in )                    :: zt    ! height for t_zt and q_zt                    [m]
      REAL(wp), INTENT(in )                    :: zu    ! height for U_zu                             [m]
      REAL(wp), INTENT(in ), DIMENSION(A2D(0)) :: Ts_i  ! ice surface temperature                [Kelvin]
      REAL(wp), INTENT(in ), DIMENSION(A2D(0)) :: t_zt  ! potential air temperature              [Kelvin]
      REAL(wp), INTENT(in ), DIMENSION(A2D(0)) :: qs_i  ! sat. spec. hum. at ice/air interface    [kg/kg]
      REAL(wp), INTENT(in ), DIMENSION(A2D(0)) :: q_zt  ! spec. air humidity at zt               [kg/kg]
      REAL(wp), INTENT(in ), DIMENSION(A2D(0)) :: U_zu  ! relative wind module at zu                [m/s]
      REAL(wp), INTENT(in ), DIMENSION(A2D(0)) :: frice ! sea-ice concentration        (fraction)
      REAL(wp), INTENT(out), DIMENSION(A2D(0)) :: Cd_i  ! drag coefficient over sea-ice
      REAL(wp), INTENT(out), DIMENSION(A2D(0)) :: Ch_i  ! transfert coefficient for heat over ice
      REAL(wp), INTENT(out), DIMENSION(A2D(0)) :: Ce_i  ! transfert coefficient for sublimation over ice
      REAL(wp), INTENT(out), DIMENSION(A2D(0)) :: t_zu_i ! pot. air temp. adjusted at zu               [K]
      REAL(wp), INTENT(out), DIMENSION(A2D(0)) :: q_zu_i ! spec. humidity adjusted at zu           [kg/kg]
      !!----------------------------------------------------------------------------------
      REAL(wp), INTENT(out), DIMENSION(A2D(0)), OPTIONAL :: CdN
      REAL(wp), INTENT(out), DIMENSION(A2D(0)), OPTIONAL :: ChN
      REAL(wp), INTENT(out), DIMENSION(A2D(0)), OPTIONAL :: CeN
      REAL(wp), INTENT(out), DIMENSION(A2D(0)), OPTIONAL :: xz0  ! Aerodynamic roughness length   [m]
      REAL(wp), INTENT(out), DIMENSION(A2D(0)), OPTIONAL :: xu_star  ! u*, friction velocity
      REAL(wp), INTENT(out), DIMENSION(A2D(0)), OPTIONAL :: xL  ! zeta (zu/L)
      REAL(wp), INTENT(out), DIMENSION(A2D(0)), OPTIONAL :: xUN10  ! Neutral wind at zu
      !!----------------------------------------------------------------------------------
      REAL(wp), DIMENSION(:,:), ALLOCATABLE :: dt_zu, dq_zu, z0
      REAL(wp), DIMENSION(:,:), ALLOCATABLE :: Ubzu
      !!
      LOGICAL :: lreturn_cdn=.FALSE., lreturn_chn=.FALSE., lreturn_cen=.FALSE.
      LOGICAL :: lreturn_z0=.FALSE., lreturn_ustar=.FALSE., lreturn_L=.FALSE., lreturn_UN10=.FALSE.
      !!
      CHARACTER(len=40), PARAMETER :: crtnm = 'turb_ice_lu12@sbcblk_algo_ice_lu12.f90'
      !!----------------------------------------------------------------------------------
      ALLOCATE ( Ubzu(A2D(0)) )
      ALLOCATE ( dt_zu(A2D(0)), dq_zu(A2D(0)), z0(A2D(0)) )

      lreturn_cdn   = PRESENT(CdN)
      lreturn_chn   = PRESENT(ChN)
      lreturn_cen   = PRESENT(CeN)
      lreturn_z0    = PRESENT(xz0)
      lreturn_ustar = PRESENT(xu_star)
      lreturn_L     = PRESENT(xL)
      lreturn_UN10  = PRESENT(xUN10)

      !! Scalar wind speed cannot be below 0.2 m/s
      Ubzu = MAX( U_zu, wspd_thrshld_ice )

      !! First guess of temperature and humidity at height zu:
      t_zu_i = MAX( t_zt ,   100._wp )   ! who knows what's given on masked-continental regions...
      q_zu_i = MAX( q_zt , 0.1e-6_wp )   !               "

      !! Air-Ice & Air-Sea differences (and we don't want them to be 0!)
      dt_zu = t_zu_i - Ts_i ;   dt_zu = SIGN( MAX(ABS(dt_zu),1.E-6_wp), dt_zu )
      dq_zu = q_zu_i - qs_i ;   dq_zu = SIGN( MAX(ABS(dq_zu),1.E-9_wp), dq_zu )

      !! To estimate CDN10_skin:
      !!  we use the method that comes in LG15, i.e. by starting from a default roughness length z0 for skin drag:

      Ce_i(:,:) = rz0_i_s_0 !! temporary array to contain roughness length for skin drag !


      !! Method #1:
      !Cd_i(:,:) = Cd_from_z0( zu, Ce_i(:,:) )  + CdN10_f_LU13( frice(:,:) )
      !IF( lreturn_cdfrm ) CdN_frm = CdN10_f_LU13( frice(:,:) )
      !PRINT *, 'LOLO: estimate of Cd_f_i method #1 =>', CdN10_f_LU13( frice(:,:) ); PRINT *, ''

      !! Method #2:
      !! We need an estimate of z0 over water:
      !z0_w(:,:) = z0_from_Cd( zu, CD_N10_NCAR(Ubzu) )
      !!PRINT *, 'LOLO: estimate of z0_w =>', z0_w
      !Cd_i(:,:)   = Cd_from_z0( zu, Ce_i(:,:) )  + CdN10_f_LU12( frice(:,:), z0_w(:,:) )
      !IF( lreturn_cdfrm ) CdN_frm =  CdN10_f_LU12( frice(:,:), z0_w(:,:) )
      !!          N10 skin drag                     N10 form drag

      !! Method #3:
      !Cd_i(:,:)   = Cd_from_z0( zu, Ce_i(:,:) ) + CdN10_f_LU12_eq36( frice(:,:) )
      !IF( lreturn_cdfrm ) CdN_frm = CdN10_f_LU12_eq36( frice(:,:) )
      !PRINT *, 'LOLO: estimate of Cd_f_i method #2 =>', CdN10_f_LU12( frice(:,:), z0_w(:,:) )

      !! Method #4:
      !! using eq.21 of LG15 instead:
      z0(:,:) = rz0_i_f_0
      !Cd_i(:,:)   = Cd_from_z0( zu, Ce_i(:,:) )  + CdN_f_LG15( zu, frice(:,:), z0(:,:) ) / frice(:,:)
      Cd_i(:,:)   = Cd_from_z0( zu, Ce_i(:,:) )  + CdN_f_LG15( zu, frice(:,:), z0(:,:) ) !/ frice(:,:)
      !IF( lreturn_cdfrm ) CdN_frm = CdN_f_LG15( zu, frice(:,:), z0(:,:) )


      Ch_i(:,:) = Cd_i(:,:)
      Ce_i(:,:) = Cd_i(:,:)

      IF( lreturn_cdn )   CdN = Cd_i(:,:)
      IF( lreturn_chn )   ChN = Ch_i(:,:)
      IF( lreturn_cen )   CeN = Ce_i(:,:)

      IF( lreturn_z0 )    xz0     = z0_from_Cd( zu, Cd_i )
      IF( lreturn_ustar ) xu_star = SQRT(Cd_i)*Ubzu
      IF( lreturn_L )     xL      = 1./One_on_L(t_zu_i, q_zu_i, SQRT(Cd_i)*Ubzu, &
         &                          Cd_i/SQRT(Cd_i)*dt_zu, Cd_i/SQRT(Cd_i)*dq_zu)
      IF( lreturn_UN10 )  xUN10   = SQRT(Cd_i)*Ubzu/vkarmn * LOG( 10._wp / z0_from_Cd( zu, Cd_i ) )

      DEALLOCATE ( dt_zu, dq_zu, z0 )
      DEALLOCATE ( Ubzu )

   END SUBROUTINE turb_ice_lu12

   !!======================================================================
END MODULE sbcblk_algo_ice_lu12
