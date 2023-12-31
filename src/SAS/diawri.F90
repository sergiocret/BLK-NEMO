MODULE diawri
   !!======================================================================
   !!                     ***  MODULE  diawri  ***
   !! Ocean diagnostics :  write ocean output files
   !!=====================================================================
   !! History :  OPA  ! 1991-03  (M.-A. Foujols)  Original code
   !!            4.0  ! 1991-11  (G. Madec)
   !!                 ! 1992-06  (M. Imbard)  correction restart file
   !!                 ! 1992-07  (M. Imbard)  split into diawri and rstwri
   !!                 ! 1993-03  (M. Imbard)  suppress writibm
   !!                 ! 1998-01  (C. Levy)  NETCDF format using ioipsl INTERFACE
   !!                 ! 1999-02  (E. Guilyardi)  name of netCDF files + variables
   !!            8.2  ! 2000-06  (M. Imbard)  Original code (diabort.F)
   !!   NEMO     1.0  ! 2002-06  (A.Bozec, E. Durand)  Original code (diainit.F)
   !!             -   ! 2002-09  (G. Madec)  F90: Free form and module
   !!             -   ! 2002-12  (G. Madec)  merge of diabort and diainit, F90
   !!                 ! 2005-11  (V. Garnier) Surface pressure gradient organization
   !!            3.2  ! 2008-11  (B. Lemaire) creation from old diawri
   !!----------------------------------------------------------------------

   !!----------------------------------------------------------------------
   !!   dia_wri       : create the standart output files
   !!   dia_wri_state : create an output NetCDF file for a single instantaeous ocean state and forcing fields
   !!----------------------------------------------------------------------
   USE oce             ! ocean dynamics and tracers 
   USE abl            ! abl variables in case ln_abl = .true.
   USE dom_oce         ! ocean space and time domain
   USE zdf_oce         ! ocean vertical physics
   USE sbc_oce         ! Surface boundary condition: ocean fields
   USE sbc_ice         ! Surface boundary condition: ice fields
   USE sbcssr          ! restoring term toward SST/SSS climatology
   USE phycst          ! physical constants
   USE zdfmxl          ! mixed layer
   USE dianam          ! build name of file (routine)
   USE zdfddm          ! vertical  physics: double diffusion
   USE diahth          ! thermocline diagnostics
   USE lbclnk          ! ocean lateral boundary conditions (or mpp link)
   USE in_out_manager  ! I/O manager
   USE iom
   USE ioipsl
#if defined key_si3
   USE ice
   USE icewri
#endif
   USE lib_mpp         ! MPP library
   USE timing          ! preformance summary

   IMPLICIT NONE
   PRIVATE

   PUBLIC   dia_wri                 ! routines called by step.F90
   PUBLIC   dia_wri_state
   PUBLIC   dia_wri_alloc           ! Called by nemogcm module
#if ! defined key_xios   
   PUBLIC   dia_wri_alloc_abl       ! Called by sbcabl  module (if ln_abl = .true.)
#endif
   INTEGER ::   nid_T, nz_T, nh_T, ndim_T, ndim_hT   ! grid_T file
   INTEGER ::   nid_U, nz_U, nh_U, ndim_U, ndim_hU   ! grid_U file
   INTEGER ::   nid_V, nz_V, nh_V, ndim_V, ndim_hV   ! grid_V file
   INTEGER ::   ndim_A, ndim_hA                      ! ABL file   
   INTEGER ::   nid_A, nz_A, nh_A                    ! grid_ABL file   
   INTEGER ::   ndex(1)                              ! ???
   INTEGER, SAVE, ALLOCATABLE, DIMENSION(:) :: ndex_hT, ndex_hU, ndex_hV
   INTEGER, SAVE, ALLOCATABLE, DIMENSION(:) :: ndex_hA, ndex_A ! ABL

   !!----------------------------------------------------------------------
   !! NEMO/SAS 4.0 , NEMO Consortium (2018)
   !! $Id: diawri.F90 14239 2020-12-23 08:57:16Z smasson $
   !! Software governed by the CeCILL license (see ./LICENSE)
   !!----------------------------------------------------------------------
CONTAINS

# if defined key_xios
   !!----------------------------------------------------------------------
   !!   'key_xios'                                        use IOM library
   !!----------------------------------------------------------------------
   INTEGER FUNCTION dia_wri_alloc()
      !
      dia_wri_alloc = 0
      !
   END FUNCTION dia_wri_alloc

   
   SUBROUTINE dia_wri( kt, Kmm )
      !!---------------------------------------------------------------------
      !!                  ***  ROUTINE dia_wri  ***
      !!                   
      !! ** Purpose :   Standard output of opa: dynamics and tracer fields 
      !!      NETCDF format is used by default 
      !!      Standalone surface scheme 
      !!
      !! ** Method  :  use iom_put
      !!----------------------------------------------------------------------
      !!
      INTEGER, INTENT( in ) ::   kt      ! ocean time-step index
      INTEGER, INTENT( in ) ::   Kmm     ! ocean time levelindex
      !!----------------------------------------------------------------------
      ! 
      ! Output the initial state and forcings
      IF( ninist == 1 ) THEN
         CALL dia_wri_state( Kmm, 'output.init' )
         ninist = 0
      ENDIF
      !
   END SUBROUTINE dia_wri

#else
   !!----------------------------------------------------------------------
   !!   Default option                                  use IOIPSL  library
   !!----------------------------------------------------------------------
   INTEGER FUNCTION dia_wri_alloc()
      !!----------------------------------------------------------------------
      INTEGER :: ierr
      !!----------------------------------------------------------------------
      !
      ALLOCATE( ndex_hT(jpi*jpj), ndex_hU(jpi*jpj), ndex_hV(jpi*jpj), STAT=dia_wri_alloc )
      CALL mpp_sum( 'diawri', dia_wri_alloc )
      !
   END FUNCTION dia_wri_alloc
   
   INTEGER FUNCTION dia_wri_alloc_abl()
      !!----------------------------------------------------------------------
	  ALLOCATE(   ndex_hA(jpi*jpj), ndex_A (jpi*jpj*jpkam1), STAT=dia_wri_alloc_abl)
      CALL mpp_sum( 'diawri', dia_wri_alloc_abl )
      !
   END FUNCTION dia_wri_alloc_abl
  
   SUBROUTINE dia_wri( kt, Kmm )
      !!---------------------------------------------------------------------
      !!                  ***  ROUTINE dia_wri  ***
      !!                   
      !! ** Purpose :   Standard output of opa: dynamics and tracer fields 
      !!      NETCDF format is used by default 
      !!
      !! ** Method  :   At the beginning of the first time step (nit000), 
      !!      define all the NETCDF files and fields
      !!      At each time step call histdef to compute the mean if ncessary
      !!      Each nn_write time step, output the instantaneous or mean fields
      !!----------------------------------------------------------------------
      INTEGER, INTENT( in ) ::   kt      ! ocean time-step index
      INTEGER, INTENT( in ) ::   Kmm     ! ocean time level index
      !!
      LOGICAL ::   ll_print = .FALSE.                        ! =T print and flush numout
      CHARACTER (len=40) ::   clhstnam, clop, clmx           ! local names
      INTEGER  ::   inum = 11                                ! temporary logical unit
      INTEGER  ::   ji, jj, jk                               ! dummy loop indices
      INTEGER  ::   ierr                                     ! error code return from allocation
      INTEGER  ::   iimi, iima, ipk, it, itmod, ijmi, ijma   ! local integers
      INTEGER  ::   ipka                                     ! ABL
      REAL(wp) ::   zsto, zout, zmax, zjulian                ! local scalars
      REAL(wp), DIMENSION(:,:,:), ALLOCATABLE :: zw3d_abl   ! ABL 3D workspace
      !!----------------------------------------------------------------------
      !
      ! Output the initial state and forcings
      IF( ninist == 1 ) THEN                       
         CALL dia_wri_state( Kmm, 'output.init' )
         ninist = 0
      ENDIF
      !
      IF( nn_write == -1 )   RETURN   ! we will never do any output
      ! 
      IF( ln_timing )   CALL timing_start('dia_wri')
      !
      ! 0. Initialisation
      ! -----------------

      ! local variable for debugging
      ll_print = .FALSE.
      ll_print = ll_print .AND. lwp

      ! Define frequency of output and means
      IF( ln_mskland )   THEN   ;   clop = "only(x)"   ! put 1.e+20 on land (very expensive!!)
      ELSE                      ;   clop = "x"         ! no use of the mask value (require less cpu time)
      ENDIF
#if defined key_diainstant
      zsto = nn_write * rn_Dt
      clop = "inst("//TRIM(clop)//")"
#else
      zsto=rn_Dt
      clop = "ave("//TRIM(clop)//")"
#endif
      zout = nn_write * rn_Dt
      zmax = ( nitend - nit000 + 1 ) * rn_Dt

      ! Define indices of the horizontal output zoom and vertical limit storage
      iimi = 1      ;      iima = jpi
      ijmi = 1      ;      ijma = jpj
      ipk = jpk
	  IF(ln_abl) ipka = jpkam1

      ! define time axis
      it = kt
      itmod = kt - nit000 + 1


      ! 1. Define NETCDF files and fields at beginning of first time step
      ! -----------------------------------------------------------------

      IF( kt == nit000 ) THEN

         ! Define the NETCDF files (one per grid)

         ! Compute julian date from starting date of the run
         CALL ymds2ju( nyear, nmonth, nday, rn_Dt, zjulian )
         zjulian = zjulian - adatrj   !   set calendar origin to the beginning of the experiment
         IF(lwp)WRITE(numout,*)
         IF(lwp)WRITE(numout,*) 'Date 0 used :', nit000, ' YEAR ', nyear,   &
            &                    ' MONTH ', nmonth, ' DAY ', nday, 'Julian day : ', zjulian
         IF(lwp)WRITE(numout,*) ' indexes of zoom = ', iimi, iima, ijmi, ijma,   &
                                 ' limit storage in depth = ', ipk

         ! WRITE root name in date.file for use by postpro
         IF(lwp) THEN
            CALL dia_nam( clhstnam, nn_write,' ' )
            CALL ctl_opn( inum, 'date.file', 'REPLACE', 'FORMATTED', 'SEQUENTIAL', -1, numout, lwp, narea )
            WRITE(inum,*) clhstnam
            CLOSE(inum)
         ENDIF

         ! Define the T grid FILE ( nid_T )

         CALL dia_nam( clhstnam, nn_write, 'grid_T' )
         IF(lwp) WRITE(numout,*) " Name of NETCDF file ", clhstnam    ! filename
         CALL histbeg( clhstnam, jpi, glamt, jpj, gphit,           &  ! Horizontal grid: glamt and gphit
            &          iimi, iima-iimi+1, ijmi, ijma-ijmi+1,       &
            &          nit000-1, zjulian, rn_Dt, nh_T, nid_T, domain_id=nidom, snc4chunks=snc4set )
         CALL histvert( nid_T, "deptht", "Vertical T levels",      &  ! Vertical grid: gdept
            &           "m", ipk, gdept_1d, nz_T, "down" )
         !                                                            ! Index of ocean points
         CALL wheneq( jpi*jpj    , tmask, 1, 1., ndex_hT, ndim_hT )      ! surface

         ! Define the U grid FILE ( nid_U )

         CALL dia_nam( clhstnam, nn_write, 'grid_U' )
         IF(lwp) WRITE(numout,*) " Name of NETCDF file ", clhstnam    ! filename
         CALL histbeg( clhstnam, jpi, glamu, jpj, gphiu,           &  ! Horizontal grid: glamu and gphiu
            &          iimi, iima-iimi+1, ijmi, ijma-ijmi+1,       &
            &          nit000-1, zjulian, rn_Dt, nh_U, nid_U, domain_id=nidom, snc4chunks=snc4set )
         CALL histvert( nid_U, "depthu", "Vertical U levels",      &  ! Vertical grid: gdept
            &           "m", ipk, gdept_1d, nz_U, "down" )
         !                                                            ! Index of ocean points
         CALL wheneq( jpi*jpj    , umask, 1, 1., ndex_hU, ndim_hU )      ! surface

         ! Define the V grid FILE ( nid_V )

         CALL dia_nam( clhstnam, nn_write, 'grid_V' )                   ! filename
         IF(lwp) WRITE(numout,*) " Name of NETCDF file ", clhstnam
         CALL histbeg( clhstnam, jpi, glamv, jpj, gphiv,           &  ! Horizontal grid: glamv and gphiv
            &          iimi, iima-iimi+1, ijmi, ijma-ijmi+1,       &
            &          nit000-1, zjulian, rn_Dt, nh_V, nid_V, domain_id=nidom, snc4chunks=snc4set )
         CALL histvert( nid_V, "depthv", "Vertical V levels",      &  ! Vertical grid : gdept
            &          "m", ipk, gdept_1d, nz_V, "down" )
         !                                                            ! Index of ocean points
         CALL wheneq( jpi*jpj    , vmask, 1, 1., ndex_hV, ndim_hV )      ! surface

         ! No W grid FILE
         IF( ln_abl ) THEN 
         ! Define the ABL grid FILE ( nid_A )
            CALL dia_nam( clhstnam, nn_write, 'grid_ABL' )
            IF(lwp) WRITE(numout,*) " Name of NETCDF file ", clhstnam    ! filename
            CALL histbeg( clhstnam, jpi, glamt, jpj, gphit,           &  ! Horizontal grid: glamt and gphit
               &          iimi, iima-iimi+1, ijmi, ijma-ijmi+1,       &
               &          nit000-1, zjulian, rn_Dt, nh_A, nid_A, domain_id=nidom, snc4chunks=snc4set )
            CALL histvert( nid_A, "ght_abl", "Vertical T levels",      &  ! Vertical grid: gdept
               &           "m", ipka, ght_abl(2:jpka), nz_A, "up" )
            !                                                            ! Index of ocean points
			ALLOCATE( zw3d_abl(jpi,jpj,ipka) ) 
			zw3d_abl(:,:,:) = 1._wp 
			CALL wheneq( jpi*jpj*ipka, zw3d_abl, 1, 1., ndex_A , ndim_A  )      ! volume
            CALL wheneq( jpi*jpj     , zw3d_abl, 1, 1., ndex_hA, ndim_hA )      ! surface
			DEALLOCATE(zw3d_abl)
         ENDIF

         ! Declare all the output fields as NETCDF variables

         !                                                                                      !!! nid_T : 3D
         CALL histdef( nid_T, "sst_m", "Sea Surface temperature"            , "C"      ,   &  ! sst
            &          jpi, jpj, nh_T, 1  , 1, 1  , -99 , 32, clop, zsto, zout )
         CALL histdef( nid_T, "sss_m", "Sea Surface Salinity"               , "PSU"    ,   &  ! sss
            &          jpi, jpj, nh_T, 1  , 1, 1  , -99 , 32, clop, zsto, zout )
         CALL histdef( nid_T, "sowaflup", "Net Upward Water Flux"              , "Kg/m2/s",   &  ! (emp-rnf)
            &          jpi, jpj, nh_T, 1  , 1, 1  , -99 , 32, clop, zsto, zout )
         CALL histdef( nid_T, "sosfldow", "downward salt flux"                 , "PSU/m2/s",  &  ! (sfx)
             &         jpi, jpj, nh_T, 1  , 1, 1  , -99 , 32, clop, zsto, zout )
         CALL histdef( nid_T, "sohefldo", "Net Downward Heat Flux"             , "W/m2"   ,   &  ! qns + qsr
            &          jpi, jpj, nh_T, 1  , 1, 1  , -99 , 32, clop, zsto, zout )
         CALL histdef( nid_T, "soshfldo", "Shortwave Radiation"                , "W/m2"   ,   &  ! qsr
            &          jpi, jpj, nh_T, 1  , 1, 1  , -99 , 32, clop, zsto, zout )
         CALL histdef( nid_T, "soicecov", "Ice fraction"                       , "[0,1]"  ,   &  ! fr_i
            &          jpi, jpj, nh_T, 1  , 1, 1  , -99 , 32, clop, zsto, zout )
         CALL histdef( nid_T, "sowindsp", "wind speed at 10m"                  , "m/s"    ,   &  ! wndm
            &          jpi, jpj, nh_T, 1  , 1, 1  , -99 , 32, clop, zsto, zout )
!
         IF( ln_abl ) THEN
         !                                                                                      !!! nid_A : 3D
			CALL histdef( nid_A, "t_abl", "Potential Temperature"     , "K"        ,       &  ! t_abl
               &          jpi, jpj, nh_A, ipka, 1, ipka, nz_A, 32, clop, zsto, zout )
            CALL histdef( nid_A, "q_abl", "Humidity"                  , "kg/kg"    ,       &  ! q_abl
               &          jpi, jpj, nh_A, ipka, 1, ipka, nz_A, 32, clop, zsto, zout ) 
            CALL histdef( nid_A, "u_abl", "Atmospheric U-wind   "     , "m/s"        ,     &  ! u_abl
               &          jpi, jpj, nh_A, ipka, 1, ipka, nz_A, 32, clop, zsto, zout )
            CALL histdef( nid_A, "v_abl", "Atmospheric V-wind   "     , "m/s"    ,         &  ! v_abl
               &          jpi, jpj, nh_A, ipka, 1, ipka, nz_A, 32, clop, zsto, zout ) 
            CALL histdef( nid_A, "tke_abl", "Atmospheric TKE   "     , "m2/s2"    ,        &  ! tke_abl
               &          jpi, jpj, nh_A, ipka, 1, ipka, nz_A, 32, clop, zsto, zout ) 
            CALL histdef( nid_A, "avm_abl", "Atmospheric turbulent viscosity", "m2/s"   ,  &  ! avm_abl
               &          jpi, jpj, nh_A, ipka, 1, ipka, nz_A, 32, clop, zsto, zout ) 
            CALL histdef( nid_A, "avt_abl", "Atmospheric turbulent diffusivity", "m2/s2",  &  ! avt_abl
               &          jpi, jpj, nh_A, ipka, 1, ipka, nz_A, 32, clop, zsto, zout ) 
            CALL histdef( nid_A, "pblh", "Atmospheric boundary layer height "  , "m",      &  ! pblh
               &          jpi, jpj, nh_A,  1  , 1, 1   , -99 , 32, clop, zsto, zout )		 			   
#if defined key_si3
            CALL histdef( nid_A, "oce_frac", "Fraction of open ocean"  , " ",      &  ! ato_i
               &          jpi, jpj, nh_A,  1  , 1, 1   , -99 , 32, clop, zsto, zout )
#endif
		    CALL histend( nid_A, snc4chunks=snc4set )
		 !
		 ENDIF
!
         CALL histdef( nid_T, "sozotaux", "Wind Stress along i-axis"           , "N/m2"   ,   &  ! utau
            &          jpi, jpj, nh_T, 1  , 1, 1  , - 99, 32, clop, zsto, zout )
         CALL histdef( nid_T, "sometauy", "Wind Stress along j-axis"           , "N/m2"   ,   &  ! vtau
            &          jpi, jpj, nh_T, 1  , 1, 1  , - 99, 32, clop, zsto, zout )

         CALL histend( nid_T, snc4chunks=snc4set )

         !                                                                                      !!! nid_U : 3D
         CALL histdef( nid_U, "ssu_m", "Velocity component in x-direction", "m/s"   ,         &  ! ssu
            &          jpi, jpj, nh_U, 1  , 1, 1  , - 99, 32, clop, zsto, zout )

         CALL histend( nid_U, snc4chunks=snc4set )

         !                                                                                      !!! nid_V : 3D
         CALL histdef( nid_V, "ssv_m", "Velocity component in y-direction", "m/s",            &  ! ssv_m
            &          jpi, jpj, nh_V, 1  , 1, 1  , - 99, 32, clop, zsto, zout )

         CALL histend( nid_V, snc4chunks=snc4set )

         IF(lwp) WRITE(numout,*)
         IF(lwp) WRITE(numout,*) 'End of NetCDF Initialization'
         IF(ll_print) CALL FLUSH(numout )

      ENDIF

      ! 2. Start writing data
      ! ---------------------

      ! ndex(1) est utilise ssi l'avant dernier argument est diffferent de 
      ! la taille du tableau en sortie. Dans ce cas , l'avant dernier argument
      ! donne le nombre d'elements, et ndex la liste des indices a sortir

      IF( lwp .AND. MOD( itmod, nn_write ) == 0 ) THEN 
         WRITE(numout,*) 'dia_wri : write model outputs in NetCDF files at ', kt, 'time-step'
         WRITE(numout,*) '~~~~~~ '
      ENDIF

      ! Write fields on T grid
      CALL histwrite( nid_T, "sst_m", it, sst_m, ndim_hT, ndex_hT )   ! sea surface temperature
      CALL histwrite( nid_T, "sss_m", it, sss_m, ndim_hT, ndex_hT )   ! sea surface salinity
      CALL histwrite( nid_T, "sowaflup", it, (emp - rnf )  , ndim_hT, ndex_hT )   ! upward water flux
      CALL histwrite( nid_T, "sosfldow", it, sfx           , ndim_hT, ndex_hT )   ! downward salt flux 
                                                                                  ! (includes virtual salt flux beneath ice 
                                                                                  ! in linear free surface case)

      CALL histwrite( nid_T, "sohefldo", it, qns + qsr     , ndim_hT, ndex_hT )   ! total heat flux
      CALL histwrite( nid_T, "soshfldo", it, qsr           , ndim_hT, ndex_hT )   ! solar heat flux
      CALL histwrite( nid_T, "soicecov", it, fr_i          , ndim_hT, ndex_hT )   ! ice fraction   
      CALL histwrite( nid_T, "sowindsp", it, wndm          , ndim_hT, ndex_hT )   ! wind speed   
      CALL histwrite( nid_T, "sozotaux", it, utau          , ndim_hT, ndex_hT )   ! i-wind stress
      CALL histwrite( nid_T, "sometauy", it, vtau          , ndim_hT, ndex_hT )   ! j-wind stress
!
      IF( ln_abl ) THEN 
	     ALLOCATE( zw3d_abl(jpi,jpj,jpka) )
	     IF( ln_mskland )   THEN 
		    DO jk=1,jpka
		       zw3d_abl(:,:,jk) = tmask(:,:,1)
            END DO
		 ELSE
            zw3d_abl(:,:,:) = 1._wp		 
         ENDIF			
		 CALL histwrite( nid_A,  "pblh"   , it, pblh(:,:)                  *zw3d_abl(:,:,1     ), ndim_hA, ndex_hA )   ! pblh 
	     CALL histwrite( nid_A,  "u_abl"  , it, u_abl   (:,:,2:jpka,nt_n  )*zw3d_abl(:,:,2:jpka), ndim_A , ndex_A  )   ! u_abl
	     CALL histwrite( nid_A,  "v_abl"  , it, v_abl   (:,:,2:jpka,nt_n  )*zw3d_abl(:,:,2:jpka), ndim_A , ndex_A  )   ! v_abl
	     CALL histwrite( nid_A,  "t_abl"  , it, tq_abl  (:,:,2:jpka,nt_n,1)*zw3d_abl(:,:,2:jpka), ndim_A , ndex_A  )   ! t_abl
	     CALL histwrite( nid_A,  "q_abl"  , it, tq_abl  (:,:,2:jpka,nt_n,2)*zw3d_abl(:,:,2:jpka), ndim_A , ndex_A  )   ! q_abl		 
	     CALL histwrite( nid_A,  "tke_abl", it, tke_abl (:,:,2:jpka,nt_n  )*zw3d_abl(:,:,2:jpka), ndim_A , ndex_A  )   ! tke_abl
	     CALL histwrite( nid_A,  "avm_abl", it, avm_abl (:,:,2:jpka       )*zw3d_abl(:,:,2:jpka), ndim_A , ndex_A  )   ! avm_abl
	     CALL histwrite( nid_A,  "avt_abl", it, avt_abl (:,:,2:jpka       )*zw3d_abl(:,:,2:jpka), ndim_A , ndex_A  )   ! avt_abl	
#if defined key_si3
         CALL histwrite( nid_A,  "oce_frac"   , it, ato_i(:,:)                                  , ndim_hA, ndex_hA )   ! ato_i
#endif
		 DEALLOCATE(zw3d_abl)
	  ENDIF
!

         ! Write fields on U grid
      CALL histwrite( nid_U, "ssu_m"   , it, ssu_m         , ndim_hU, ndex_hU )   ! i-current speed

         ! Write fields on V grid
      CALL histwrite( nid_V, "ssv_m"   , it, ssv_m         , ndim_hV, ndex_hV )   ! j-current speed

      ! 3. Close all files
      ! ---------------------------------------
      IF( kt == nitend ) THEN
         CALL histclo( nid_T )
         CALL histclo( nid_U )
         CALL histclo( nid_V )
         IF(ln_abl) CALL histclo( nid_A )
      ENDIF
      !
      IF( ln_timing )   CALL timing_stop('dia_wri')
      !
   END SUBROUTINE dia_wri
#endif

   SUBROUTINE dia_wri_state( Kmm, cdfile_name )
      !!---------------------------------------------------------------------
      !!                 ***  ROUTINE dia_wri_state  ***
      !!        
      !! ** Purpose :   create a NetCDF file named cdfile_name which contains 
      !!      the instantaneous ocean state and forcing fields.
      !!        Used to find errors in the initial state or save the last
      !!      ocean state in case of abnormal end of a simulation
      !!
      !! ** Method  :   NetCDF files using ioipsl
      !!      File 'output.init.nc'  is created if ninist = 1 (namelist)
      !!      File 'output.abort.nc' is created in case of abnormal job end
      !!----------------------------------------------------------------------
      INTEGER           , INTENT( in ) ::   Kmm              ! ocean time levelindex
      CHARACTER (len=* ), INTENT( in ) ::   cdfile_name      ! name of the file created
      !!
      INTEGER :: inum
      !!----------------------------------------------------------------------
      ! 
      IF(lwp) WRITE(numout,*)
      IF(lwp) WRITE(numout,*) 'dia_wri_state : single instantaneous ocean state'
      IF(lwp) WRITE(numout,*) '~~~~~~~~~~~~~   and forcing fields file created '
      IF(lwp) WRITE(numout,*) '                and named :', cdfile_name, '...nc'
      !
      CALL iom_open( TRIM(cdfile_name), inum, ldwrt = .TRUE. )
      !
      CALL iom_rstput( 0, 0, inum, 'votemper', ts (:,:,:,jp_tem,Kmm) )    ! now temperature
      CALL iom_rstput( 0, 0, inum, 'vosaline', ts (:,:,:,jp_sal,Kmm) )    ! now salinity
      CALL iom_rstput( 0, 0, inum, 'sossheig', ssh(:,:,         Kmm) )    ! sea surface height
      CALL iom_rstput( 0, 0, inum, 'vozocrtx', uu (:,:,:,       Kmm) )    ! now i-velocity
      CALL iom_rstput( 0, 0, inum, 'vomecrty', vv (:,:,:,       Kmm) )    ! now j-velocity
      CALL iom_rstput( 0, 0, inum, 'vovecrtz', ww                    )    ! now k-velocity
      CALL iom_rstput( 0, 0, inum, 'sowaflup', emp - rnf             )    ! freshwater budget
      CALL iom_rstput( 0, 0, inum, 'sohefldo', qsr + qns             )    ! total heat flux
      CALL iom_rstput( 0, 0, inum, 'soshfldo', qsr                   )    ! solar heat flux
      CALL iom_rstput( 0, 0, inum, 'soicecov', fr_i                  )    ! ice fraction
      CALL iom_rstput( 0, 0, inum, 'sozotaux', utau                  )    ! i-wind stress
      CALL iom_rstput( 0, 0, inum, 'sometauy', vtau                  )    ! j-wind stress
      !
      CALL iom_close( inum )
      !
#if defined key_si3
      IF( nn_ice == 2 ) THEN   ! condition needed in case agrif + ice-model but no-ice in child grid
         CALL iom_open( TRIM(cdfile_name)//'_ice', inum, ldwrt = .TRUE., kdlev = jpl, cdcomp = 'ICE' )
         CALL ice_wri_state( inum )
         CALL iom_close( inum )
      ENDIF
      !
#endif
   END SUBROUTINE dia_wri_state

   !!======================================================================
END MODULE diawri
