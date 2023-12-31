MODULE usrdef_nam
   !!======================================================================
   !!                       ***  MODULE  usrdef_nam  ***
   !!
   !!                      ===  ICE_AGRIF configuration  ===
   !!
   !! User defined : set the domain characteristics of a user configuration
   !!======================================================================
   !! History :  NEMO ! 2016-03  (S. Flavoni, G. Madec)  Original code
   !!----------------------------------------------------------------------

   !!----------------------------------------------------------------------
   !!   usr_def_nam   : read user defined namelist and set global domain size
   !!   usr_def_hgr   : initialize the horizontal mesh 
   !!----------------------------------------------------------------------
   USE dom_oce
   USE par_oce        ! ocean space and time domain
   USE phycst         ! physical constants
   !
   USE in_out_manager ! I/O manager
   USE lib_mpp        ! MPP library
   USE timing         ! Timing
   
   IMPLICIT NONE
   PRIVATE

   PUBLIC   usr_def_nam   ! called by nemogcm.F90

   !                               !!* namusr_def namelist *!!
   REAL(wp), PUBLIC ::   rn_dx      ! resolution in meters defining the horizontal domain size
   REAL(wp), PUBLIC ::   rn_dy      ! resolution in meters defining the horizontal domain size
   REAL(wp), PUBLIC ::   rn_ppgphi0 ! reference latitude for beta-plane 
   LOGICAL , PUBLIC ::   ln_corio   ! set coriolis at 0 (ln_corio=F) or not 

   !!----------------------------------------------------------------------
   !! NEMO/OCE 4.0 , NEMO Consortium (2018)
   !! $Id: usrdef_nam.F90 15119 2021-07-13 14:43:22Z jchanut $ 
   !! Software governed by the CeCILL license (see ./LICENSE)
   !!----------------------------------------------------------------------
CONTAINS

   SUBROUTINE usr_def_nam( cd_cfg, kk_cfg, kpi, kpj, kpk, ldIperio, ldJperio, ldNFold, cdNFtype )
      !!----------------------------------------------------------------------
      !!                     ***  ROUTINE dom_nam  ***
      !!                    
      !! ** Purpose :   read user defined namelist and define the domain size
      !!
      !! ** Method  :   read in namusr_def containing all the user specific namelist parameter
      !!
      !!                Here ICE_AGRIF configuration
      !!
      !! ** input   : - namusr_def namelist found in namelist_cfg
      !!----------------------------------------------------------------------
      CHARACTER(len=*), INTENT(out) ::   cd_cfg               ! configuration name
      INTEGER         , INTENT(out) ::   kk_cfg               ! configuration resolution
      INTEGER         , INTENT(out) ::   kpi, kpj, kpk        ! global domain sizes 
      LOGICAL         , INTENT(out) ::   ldIperio, ldJperio   ! i- and j- periodicity
      LOGICAL         , INTENT(out) ::   ldNFold              ! North pole folding
      CHARACTER(len=1), INTENT(out) ::   cdNFtype             ! Folding type: T or F
      !
      INTEGER ::   ios       ! Local integer
      INTEGER ::   ighost_n, ighost_s, ighost_w, ighost_e
      REAL(wp)::   zlx, zly  ! Local scalars
      !!
      NAMELIST/namusr_def/ rn_dx, rn_dy, ln_corio, rn_ppgphi0
      !!----------------------------------------------------------------------
      !
      READ  ( numnam_cfg, namusr_def, IOSTAT = ios, ERR = 902 )
902   IF( ios /= 0 )   CALL ctl_nam ( ios , 'namusr_def in configuration namelist' )
      !
#if defined key_agrif 
      ! Domain parameters are taken from parent:
      IF( .NOT. Agrif_Root() ) THEN
         rn_dx = Agrif_Parent(rn_dx)/Agrif_Rhox()
         rn_dy = Agrif_Parent(rn_dy)/Agrif_Rhoy()
         rn_ppgphi0 = Agrif_Parent(rn_ppgphi0)
      ENDIF
#endif
      !
      IF(lwm)   WRITE( numond, namusr_def )
      !
      cd_cfg = 'ICE_AGRIF'           ! name & resolution (not used)
      kk_cfg = NINT( rn_dx )
      !
      IF( Agrif_Root() ) THEN        ! Global Domain size:  ICE_AGRIF domain is  300 km x 300 Km x 10 m
         kpi = NINT( 300.e3 / rn_dx ) - 3 
         kpj = NINT( 300.e3 / rn_dy ) - 3
      ELSE                           ! Global Domain size: add nbghostcells + 1 "land" point on each side
         ! At this stage, child ghosts have not been set
         ighost_w = nbghostcells
         ighost_e = nbghostcells
         ighost_s = nbghostcells
         ighost_n = nbghostcells

         ! In case one sets zoom boundaries over domain edges: 
         IF  ( Agrif_Ix() == 2 - Agrif_Parent(nbghostcells_x_w) ) ighost_w = 1
         IF  ( Agrif_Ix() + nbcellsx/AGRIF_Irhox() == Agrif_Parent(Ni0glo) - Agrif_Parent(nbghostcells_x_w) ) ighost_e = 1
         IF  ( Agrif_Iy() == 2 - Agrif_Parent(nbghostcells_y_s) ) ighost_s = 1
         IF  ( Agrif_Iy() + nbcellsy/AGRIF_Irhoy() == Agrif_Parent(Nj0glo) - Agrif_Parent(nbghostcells_y_s) ) ighost_n = 1
!         kpi  = nbcellsx + 2 * ( nbghostcells + 1 )
!         kpj  = nbcellsy + 2 * ( nbghostcells + 1 )
         kpi  = nbcellsx + ighost_w + ighost_e
         kpj  = nbcellsy + ighost_s + ighost_n
      ENDIF
      kpk = 2
      !
      zlx = (kpi-2)*rn_dx*1.e-3
      zly = (kpj-2)*rn_dy*1.e-3
!!      zlx = kpi*rn_dx*1.e-3
!!      zly = kpj*rn_dy*1.e-3
      !
      IF( Agrif_Root() ) THEN   ;   ldIperio =  .TRUE.   ;   ldJperio =  .TRUE.     ! ICE_AGRIF configuration : bi-periodic basin
      ELSE                      ;   ldIperio = .FALSE.   ;   ldJperio = .FALSE.     ! closed periodicity for the zoom
      ENDIF
      ldNFold  = .FALSE.   ;   cdNFtype = '-'
      !
      !                             ! control print
      IF(lwp) THEN
         WRITE(numout,*) '   '
         WRITE(numout,*) 'usr_def_nam  : read the user defined namelist (namusr_def) in namelist_cfg'
         WRITE(numout,*) '~~~~~~~~~~~ '
         WRITE(numout,*) '   Namelist namusr_def : ICE_AGRIF test case'
         WRITE(numout,*) '      horizontal resolution                    rn_dx  = ', rn_dx, ' meters'
         WRITE(numout,*) '      horizontal resolution                    rn_dy  = ', rn_dy, ' meters'
         WRITE(numout,*) '      ICE_AGRIF domain = 300 km x 300Km x 1 grid-point '
         WRITE(numout,*) '         LX [km]: ', zlx
         WRITE(numout,*) '         LY [km]: ', zly
         WRITE(numout,*) '         resulting global domain size :        Ni0glo = ', kpi
         WRITE(numout,*) '                                               Nj0glo = ', kpj
         WRITE(numout,*) '                                               jpkglo = ', kpk
         WRITE(numout,*) '         Coriolis:', ln_corio
         WRITE(numout,*) '   '
      ENDIF
      !
   END SUBROUTINE usr_def_nam

   !!======================================================================
END MODULE usrdef_nam
