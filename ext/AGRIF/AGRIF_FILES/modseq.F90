module Agrif_seq
!
    use Agrif_Init
    use Agrif_Procs
    use Agrif_Arrays
!
    implicit none

    integer, private, parameter :: subdomain_minwidth = 6
!
contains
!
#if defined AGRIF_MPI
!===================================================================================================
function Agrif_seq_allocate_list ( nb_seqs ) result( seqlist )
!---------------------------------------------------------------------------------------------------
    integer, intent(in)     :: nb_seqs
!
    type(Agrif_Sequence_List), pointer :: seqlist
!
    allocate(seqlist)
    seqlist % nb_seqs = nb_seqs
    allocate(seqlist % sequences(1:nb_seqs))
!---------------------------------------------------------------------------------------------------
end function Agrif_seq_allocate_list
!===================================================================================================
!
!===================================================================================================
subroutine Agrif_seq_add_grid ( seqlist, seq_num, grid )
!---------------------------------------------------------------------------------------------------
    type(Agrif_Sequence_List), intent(inout)    :: seqlist
    integer,                   intent(in)       :: seq_num
    type(Agrif_Grid), pointer, intent(in)       :: grid
!
    call Agrif_gl_append(seqlist % sequences(seq_num) % gridlist, grid )
!---------------------------------------------------------------------------------------------------
end subroutine Agrif_seq_add_grid
!===================================================================================================
!
!===================================================================================================
recursive subroutine Agrif_seq_init_sequences ( grid )
!---------------------------------------------------------------------------------------------------
    type(Agrif_Grid), intent(inout)  :: grid
!
    type(Agrif_PGrid), pointer  :: gp
!
#if defined AGRIF_MPI
!
! Build list of required procs for each child grid
    gp => grid % child_list % first
    do while ( associated( gp ) )
        call Agrif_seq_build_required_proclist( gp % gr )
        gp => gp % next
    enddo
!
! Create integration sequences for the current grid
    call Agrif_seq_create_proc_sequences( grid )
    call Agrif_seq_allocate_procs_to_childs( grid )
!
! Create new communicators for sequences
    call Agrif_seq_create_communicators( grid )
!
#endif
!---------------------------------------------------------------------------------------------------
end subroutine Agrif_seq_init_sequences
!===================================================================================================
!
!===================================================================================================
subroutine Agrif_seq_build_required_proclist ( grid )
!---------------------------------------------------------------------------------------------------
    type(Agrif_Grid), intent(inout) :: grid
!
    type(Agrif_Grid),      pointer  :: parent_grid
    type(Agrif_Rectangle), pointer  :: grid_rect
    type(Agrif_Proc_p),    pointer  :: proc_rect
    type(Agrif_Proc),      pointer  :: proc
    logical     :: proc_is_required
    integer     :: i
!
    if ( grid % fixedrank == 0 ) then
!       grid is the Root
        if ( grid % required_proc_list % nitems == 0 ) then
            print*, "### Error Agrif_seq_build_required_proclist: empty proc list."
            print*, "# -> You should check if Agrif_Init_ProcList() is actually working."
            stop
        endif
        return
    endif
!
    parent_grid => grid % parent
    grid_rect   => grid % rect_in_parent
    proc_rect   => parent_grid % proc_def_list % first
!

    do while ( associated( proc_rect ) )

!
        proc => proc_rect % proc
!
        proc_is_required = .true.
        do i = 1,Agrif_Probdim
            proc_is_required = ( proc_is_required             .and. &
                    ( grid_rect % imin(i) <= proc % imax(i) ) .and. &
                    ( grid_rect % imax(i) >= proc % imin(i) ) )
        enddo
!
        if ( proc_is_required ) then
            call Agrif_pl_append(grid % required_proc_list, proc)
        endif
        proc_rect => proc_rect % next
!
    enddo
    if (agrif_debug_parallel_sisters) then
        if (Agrif_GlobProcRank == 0) print *,'Grid ',grid%fixedrank,' requires'
        if (Agrif_GlobProcRank == 0) call Agrif_pl_print(grid % required_proc_list)
    endif
!---------------------------------------------------------------------------------------------------
end subroutine Agrif_seq_build_required_proclist
!===================================================================================================
!
!===================================================================================================
subroutine Agrif_seq_create_proc_sequences ( grid )
!---------------------------------------------------------------------------------------------------
    type(Agrif_Grid), intent(inout)    :: grid
!
    type(Agrif_Grid_List), pointer :: sorted_child_list
    type(Agrif_PGrid),     pointer :: child_p
    type(Agrif_PGrid),     pointer :: g1p, g2p
    type(Agrif_Proc_p),    pointer :: pp1, pp2
    type(Agrif_Proc),      pointer :: proc
    integer                        :: nb_seq_max, nb_seqs, cur_seq
!
    nb_seq_max = 0
!
    if ( grid % child_list % nitems == 0 ) return
!
! For each required proc...
    pp1  => grid % required_proc_list % first
    do while ( associated(pp1) )
        proc => pp1 % proc
        proc % nb_seqs = 0
!   ..loop over all child grids...
        child_p => grid % child_list % first
        do while ( associated(child_p) )
!       ..and look for 'proc' in the list of procs required by 'child'
            pp2 => child_p % gr % required_proc_list % first
            do while ( associated(pp2) )
                if ( proc % pn == pp2 % proc % pn ) then
!                   'proc' is required by this child grid, so we increment its number of sequences
                    proc % nb_seqs = proc % nb_seqs + 1
                    pp2 => NULL()
                else
                    pp2 => pp2 % next
                endif
            enddo
            child_p => child_p % next
        enddo
        nb_seq_max = max(nb_seq_max, proc % nb_seqs)
        pp1 => pp1 % next
    enddo
!
! For each grid...
    g1p => grid % child_list % first
    do while ( associated(g1p) )
!     compare it with the following ones
        g2p => g1p % next
        do while ( associated(g2p) )
            if ( Agrif_seq_grids_are_connected( g1p % gr, g2p % gr ) ) then
                call Agrif_gl_append( g1p % gr % neigh_list, g2p % gr )
                call Agrif_gl_append( g2p % gr % neigh_list, g1p % gr )
            endif
            g2p => g2p % next
        enddo
        g1p => g1p % next
    enddo
!
! Colorize graph nodes
    nb_seqs = Agrif_seq_colorize_grid_list(grid % child_list)
    sorted_child_list => Agrif_gl_merge_sort ( grid % child_list, compare_colors )
!
! Create sequence structure
    cur_seq = 0
    grid % child_seq => Agrif_seq_allocate_list(nb_seqs)
    if (agrif_debug_parallel_sisters) then
        if (Agrif_GlobProcRank == 0) print *,'GRILLE SEQ = ',grid%fixedrank,nb_seqs
    endif
    child_p => sorted_child_list % first
    do while ( associated(child_p) )
        if ( cur_seq /= child_p % gr % seq_num ) then
            cur_seq = child_p % gr % seq_num
        endif
        if (agrif_debug_parallel_sisters) then
            if (Agrif_GlobProcRank == 0) then
                print *,'Grille = ',child_p % gr %fixedrank,' Seq = ',child_p % gr % seq_num
            endif
        endif
        call Agrif_seq_add_grid(grid % child_seq,cur_seq,child_p% gr)
        child_p => child_p % next
    enddo
!
    call Agrif_gl_delete(sorted_child_list)
!---------------------------------------------------------------------------------------------------
end subroutine Agrif_seq_create_proc_sequences
!===================================================================================================
!
!===================================================================================================
function Agrif_seq_grids_are_connected( g1, g2 ) result( connection )
!
!< Compare required_proc_list for g1 and g2. These are connected if they share a same proc.
!---------------------------------------------------------------------------------------------------
    type(Agrif_Grid), intent(in) :: g1, g2
!
    logical :: connection
    type(Agrif_Proc_p), pointer :: pp1, pp2
!
    connection = .false.
!
    pp1 => g1 % required_proc_list % first
!
    do while( associated(pp1) .and. (.not. connection) )
!
        pp2 => g2 % required_proc_list % first
        do while ( associated(pp2) .and. (.not. connection) )
            if ( pp1 % proc % pn == pp2 % proc % pn ) then
            ! if pp1 and pp2 are the same proc, it means that g1 and g2 are connected. We stop here.
                connection = .true.
            endif
            pp2 => pp2 % next
        enddo
        pp1 => pp1 % next
!
    enddo
!---------------------------------------------------------------------------------------------------
end function Agrif_seq_grids_are_connected
!===================================================================================================
!
!===================================================================================================
function Agrif_seq_colorize_grid_list ( gridlist ) result ( ncolors )
!
!< 1.  Sort nodes in decreasing order of degree.
!< 2.  Color the node with highest degree with color 1.
!< 3.  Choose the node with the largest DSAT value. In case of conflict, choose the one with the
!!       highest degree. Then the one corresponding to the largest grid.
!< 4.  Color this node with the smallest possible color.
!< 5.  If all nodes are colored, then stop. Otherwise, go to 3.
!---------------------------------------------------------------------------------------------------
    type(Agrif_Grid_List), intent(in)    :: gridlist
!
    type(Agrif_Grid_List),   pointer  :: X, Y
    type(Agrif_PGrid),       pointer  :: gridp
    type(Agrif_Grid_List),   pointer  :: tmp_gl
    integer                           :: ncolors
    integer, dimension(1:gridlist%nitems)   :: colors
!
! Be carefull...
    nullify(Y)
!
! First initialize the color of each node
    gridp => gridlist % first
    do while ( associated(gridp) )
        gridp % gr % seq_num = 0
        gridp => gridp % next
    enddo
!
! Then sort the grids by decreasing degree
    X => Agrif_gl_merge_sort( gridlist, compare_grid_degrees )
    gridp => X % first
!
! Colorize the first grid in the list
    gridp % gr % seq_num = 1
    gridp => gridp % next
!
! Then for each of its neighbors...
    do while ( associated(gridp) )
!
        if ( gridp % gr % neigh_list % nitems == 0 ) then
        ! this grid is alone... let.s attach it to an existing sequence
            call Agrif_seq_attach_grid( X, gridp % gr )
            gridp => gridp % next
            cycle
        endif
!
!     Compute dsat value of all non-colored grids
        tmp_gl => Agrif_gl_build_from_gp(gridp)
        call Agrif_seq_calc_dsat(tmp_gl)
!
!     Sort non-colored grids by decreasing dsat value, then by size
        call Agrif_gl_delete(Y)
        Y => Agrif_gl_merge_sort( tmp_gl, compare_dsat_values, compare_size_values )
!
!     Next coloration is for the first grid in this list  TODO : maybe we could find a better choice ..?
        gridp => Y % first
!
!     Assign a color to the chosen grid
        gridp % gr % seq_num = Agrif_seq_smallest_available_color_in_neighborhood( gridp % gr % neigh_list )
!
        gridp => gridp % next
        call Agrif_gl_delete(tmp_gl)
!
    enddo
!
    call Agrif_gl_delete(X)
    call Agrif_seq_colors_in_neighborhood( gridlist, colors )
    ncolors = maxval(colors)
!---------------------------------------------------------------------------------------------------
end function Agrif_seq_colorize_grid_list
!===================================================================================================
!
!===================================================================================================
subroutine Agrif_seq_attach_grid ( gridlist, grid )
!
!< 'grid' is not connected to any neighbor. Therefore, we give an existing and well chosen color.
!---------------------------------------------------------------------------------------------------
    type(Agrif_Grid_List), intent(in)       :: gridlist
    type(Agrif_Grid),      intent(inout)    :: grid
!
    integer, dimension(gridlist%nitems) :: colors
    integer, dimension(:), allocatable  :: ngrids_by_color
    integer :: i, color, ncolors
!
    call Agrif_seq_colors_in_neighborhood( gridlist, colors )
    ncolors = maxval(colors)
!
    allocate(ngrids_by_color(ncolors))
    ngrids_by_color = 0
!
    do i = 1,gridlist % nitems
        if (colors(i) > 0)  ngrids_by_color(colors(i)) = ngrids_by_color(colors(i)) + 1
    enddo
!
    color = ncolors
    do i = 1,ncolors
        if ( ngrids_by_color(i) < color ) color = i
    enddo
!
    grid % seq_num = color
    deallocate(ngrids_by_color)
!---------------------------------------------------------------------------------------------------
end subroutine Agrif_seq_attach_grid
!===================================================================================================
!
!===================================================================================================
subroutine Agrif_seq_colors_in_neighborhood ( neigh_list, colors )
!---------------------------------------------------------------------------------------------------
    type(Agrif_Grid_List), intent(in)   :: neigh_list
    integer, dimension(:), intent(out)  :: colors
!
    integer                     :: i
    type(Agrif_PGrid), pointer  :: gridp
!
    i = lbound(colors,1)
    colors = 0
    gridp => neigh_list % first
!
    do while ( associated(gridp) )
!
        if ( i > ubound(colors,1) ) then
            print*,'Error in Agrif_seq_colors_in_neighborhood : "colors" array is too small'
            stop
        endif
        colors(i) = gridp % gr % seq_num
        gridp => gridp % next
        i = i+1
!
    enddo
!---------------------------------------------------------------------------------------------------
end subroutine Agrif_seq_colors_in_neighborhood
!===================================================================================================
!
!===================================================================================================
function Agrif_seq_smallest_available_color_in_neighborhood ( neigh_list ) result ( smallest )
!---------------------------------------------------------------------------------------------------
    type(Agrif_Grid_List), intent(in)   :: neigh_list
!
    integer, dimension(:), allocatable :: color_is_met
    integer     :: colors_tab(1:neigh_list%nitems)
    integer     :: i, smallest, max_color
!
    call Agrif_seq_colors_in_neighborhood( neigh_list, colors_tab )
    max_color = maxval(colors_tab)
!
    allocate(color_is_met(1:max_color))
    color_is_met = 0
!
    do i = 1,neigh_list % nitems
        if ( colors_tab(i) /= 0 ) then
            color_is_met(colors_tab(i)) = 1
        endif
    enddo
!
    smallest = max_color+1
    do i = 1,max_color
        if ( color_is_met(i) == 0 ) then
            smallest = i
            exit
        endif
    enddo
!
    deallocate(color_is_met)
!---------------------------------------------------------------------------------------------------
end function Agrif_seq_smallest_available_color_in_neighborhood
!===================================================================================================
!
!===================================================================================================
subroutine Agrif_seq_calc_dsat ( gridlist )
!< For each node 'v' :
!<   if none of its neighbors is colored then
!<       DSAT(v) = degree(v)  #  degree(v) := number of neighbors
!<   else
!<       DSAT(v) = number of different colors used in the first neighborhood of v.
!---------------------------------------------------------------------------------------------------
    type(Agrif_Grid_List), intent(in)   :: gridlist
!
    type(Agrif_PGrid), pointer          :: gridp
    type(Agrif_Grid),  pointer          :: grid
    integer, dimension(:), allocatable  :: colors, color_is_met
    integer                             :: i, ncolors
!
    gridp => gridlist % first
!
    do while ( associated(gridp) )
!
        grid => gridp % gr
!
        allocate(colors(grid % neigh_list % nitems))
        call Agrif_seq_colors_in_neighborhood( grid % neigh_list, colors )

        allocate(color_is_met(1:maxval(colors)))
        color_is_met = 0
!
        do i = 1,grid % neigh_list % nitems
            if ( colors(i) /= 0 ) then
                color_is_met(colors(i)) = 1
            endif
        enddo
        ncolors = sum(color_is_met)
!
        if ( ncolors == 0 ) then
            grid % dsat = grid % neigh_list % nitems
        else
            grid % dsat = ncolors
        endif
        deallocate(colors, color_is_met)
        gridp => gridp % next
    enddo
!---------------------------------------------------------------------------------------------------
end subroutine Agrif_seq_calc_dsat
!===================================================================================================
!
!===================================================================================================
subroutine Agrif_seq_allocate_procs_to_childs ( coarse_grid )
!---------------------------------------------------------------------------------------------------
    type(Agrif_Grid), intent(inout) :: coarse_grid
!
    integer                         :: is, ip, ig, ngrids
    type(Agrif_Grid_List), pointer  :: gridlist
    type(Agrif_PGrid),     pointer  :: gp
    type(Agrif_Grid),      pointer  :: grid
    type(Agrif_Proc_List), pointer  :: proclist
    type(Agrif_Proc),      pointer  :: proc
    type(Agrif_Proc_p),    pointer  :: pp
    type(Agrif_Proc), dimension(:), allocatable, target :: procarray
    type(Agrif_PGrid), dimension(:), allocatable         :: gridarray
    type(Agrif_Sequence_List), pointer :: seqlist
    real,dimension(:),allocatable :: grid_costs, grid_sizes
    real :: total_grid_sizes
    integer,dimension(:), allocatable :: nbprocs_per_grid
    logical,dimension(:), allocatable :: proc_was_required
    integer :: i1, i2, j1, j2, i, j
    real :: max_cost
    integer :: max_index
    integer,dimension(2) :: closest_nb_procs
    integer :: number_of_procs_toremove, number_of_procs_toadd, add_possible, number_of_procs_added, nproc
    logical,dimension(:,:),allocatable :: ispossibletoadd
    logical :: inform_possible_nbprocs
    type(Agrif_Grid)                    , pointer :: save_grid
    integer :: maximum_number_of_procs_to_add, ip2, ip3
    integer :: imax, jmax, deltaij


!
    seqlist => coarse_grid % child_seq
    if ( .not. associated(seqlist) ) return
!
! Initialize proc allocation
    pp => coarse_grid % proc_def_list % first
    do while ( associated(pp) )
        pp % proc % grid_id = 0
        pp => pp % next
    enddo
!
! For each sequence...
    do is = 1,seqlist % nb_seqs
        if (agrif_debug_parallel_sisters) then
            if (Agrif_GlobProcRank == 0) then
                print *,'Sequence = ',is
            endif
        endif
!
        proclist => seqlist % sequences(is) % proclist
        gridlist => seqlist % sequences(is) % gridlist
!
!     Copy coarse grid proc list and convert it to an array
        call Agrif_pl_deep_copy( coarse_grid % proc_def_list, proclist )
        call Agrif_pl_to_array ( proclist, procarray )
!
!     Allocate a temporary array with concerned grid numbers
        ngrids = gridlist % nitems
        allocate(gridarray(1:ngrids))
        allocate(grid_costs(1:ngrids))
        allocate(grid_sizes(1:ngrids))
        allocate(nbprocs_per_grid(1:ngrids))

      nbprocs_per_grid = 0
!
!     Allocate required procs to each grid
        gp => gridlist % first
        ig = 0
        do while ( associated(gp) )
            grid => gp % gr
            ig = ig+1 ; gridarray(ig)%gr => grid
            pp => grid % required_proc_list % first
            do while ( associated(pp) )
                procarray( pp % proc % pn+1 ) % grid_id = grid % fixedrank
                nbprocs_per_grid(ig) = nbprocs_per_grid(ig) + 1
                pp => pp % next
            enddo
            gp => gp % next
        enddo
!
!     Add unused procs to the grids
! TODO FIXME: This is just a dummy allocation. You should take into account grid size and more
!             information here...

! Estimate current costs

        total_grid_sizes = 0.
        do ig = 1, ngrids
          i1 = gridarray(ig)%gr%ix(1)
          i2 = gridarray(ig)%gr%ix(1)+gridarray(ig)%gr%nb(1)/gridarray(ig)%gr%spaceref(1)-1
          j1 = gridarray(ig)%gr%ix(2)
          j2 = gridarray(ig)%gr%ix(2)+gridarray(ig)%gr%nb(2)/gridarray(ig)%gr%spaceref(2)-1

          grid_sizes(ig) = (i2-i1+1)*(j2-j1+1)
          total_grid_sizes = total_grid_sizes + grid_sizes(ig)

          save_grid => Agrif_Curgrid
          Call Agrif_instance(gridarray(ig)%gr)

          Call Agrif_estimate_parallel_cost(i1,i2,j1,j2,nbprocs_per_grid(ig),grid_costs(ig))

          Call Agrif_instance(save_grid)

          grid_costs(ig) = grid_costs(ig) * gridarray(ig)%gr%timeref(1)
        enddo

        allocate(proc_was_required(proclist%nitems))
        proc_was_required = .TRUE.
        do ip = 1,proclist%nitems
            if ( procarray( ip ) % grid_id == 0 ) then
                proc_was_required(ip) = .FALSE.
            endif
        enddo

        ig = 1
        do ip = 1,proclist%nitems
            if ( procarray( ip ) % grid_id == 0 ) then
!             this proc is unused
              max_cost = 0.
              max_index = 1
              do ig = 1,ngrids
                 if (grid_costs(ig) > max_cost) then
                    max_cost = grid_costs(ig)
                    max_index = ig
                 endif
              enddo

              ig = max_index


              i1 = gridarray(ig)%gr%ix(1)
              i2 = gridarray(ig)%gr%ix(1)+gridarray(ig)%gr%nb(1)/gridarray(ig)%gr%spaceref(1)-1
              j1 = gridarray(ig)%gr%ix(2)
              j2 = gridarray(ig)%gr%ix(2)+gridarray(ig)%gr%nb(2)/gridarray(ig)%gr%spaceref(2)-1
              if (agrif_debug_parallel_sisters) then
                  if (Agrif_GlobProcRank == 0) then
                      print *,'Grid = ',ig,' Cost = ',grid_costs(ig)
                      print *,'Total number of procs = ',nbprocs_per_grid(ig) + 1
                      print *,'Size = ',gridarray(ig)%gr%nb(1),gridarray(ig)%gr%nb(2),(i2-i1+1)*(j2-j1+1)
                      print *,'Total Size = ',nint(total_grid_sizes)
                  endif
              endif

              maximum_number_of_procs_to_add = 1
              do ip2=ip+1,proclist%nitems
                 if (procarray(ip2)%grid_id == 0) then
                         maximum_number_of_procs_to_add = maximum_number_of_procs_to_add + 1
                 endif
              enddo

              if (agrif_debug_parallel_sisters) then
                  if (Agrif_GlobProcRank == 0) then
                         print *,'Number of procs remaining = ',maximum_number_of_procs_to_add
                  endif
              endif

              maximum_number_of_procs_to_add =                          &
                      max(maximum_number_of_procs_to_add/               &
                      (nint(2.*total_grid_sizes/grid_sizes(ig))),1)

              ip3 = 0
              ip2 = ip
              do while (ip3 < maximum_number_of_procs_to_add)
                 if (procarray(ip2)%grid_id == 0) then
                       ip3 = ip3 + 1
                       procarray( ip2 ) % grid_id = gridarray(ig) %gr % fixedrank
                 endif 
                 ip2 = ip2 + 1
              enddo
              if (agrif_debug_parallel_sisters) then
                  if (Agrif_GlobProcRank == 0) then
                         print *,'Number of procs added = ',maximum_number_of_procs_to_add
                  endif
              endif

              !procarray( ip ) % grid_id = gridarray(ig) %gr % fixedrank

              !nbprocs_per_grid(ig) =  nbprocs_per_grid(ig) + 1
              nbprocs_per_grid(ig) =  nbprocs_per_grid(ig) + maximum_number_of_procs_to_add

              save_grid => Agrif_Curgrid
              Call Agrif_instance(gridarray(ig)%gr)

              Call Agrif_estimate_parallel_cost(i1,i2,j1,j2,nbprocs_per_grid(ig),grid_costs(ig))

              Call Agrif_instance(save_grid)

              grid_costs(ig) = grid_costs(ig) * gridarray(ig)%gr%timeref(1)
              if (agrif_debug_parallel_sisters) then
                  if (Agrif_GlobProcRank == 0) then
                         print *,'Current grid costs = ',grid_costs(1:ngrids)
                  endif
              endif

            endif
        enddo

! Adjust the number of processors per grid
              if (agrif_debug_parallel_sisters) then
                  if (Agrif_GlobProcRank == 0) then
                         print *,'Now adjust the number of procs'
                  endif
              endif
        do ig = 1,ngrids
            imax = gridarray(ig)%gr%nb(1)/subdomain_minwidth
            jmax = gridarray(ig)%gr%nb(2)/subdomain_minwidth
            closest_nb_procs=-1
            deltaij=huge(1)
            do j=1,jmax
              do i=1,min(imax,nbprocs_per_grid(ig)/j)
                if ((nbprocs_per_grid(ig)-i*j) < deltaij) then
                        deltaij = nbprocs_per_grid(ig)-i*j
                        closest_nb_procs(1)=i
                        closest_nb_procs(2)=j
                endif
              enddo
            enddo

            if (agrif_debug_parallel_sisters) then
                if (Agrif_GlobProcRank == 0) then
                    print *,'The grid ',ig,' has ',nbprocs_per_grid(ig),' procs'
                    print *,'The closest decomposition is ',closest_nb_procs(1)*closest_nb_procs(2), &
                           closest_nb_procs(1),closest_nb_procs(2)
                endif
            endif
            number_of_procs_toremove = nbprocs_per_grid(ig) - closest_nb_procs(1)*closest_nb_procs(2)
            do while (number_of_procs_toremove > 0)
                do ip = 1,proclist%nitems
                  if ((procarray( ip ) % grid_id == gridarray(ig)%gr % fixedrank).AND.(.NOT. proc_was_required(ip))) then
                    procarray( ip ) % grid_id = 0
                    number_of_procs_toremove = number_of_procs_toremove - 1
                    nbprocs_per_grid(ig) = nbprocs_per_grid(ig) - 1
                    exit
                  endif
                enddo
            enddo
            if (agrif_debug_parallel_sisters) then
                if (Agrif_GlobProcRank == 0) then
                    print *,'After correction : The grid ',ig,' has ',nbprocs_per_grid(ig),' procs'
                endif
            endif
        enddo

! Now add the remaining procs
        ! Count the number of procs to add
        number_of_procs_toadd = 0
        do ip = 1,proclist%nitems
            if ( procarray( ip ) % grid_id == 0 ) then
                number_of_procs_toadd = number_of_procs_toadd + 1
            endif
        enddo

        inform_possible_nbprocs = .FALSE.

        if (number_of_procs_toadd > 0) then
            ! allocate(ispossibletoadd(ngrids,-2*number_of_procs_toadd:2*number_of_procs_toadd))
            ! ispossibletoadd = .FALSE.
            ! do ig=1,ngrids
            !     mask_possible_procs = .TRUE.
            !     do j = 1,Agrif_maxprocs1D
            !         if (gridarray(ig)%nb(2)/j < subdomain_minwidth) mask_possible_procs(:,j) = .FALSE.
            !     enddo
            !     do i = 1, Agrif_maxprocs1D
            !         if (gridarray(ig)%nb(1)/i < subdomain_minwidth) mask_possible_procs(i,:) = .FALSE.
            !     enddo
            !     do j=-2*number_of_procs_toadd,2*number_of_procs_toadd
            !         add_possible=minval(abs(possible_procs-(nbprocs_per_grid(ig)+j)),mask=mask_possible_procs)
            !         ispossibletoadd(ig,j) = add_possible == 0
            !     enddo
            ! enddo

            
            ! if (Agrif_GlobProcRank==0) then
            !     print *,'Possible add'
            ! do ig=1,ngrids
              
            !   do j=-2*number_of_procs_toadd,2*number_of_procs_toadd
            !     if (ispossibletoadd(ig,j)) then
            !         print *,'On grid = ',ig,' , ',j,' is ok'
            !     endif
            !   enddo
            ! enddo
            ! endif
            !deallocate(ispossibletoadd)



        do while (number_of_procs_toadd > 0)
            donproc: do nproc = number_of_procs_toadd, 1, -1
                number_of_procs_added = 0
                do ig = 1,ngrids
                ! test the possiblity to add to grid ig
                    imax = gridarray(ig)%gr%nb(1)/subdomain_minwidth
                    jmax = gridarray(ig)%gr%nb(2)/subdomain_minwidth
                    add_possible=1
                    externj: do j=1,jmax
                      do i=1,imax
                        if (i*j == nbprocs_per_grid(ig)+nproc) then
                          add_possible = 0
                          exit externj
                        endif
                      enddo
                    enddo externj
                    if (add_possible == 0) then
                        do ip = 1,proclist%nitems
                            if ( procarray( ip ) % grid_id == 0 ) then
                                procarray( ip ) % grid_id =gridarray(ig)%gr % fixedrank
                                nbprocs_per_grid(ig) = nbprocs_per_grid(ig) + 1
                                number_of_procs_added = number_of_procs_added + 1
                                if (agrif_debug_parallel_sisters) then
                                    if (Agrif_GlobProcRank == 0) then
                                        print *,'The proc can be added to the grid ',ig
                                    endif
                                endif
                                if (number_of_procs_added == nproc) exit donproc
                            endif
                        enddo
                        exit
                    endif
                enddo
            end do donproc
            if (number_of_procs_added == 0) then
                inform_possible_nbprocs = .TRUE.
                exit
            endif
            number_of_procs_toadd = number_of_procs_toadd - nproc
            if (agrif_debug_parallel_sisters) then
                if (Agrif_GlobProcRank == 0) then
                    print *,'Remaining number of procs to add = ',number_of_procs_toadd
                endif
            endif
        enddo
        endif

        if (inform_possible_nbprocs) then
            if (agrif_debug_parallel_sisters) then
                if (Agrif_GlobProcRank == 0) then
                    print *,'Impossible to add more procs'
                endif
                stop
            endif
        endif
!
!     Allocate proc nums to each grid
        gp => gridlist % first
        do while ( associated(gp) )
            do ip = 1,proclist%nitems
                if ( procarray( ip ) % grid_id == gp % gr % fixedrank ) then
                    allocate(proc)
                    proc = procarray( ip )
                    call Agrif_pl_append(gp % gr % proc_def_in_parent_list, proc)
                endif
            enddo
            gp => gp % next
        enddo
!
!     Clean up
        deallocate(procarray, gridarray, grid_costs, grid_sizes, nbprocs_per_grid, proc_was_required)

              if (agrif_debug_parallel_sisters) then
                  if (Agrif_GlobProcRank == 0) then
                         print *, 'sortie de modseq'
                  endif
              endif
!
    enddo
!---------------------------------------------------------------------------------------------------
end subroutine Agrif_seq_allocate_procs_to_childs
!===================================================================================================
!
!===================================================================================================
subroutine Agrif_seq_create_communicators ( grid )
!---------------------------------------------------------------------------------------------------
    type(Agrif_Grid), intent(inout) :: grid
!
    include 'mpif.h'
    type(Agrif_Sequence_List), pointer  :: seqlist  ! List of child sequences
    type(Agrif_PGrid), pointer          :: gridp
    type(Agrif_Proc),  pointer          :: proc
    integer     :: i, ierr
    integer     :: current_comm, comm_seq, color_seq
    integer, parameter :: color_seq_not_used = 100000000
    integer, parameter :: color_seq_not_initialized = -100
!
    seqlist => grid % child_seq
    if ( .not. associated(seqlist) ) return
!
    current_comm = grid % communicator
    
!
! For each sequence, split the current communicator into as many groups as needed.
    do i = 1,seqlist % nb_seqs
        color_seq = color_seq_not_initialized ! color_seq should be positive
                                              ! Initialize it to color_seq_not_initialized (<0)
                                              ! for MPI_COMM_SPLIT to raise error if needed
!
!     Loop over each proclist to give a color to the current process
        gridp => seqlist % sequences(i) % gridlist % first
        grid_loop : do while ( associated(gridp) )
            proc => Agrif_pl_search_proc( gridp % gr % proc_def_in_parent_list, Agrif_Procrank )
            if ( associated(proc) ) then
                if ( gridp % gr % fixedrank /= proc % grid_id ) then
                    write(*,'("### Error Agrif_seq_create_communicators : ")')
                    write(*,'("  inconsitancy on proc ",i2,":")') Agrif_Procrank
                    write(*,'("gr % fixedrank = ",i0,", where proc % grid_id = ",i0)') &
                            gridp % gr % fixedrank, proc % grid_id
                    stop
                endif
                color_seq = gridp % gr % fixedrank
                exit grid_loop
            endif
            gridp => gridp % next
        enddo grid_loop
!
        if (color_seq == color_seq_not_initialized) then
            if (agrif_debug_parallel_sisters) then
                print *,'The proc ',Agrif_Procrank,' is not integrating sequence ',i
            endif
            color_seq = color_seq_not_used ! color for non working processors
        endif
      !  print *,'sequnce = ',i,' current_comm = ',current_comm, 'color_seq = ',color_seq
        if (color_seq /= color_seq_not_used) then
           call MPI_COMM_SPLIT(current_comm, color_seq, Agrif_ProcRank, comm_seq, ierr)
       !    print *,'la grille ',gridp % gr % fixedrank,' a le communcateur ',comm_seq
             gridp % gr % communicator = comm_seq
        else
            call MPI_COMM_SPLIT(current_comm, MPI_UNDEFINED, Agrif_ProcRank, comm_seq, ierr)
        endif
!
    enddo
!---------------------------------------------------------------------------------------------------
end subroutine Agrif_seq_create_communicators
!===================================================================================================
!
!===================================================================================================
function Agrif_seq_select_child ( g, is ) result ( gridp )
!---------------------------------------------------------------------------------------------------
    type(Agrif_Grid), pointer, intent(in)   :: g
    integer,                   intent(in)   :: is
!
    type(Agrif_PGrid), pointer  :: gridp
    type(Agrif_Proc),  pointer  :: proc
!
    call Agrif_Instance( g )
    gridp => g % child_seq % sequences(is) % gridlist % first
!
    do while ( associated(gridp) )
        proc => Agrif_pl_search_proc( gridp % gr % proc_def_in_parent_list, Agrif_Procrank )
        if ( associated(proc) ) then
            return
        endif
        gridp => gridp % next
    enddo
    if (.not.associated(gridp)) then
        nullify(gridp) ! may happen if not all the processors are in the current sequence
        return
    endif
    write(*,'("### Error Agrif_seq_select_child : no grid found in sequence ",i0," (mother G",i0,") for P",i0)')&
        is, g%fixedrank, Agrif_Procrank
    stop
!---------------------------------------------------------------------------------------------------
end function Agrif_seq_select_child
!===================================================================================================
#else
    subroutine dummy_Agrif_seq ()
    end subroutine dummy_Agrif_seq
#endif
!
end module Agrif_seq
