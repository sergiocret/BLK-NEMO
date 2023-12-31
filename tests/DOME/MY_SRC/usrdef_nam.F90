MODULE usrdef_nam
   !!======================================================================
   !!                       ***  MODULE  usrdef_nam  ***
   !!
   !!                      ===  DOME configuration  ===
   !!
   !! User defined : set the domain characteristics of a user configuration
   !!======================================================================
   !! History :  NEMO ! 2020-12  (J. Chanut)  Original code
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

   !                              !!* namusr_def namelist *!!
   REAL(wp), PUBLIC ::   rn_dx      ! resolution in meters defining the horizontal domain size
   REAL(wp), PUBLIC ::   rn_dy      ! resolution in meters defining the horizontal domain size
   REAL(wp), PUBLIC ::   rn_dz      ! vertical resolution 
   REAL(wp), PUBLIC ::   rn_f0      ! Coriolis frequency 

   !!----------------------------------------------------------------------
   !! NEMO/OCE 4.0 , NEMO Consortium (2018)
   !! $Id: usrdef_nam.F90 14086 2020-12-04 11:37:14Z cetlod $ 
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
      !!                Here DOME configuration
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
      INTEGER ::   ios          ! Local integer
      INTEGER ::   ighost_w, ighost_e, ighost_s, ighost_n
      REAL(wp)::   zlx, zly, zh ! Local scalars
      !!
      NAMELIST/namusr_def/  l_zco, l_zps, l_sco, rn_dx, rn_dz, rn_f0
      !!----------------------------------------------------------------------
      !
      READ  ( numnam_cfg, namusr_def, IOSTAT = ios, ERR = 902 )
902   IF( ios /= 0 )   CALL ctl_nam ( ios , 'namusr_def in configuration namelist' )
      !
      rn_dy = rn_dx
#if defined key_agrif 
      ! Domain parameters are taken from parent:
      IF( .NOT. Agrif_Root() ) THEN
         rn_dx = Agrif_Parent(rn_dx)/Agrif_Rhox()
         rn_dy = Agrif_Parent(rn_dy)/Agrif_Rhoy()
         rn_f0 = Agrif_Parent(rn_f0)
      ENDIF
#endif
      !
      IF(lwm)   WRITE( numond, namusr_def )
      !
      cd_cfg = 'DOME'               ! name & resolution (not used)
      kk_cfg = nINT( rn_dx )
      !
#if defined key_agrif 
      IF( Agrif_Root() ) THEN       ! Global Domain size:  DOME  global domain is  2000 km x 850 Km x 3600 m
#endif
         kpi = NINT( 2000.e3  / rn_dx ) + 2  
         kpj = NINT(  850.e3  / rn_dy ) + 2 + 1 
#if defined key_agrif 
      ELSE                          ! Global Domain size: add nbghostcells + 1 "land" point on each side
         ! At this stage, child ghosts have not been set
         ighost_w = nbghostcells
         ighost_e = nbghostcells
         ighost_s = nbghostcells
         ighost_n = nbghostcells
         ! In case one sets zoom boundaries over domain edges: 
         IF  ( Agrif_Ix() == 2 - Agrif_Parent(nbghostcells_x_w) ) ighost_w = 1 
         IF  ( Agrif_Ix() + nbcellsx/AGRIF_Irhox() == Agrif_Parent(Ni0glo)-Agrif_Parent(nbghostcells_x_w) ) ighost_e = 1 
         IF  ( Agrif_Iy() == 2 - Agrif_Parent(nbghostcells_y_s) ) ighost_s = 1 
         IF  ( Agrif_Iy() + nbcellsy/AGRIF_Irhoy() == Agrif_Parent(Nj0glo)-Agrif_Parent(nbghostcells_y_s) ) ighost_n = 1 
         kpi  = nbcellsx + ighost_w + ighost_e
         kpj  = nbcellsy + ighost_s + ighost_n
!! JC: number of ghosts are unknown at this stage !
!!$         kpi  = nbcellsx + nbghostcells_x_w + nbghostcells_x_e
!!$         kpj  = nbcellsy + nbghostcells_y_s + nbghostcells_y_n 
      ENDIF
#endif
      kpk = NINT( 3600._wp / rn_dz ) + 1
      !
      zlx = (kpi-2)*rn_dx*1.e-3
      zly = (kpj-2-1)*rn_dy*1.e-3
      zh  = (kpk-1)*rn_dz
      !                             ! Set the lateral boundary condition of the global domain
      ldIperio = .FALSE.   ;   ldJperio = .FALSE.   ! DOME configuration : closed domain
      ldNFold  = .FALSE.   ;   cdNFtype = '-'
      !
      !                             ! control print
      IF(lwp) THEN
         WRITE(numout,*) '   '
         WRITE(numout,*) 'usr_def_nam  : read the user defined namelist (namusr_def) in namelist_cfg'
         WRITE(numout,*) '~~~~~~~~~~~ '
         WRITE(numout,*) '   Namelist namusr_def : DOME test case'
         WRITE(numout,*) '      z-coordinate flag                 l_zco  = ', l_zco
         WRITE(numout,*) '      z-partial-step coordinate flag    l_zps  = ', l_zps 
         WRITE(numout,*) '      s-coordinate flag                 l_sco  = ', l_sco  
         WRITE(numout,*) '      horizontal resolution             rn_dx  = ', rn_dx, ' m'
         WRITE(numout,*) '      vertical resolution               rn_dz  = ', rn_dz, ' m'
         WRITE(numout,*) '      resulting global domain size :    Ni0glo = ', kpi
         WRITE(numout,*) '                                        Nj0glo = ', kpj
         WRITE(numout,*) '                                        jpkglo = ', kpk
         WRITE(numout,*) '      DOME domain: '
         WRITE(numout,*) '         LX [km]: ', zlx
         WRITE(numout,*) '         LY [km]: ', zly
         WRITE(numout,*) '          H [m] : ', zh
         WRITE(numout,*) '      Coriolis frequency                rn_f0 = ', rn_f0, ' s-1'
         WRITE(numout,*) '   '
      ENDIF
      !
   END SUBROUTINE usr_def_nam

   !!======================================================================
END MODULE usrdef_nam
