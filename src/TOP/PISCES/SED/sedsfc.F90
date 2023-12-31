MODULE sedsfc
   !!======================================================================
   !!              ***  MODULE  sedsfc  ***
   !!    Sediment : Data at sediment surface
   !!=====================================================================
   !! * Modules used
   USE sed     ! sediment global variable
   USE sedini
   USE sedarr
   USE seddta

   PUBLIC sed_sfc

   !! * Substitutions
#  include "do_loop_substitute.h90"
#  include "domzgr_substitute.h90"

CONTAINS

   SUBROUTINE sed_sfc( kt, Kbb )
      !!---------------------------------------------------------------------
      !!                  ***  ROUTINE sed_sfc ***
      !!
      !! ** Purpose :  Give data from sediment model to tracer model
      !!
      !!
      !!   History :
      !!        !  06-04 (C. Ethe)  Orginal code
      !!----------------------------------------------------------------------
      !!* Arguments
      INTEGER, INTENT(in) ::  kt              ! time step
      INTEGER, INTENT(in) ::  Kbb             ! time level indices

      ! * local variables
      INTEGER :: ji, jj, ikt     ! dummy loop indices

      !------------------------------------------------------------------------
      ! reading variables

      IF( ln_timing )  CALL timing_start('sed_sfc')

      CALL unpack_arr ( jpoce, trc_data(1:jpi,1:jpj,1), iarroce(1:jpoce), pwcp(1:jpoce,1,jwalk) )
      CALL unpack_arr ( jpoce, trc_data(1:jpi,1:jpj,2), iarroce(1:jpoce), pwcp(1:jpoce,1,jwdic) )
      CALL unpack_arr ( jpoce, trc_data(1:jpi,1:jpj,3), iarroce(1:jpoce), pwcp(1:jpoce,1,jwno3) )
      CALL unpack_arr ( jpoce, trc_data(1:jpi,1:jpj,4), iarroce(1:jpoce), pwcp(1:jpoce,1,jwpo4) )
      CALL unpack_arr ( jpoce, trc_data(1:jpi,1:jpj,5), iarroce(1:jpoce), pwcp(1:jpoce,1,jwoxy) )
      CALL unpack_arr ( jpoce, trc_data(1:jpi,1:jpj,6), iarroce(1:jpoce), pwcp(1:jpoce,1,jwsil) )
      CALL unpack_arr ( jpoce, trc_data(1:jpi,1:jpj,7), iarroce(1:jpoce), pwcp(1:jpoce,1,jwnh4) )
      CALL unpack_arr ( jpoce, trc_data(1:jpi,1:jpj,8), iarroce(1:jpoce), pwcp(1:jpoce,1,jwfe2) )
      CALL unpack_arr ( jpoce, trc_data(1:jpi,1:jpj,9), iarroce(1:jpoce), pwcp(1:jpoce,1,jwlgw) )

      DO_2D( 0, 0, 0, 0 )
         ikt = mbkt(ji,jj)
         IF ( tmask(ji,jj,ikt) == 1 ) THEN
            tr(ji,jj,ikt,jptal,Kbb) = trc_data(ji,jj,1)
            tr(ji,jj,ikt,jpdic,Kbb) = trc_data(ji,jj,2)
            tr(ji,jj,ikt,jpno3,Kbb) = trc_data(ji,jj,3) * redC / redNo3
            tr(ji,jj,ikt,jppo4,Kbb) = trc_data(ji,jj,4) * redC
            tr(ji,jj,ikt,jpoxy,Kbb) = trc_data(ji,jj,5)
            tr(ji,jj,ikt,jpsil,Kbb) = trc_data(ji,jj,6)
            tr(ji,jj,ikt,jpnh4,Kbb) = trc_data(ji,jj,7) * redC / redNo3
            tr(ji,jj,ikt,jpfer,Kbb) = trc_data(ji,jj,8)
         ENDIF
      END_2D

      IF( ln_timing )  CALL timing_stop('sed_sfc')

   END SUBROUTINE sed_sfc

END MODULE sedsfc
