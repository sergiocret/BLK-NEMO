MODULE sbcblk_algo_ice_lg15
   !!======================================================================
   !!                   ***  MODULE  sbcblk_algo_ice_lg15  ***
   !!       Computes turbulent components of surface fluxes over sea-ice
   !!
   !!
   !!  Lüpkes, C., and Gryanik, V. M. ( 2015), A stability‐dependent parametrization
   !!  of transfer coefficients for momentum and heat over polar sea ice to be used in climate models,
   !!  J. Geophys. Res. Atmos., 120, 552– 581, doi:10.1002/2014JD022418.
   !!
   !!       => Despite the fact that the sea-ice concentration (frice) must be provided,
   !!          only transfer coefficients, and air temp. + hum. height adjustement
   !!          over ice are returned/performed.
   !!        ==> 'frice' is only here to estimate the form drag caused by sea-ice...
   !!
   !!       Routine turb_ice_lg15 maintained and developed in AeroBulk
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

   PUBLIC :: turb_ice_lg15

   REAL(wp), PARAMETER ::   ralpha_0  = 0.2_wp     ! (Eq.12) (ECHAM6 value)

   !! To be namelist parameters in NEMO:
   REAL(wp), PARAMETER :: rz0_i_s_0  = 0.69e-3_wp  !           Eq. 43 [m]
   REAL(wp), PARAMETER :: rz0_i_f_0  = 4.54e-4_wp  ! bottom p.562 MIZ [m]

   LOGICAL,  PARAMETER :: l_add_form_drag = .TRUE.
   LOGICAL,  PARAMETER :: l_use_pond_info = .FALSE.
   LOGICAL,  PARAMETER :: l_dbg_print     = .FALSE.

   INTEGER , PARAMETER ::   nbit = 8        ! number of itterations

   !! * Substitutions
#  include "do_loop_substitute.h90"
   !!----------------------------------------------------------------------
CONTAINS

   SUBROUTINE turb_ice_lg15( zt, zu, Ts_i, t_zt, qs_i, q_zt, U_zu, frice, &
      &                      Cd_i, Ch_i, Ce_i, t_zu_i, q_zu_i,            &
      &                      CdN, ChN, CeN, xz0, xu_star, xL, xUN10 )
      !!----------------------------------------------------------------------
      !!                      ***  ROUTINE  turb_ice_lg15  ***
      !!
      !! ** Purpose :   Computes turbulent transfert coefficients of surface
      !!                fluxes according to:
      !!            Lüpkes, C., and Gryanik, V. M. ( 2015), A stability‐dependent
      !!            parametrization of transfer coefficients for momentum and heat
      !!            over polar sea ice to be used in climate models,
      !!            J. Geophys. Res. Atmos., 120, 552– 581, doi:10.1002/2014JD022418.
      !!
      !!           If relevant (zt /= zu), adjust temperature and humidity from height zt to zu
      !!           Returns the effective bulk wind speed at zu to be used in the bulk formulas
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
      REAL(wp), DIMENSION(:,:), ALLOCATABLE :: Ubzu
      REAL(wp), DIMENSION(:,:), ALLOCATABLE :: ztmp1, ztmp2      ! temporary stuff
      REAL(wp), DIMENSION(:,:), ALLOCATABLE :: dt_zu, dq_zu
      REAL(wp), DIMENSION(:,:), ALLOCATABLE :: zz0_s, zz0_f, RiB ! third dimensions (size=2):
      REAL(wp), DIMENSION(:,:), ALLOCATABLE :: zCdN_s, zChN_s, zCdN_f, zChN_f
      !!
      INTEGER :: jit
      LOGICAL :: l_zt_equal_zu = .FALSE.      ! if q and t are given at same height as U
      !!
      LOGICAL :: lreturn_cdn=.FALSE., lreturn_chn=.FALSE., lreturn_cen=.FALSE.
      LOGICAL :: lreturn_z0=.FALSE., lreturn_ustar=.FALSE., lreturn_L=.FALSE., lreturn_UN10=.FALSE.
      !!
      CHARACTER(len=40), PARAMETER :: crtnm = 'turb_ice_lg15@sbcblk_algo_ice_lg15.f90'
      !!----------------------------------------------------------------------------------
      ALLOCATE ( Ubzu(A2D(0)) )
      ALLOCATE ( ztmp1(A2D(0)),  ztmp2(A2D(0)) )
      ALLOCATE ( dt_zu(A2D(0)),  dq_zu(A2D(0)) )
      ALLOCATE ( zz0_s(A2D(0)),  zz0_f(A2D(0)),    RiB(A2D(0)), &
         &      zCdN_s(A2D(0)), zChN_s(A2D(0)), zCdN_f(A2D(0)), zChN_f(A2D(0)) )

      lreturn_cdn   = PRESENT(CdN)
      lreturn_chn   = PRESENT(ChN)
      lreturn_cen   = PRESENT(CeN)
      lreturn_z0    = PRESENT(xz0)
      lreturn_ustar = PRESENT(xu_star)
      lreturn_L     = PRESENT(xL)
      lreturn_UN10  = PRESENT(xUN10)

      l_zt_equal_zu = ( ABS(zu - zt) < 0.01_wp )

      !! Scalar wind speed cannot be below 0.2 m/s
      Ubzu = MAX( U_zu, wspd_thrshld_ice )

      !! First guess of temperature and humidity at height zu:
      t_zu_i = MAX( t_zt ,   100._wp )   ! who knows what's given on masked-continental regions...
      q_zu_i = MAX( q_zt , 0.1e-6_wp )   !               "

      !! Air-Ice & Air-Sea differences (and we don't want them to be 0!)
      dt_zu = t_zu_i - Ts_i ;   dt_zu = SIGN( MAX(ABS(dt_zu),1.E-6_wp), dt_zu )
      dq_zu = q_zu_i - qs_i ;   dq_zu = SIGN( MAX(ABS(dq_zu),1.E-9_wp), dq_zu )

      !! Very crude first guess:
      Cd_i(:,:) = 1.4e-3_wp
      Ch_i(:,:) = 1.4e-3_wp
      Ce_i(:,:) = 1.4e-3_wp
      
      !! For skin drag :
      zz0_s(:,:)  = rz0_i_s_0        !#LB/RFI! ! Room for improvement. We use the same z0_skin everywhere (= rz0_i_s_0)...
      zCdN_s(:,:) = Cd_from_z0( zu, zz0_s(:,:) )
      zChN_s(:,:) = vkarmn2 / ( LOG( zu / zz0_s(:,:) ) * LOG( zu / (ralpha_0*zz0_s(:,:)) ) )     ! (Eq.11,12)  [ "" ]
      
      !! For form drag in MIZ:
      zz0_f(:,:)  = 0._wp
      zCdN_f(:,:) = 0._wp
      zChN_f(:,:) = 0._wp
      IF ( l_add_form_drag ) THEN
         zz0_f(:,:)  = rz0_i_f_0        !#LB/RFI! ! Room for improvement. We use the same z0_form everywhere !!!
         zCdN_f(:,:) = CdN_f_LG15_light( zu, frice(:,:), zz0_f(:,:) )
         zChN_f(:,:) = zCdN_f(:,:)/( 1._wp + LOG(1._wp/ralpha_0)/vkarmn*SQRT(zCdN_f(:,:)) ) ! (Eq.60,61)   [ "" ]
      END IF

      !! Some other first guess values, needed to compute wind at zt:
      Cd_i(:,:) = zCdN_s(:,:) + zCdN_f(:,:)
      Ch_i(:,:) = zChN_s(:,:) + zChN_f(:,:)
      RiB(:,:) = Ri_bulk( zt, Ts_i(:,:), t_zt(:,:), qs_i(:,:), q_zt(:,:), Ubzu(:,:) )  ! over ice (index=1)


      !! ITERATION BLOCK
      DO jit = 1, nbit

         IF(l_dbg_print) PRINT *, 'LOLO: LOOP #', INT(jit,1)
         IF(l_dbg_print) PRINT *, 'LOLO: theta_zu, Ts_i, Ubzu =', REAL(t_zu_i(:,:),4), REAL(Ts_i(:,:),4), REAL(Ubzu(:,:),4)
         IF(l_dbg_print) PRINT *, 'LOLO:     q_zu =', REAL(q_zu_i(:,:),4)
         IF(l_dbg_print) PRINT *, 'LOLO:  CdN_s, zCdN_f   =', REAL(zCdN_s(:,:),4), REAL(zCdN_f(:,:),4)


         !! Bulk Richardson Number
         !! ======================
         !! PROBLEM: when computed at z=zu, with adjusted theta and q, it is numerically unstable in some rare events (unstable)
         !!          => fix: compute RiB at zt, with ajusted wind at zt... => seems to be more stable
         IF( .NOT. l_zt_equal_zu ) THEN
            ! U_zt = U_zu + u_star/vkarmn*(LOG(zt/zu) + psi_m_coare(zu/L) - psi_m_coare(zt/L))
            ztmp1(:,:) = zCdN_s(:,:) + zCdN_f(:,:)    ! total neutral drag coeff!
            ztmp2(:,:) = zz0_s(:,:) + zz0_f(:,:)      ! total roughness length z0
            ztmp1 = LOG(zt/zu) + f_h_louis( zu, RiB(:,:), ztmp1(:,:), ztmp2(:,:) ) &
               &               - f_h_louis( zt, RiB(:,:), ztmp1(:,:), ztmp2(:,:) )
            ztmp2(:,:) = MAX( Ubzu(:,:) + (SQRT(Cd_i(:,:))*Ubzu)*ztmp1 , wspd_thrshld_ice ) ! wind at zt ( SQRT(Cd_i(:,:))*Ubzu == u* !)
            ztmp2(:,:) = MIN( ztmp2(:,:) , Ubzu(:,:) )
            IF(l_dbg_print) PRINT *, 'LOLO: ADJUSTED WIND AT ZT =', ztmp2
         ELSE
            ztmp2(:,:) = Ubzu(:,:)
         END IF
         RiB(:,:) = Ri_bulk( zt, Ts_i(:,:), t_zt(:,:), qs_i(:,:), q_zt(:,:), ztmp2(:,:) )  ! over ice (index=1)
         IF(l_dbg_print) PRINT *, 'LOLO: RiB_zt =', RiB(:,:)


         ! Momentum and Heat transfer coefficients WITHOUT FORM DRAG / (Eq.6) and (Eq.10):
         Cd_i(:,:) = zCdN_s(:,:) * f_m_louis( zu, RiB(:,:), zCdN_s(:,:), zz0_s(:,:) ) ! (Eq.6)
         Ch_i(:,:) = zChN_s(:,:) * f_h_louis( zu, RiB(:,:), zCdN_s(:,:), zz0_s(:,:) ) ! (Eq.10) / LOLO: why "zCdN_s" (ztmp1) and not "zChn" ???
         IF(l_dbg_print) PRINT *, 'LOLO: f_m_louis_s =', f_m_louis( zu, RiB(:,:), zCdN_s(:,:), zz0_s(:,:) )
         IF(l_dbg_print) PRINT *, 'LOLO: f_h_louis_s =', f_h_louis( zu, RiB(:,:), zCdN_s(:,:), zz0_s(:,:) )
         IF(l_dbg_print) PRINT *, 'LOLO: Cd / skin only / ice   =', REAL(Cd_i(:,:),4)

         
         IF ( l_add_form_drag ) THEN
            !! Form-drag-related NEUTRAL momentum and Heat transfer coefficients:
            !!   MIZ:
            Cd_i(:,:) = Cd_i(:,:) + zCdN_f(:,:) * f_m_louis( zu, RiB(:,:), zCdN_f(:,:), zz0_f(:,:) ) ! (Eq.6)
            Ch_i(:,:) = Ch_i(:,:) + zChN_f(:,:) * f_h_louis( zu, RiB(:,:), zCdN_f(:,:), zz0_f(:,:) ) ! (Eq.10) / LOLO: why "zCdN_f" and not "zChn" ???
            IF(l_dbg_print) PRINT *, 'LOLO: f_m_louis_f =', f_m_louis( zu, RiB(:,:), zCdN_f(:,:), zz0_f(:,:) )
            IF(l_dbg_print) PRINT *, 'LOLO: f_h_louis_f =', f_h_louis( zu, RiB(:,:), zCdN_f(:,:), zz0_f(:,:) )

            IF(l_dbg_print) PRINT *, 'LOLO: Cd / form only / ice   =', REAL(zCdN_f(:,:) * f_m_louis( zu, RiB(:,:), zCdN_f(:,:), zz0_f(:,:) ),4)

         END IF

         IF(l_dbg_print) PRINT *, 'LOLO: Cd, Ch / TOTAL / ice   =', REAL(Cd_i(:,:),4), REAL(Ch_i(:,:),4)


         !! Adjusting temperature and humidity from zt to zu:
         IF( .NOT. l_zt_equal_zu ) THEN

            !! Over ice:
            ztmp1(:,:) = zCdN_s(:,:) + zCdN_f(:,:)    ! total neutral drag coeff!
            ztmp2(:,:) = zz0_s(:,:) + zz0_f(:,:)      ! total roughness length z0
            ztmp1 = LOG(zt/zu) + f_h_louis( zu, RiB(:,:), ztmp1(:,:), ztmp2(:,:) ) &
               &               - f_h_louis( zt, RiB(:,:), ztmp1(:,:), ztmp2(:,:) )
            ztmp2 = 1._wp/SQRT(Cd_i(:,:))

            t_zu_i(:,:) = t_zt - (Ch_i(:,:) * dt_zu(:,:) * ztmp2) / vkarmn * ztmp1   ! t_star = Ch * dt_zu / SQRT(Cd)
            q_zu_i(:,:) = q_zt - (Ch_i(:,:) * dq_zu(:,:) * ztmp2) / vkarmn * ztmp1   ! q_star = Ce * dq_zu / SQRT(Cd)
            q_zu_i(:,:) = MAX(0._wp, q_zu_i(:,:))

            dt_zu(:,:) = t_zu_i(:,:) - Ts_i
            dq_zu(:,:) = q_zu_i(:,:) - qs_i

            dt_zu = SIGN( MAX(ABS(dt_zu),1.E-6_wp), dt_zu )
            dq_zu = SIGN( MAX(ABS(dq_zu),1.E-9_wp), dq_zu )
         END IF

         IF(l_dbg_print) PRINT *, ''!LOLO

      END DO !DO jit = 1, nbit

      Ce_i(:,:)   =  Ch_i(:,:)

      IF( lreturn_cdn )   CdN = zCdN_s(:,:)+zCdN_f(:,:)
      IF( lreturn_chn )   ChN = zChN_s(:,:)+zChN_f(:,:)
      IF( lreturn_cen )   CeN = zChN_s(:,:)+zChN_f(:,:)

      IF( lreturn_z0 ) xz0   = z0_from_Cd( zu, zCdN_s(:,:)+zCdN_f(:,:) )

      IF( lreturn_ustar ) xu_star = SQRT(Cd_i) * Ubzu

      IF( lreturn_L ) THEN
         ztmp1 = SQRT(Cd_i)
         xL    = 1./One_on_L( t_zu_i, q_zu_i, ztmp1*Ubzu, Ch_i*dt_zu(:,:)/ztmp1, Ce_i*dq_zu(:,:)/ztmp1 )
      END IF

      IF( lreturn_UN10 ) THEN
         ztmp1 = zCdN_s(:,:) + zCdN_f(:,:)  ! => CdN
         xUN10 = SQRT(Cd_i) * Ubzu/vkarmn * LOG( 10._wp / z0_from_Cd(zu, ztmp1) )
      END IF

      DEALLOCATE ( Ubzu )
      DEALLOCATE ( ztmp1, ztmp2 )
      DEALLOCATE ( dt_zu, dq_zu )
      DEALLOCATE ( zz0_s, zz0_f, RiB, zCdN_s, zChN_s, zCdN_f, zChN_f )

   END SUBROUTINE turb_ice_lg15

   !!======================================================================
END MODULE sbcblk_algo_ice_lg15
