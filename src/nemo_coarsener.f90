PROGRAM NEMO_COARSENER

   USE io_ezcdf
   USE mod_manip

   IMPLICIT NONE

   !! ************************ Configurable part ****************************
   LOGICAL, PARAMETER :: &
      &   l_debug    = .FALSE., &
      &   l_drown_in = .FALSE. ! Not needed since we ignore points that are less than 1 point away from land... drown the field to avoid spurious values right at the coast!
   !!
   REAL(8), PARAMETER :: res = 0.1  ! resolution in degree
   !!
   INTEGER :: Nt0, Nti, Ntf, io, idx, iP, jP, npoints, jl, imgnf
   !!
   REAL(8), DIMENSION(:,:), ALLOCATABLE :: vpt_lon, vpt_lat
   !!


   !! Coupe stuff:
   REAL(8), DIMENSION(:), ALLOCATABLE :: Ftrack_in, Ftrack_in_np, Ftrack_obs, rcycle_obs, vdistance


   !! Grid, default name :
   CHARACTER(len=80) :: &
      &    cv_in, &
      &    cv_t   = 'time_counter',  &
      &    cv_lon = 'glamt',         & ! input grid longitude name, T-points
      &    cv_lat = 'gphit'            ! input grid latitude name,  T-points

   CHARACTER(len=256)  :: cr, cunit
   CHARACTER(len=512)  :: cdir_home, cdir_out, cdir_tmpdir, cdum, cconf
   !!
   !!
   !!******************** End of conf for user ********************************
   !!
   !!               ** don't change anything below **
   !!
   LOGICAL ::  &
      &     l_reg_src, &
      &     l_exist   = .FALSE., &
      &     l_use_anomaly = .FALSE., &  ! => will transform a SSH into a SLA (SSH - MEAN(SSH))
      &     l_loc1, l_loc2, &
      &     l_obs_ok
   !!
   !!
   CHARACTER(len=400)  :: &
      &    cf_in, cf_mm, &
      &    cf_ascii='file_in.txt'
   !!
   CHARACTER(len=512), DIMENSION(:), ALLOCATABLE :: cf_out
   !!
   INTEGER      :: &
      &    jarg, i1, i2, j1, j2, &
      &    idot, ip1, jp1, im1, jm1, &
      &    i0=0, j0=0, ifi=0, ivi=0, &
      &    ni, nj, Nt=0, nk=0, &
      &    ni1, nj1, ni2, nj2, &
      &    iargc, id_f1, id_v1
   !!

   !!
   INTEGER :: ji_min, ji_max, jj_min, jj_max, nib, njb

   REAL(4), DIMENSION(:,:), ALLOCATABLE :: xvar

   REAL(4), DIMENSION(:,:), ALLOCATABLE :: xdum_r4, show_obs
   REAL(8), DIMENSION(:,:), ALLOCATABLE ::    &
      &    xlont, xlatt, xlont_tmp
   !!
   INTEGER, DIMENSION(:,:), ALLOCATABLE :: JJidx, JIidx    ! debug
   !!
   INTEGER :: jt, jt0, jtf, jt_s, jtm_1, jtm_2, jtm_1_o, jtm_2_o, jb, js
   !!
   REAL(8) :: rt, rt0, rdt, &
      &       t_min_e, t_max_e, t_min_m, t_max_m, &
      &       alpha, beta, t_min, t_max
   !!
   CHARACTER(LEN=2), DIMENSION(6), PARAMETER :: &
      &            clist_opt = (/ '-h','-m','-i','-v','-x','-y' /)

   REAL(8) :: lon_min_1, lon_max_1, lon_min_2, lon_max_2, lat_min, lat_max, r_obs

   REAL(8) :: lon_min_trg, lon_max_trg, lat_min_trg, lat_max_trg



   !CALL GET_ENVIRONMENT_VARIABLE("HOME", cdir_home)
   !CALL GET_ENVIRONMENT_VARIABLE("TMPDIR", cdir_tmpdir)


   !cdir_out = TRIM(cdir_tmpdir)//'/EXTRACTED_BOXES' ! where to write data!
   cdir_out = '.'



   !! Getting string arguments :
   !! --------------------------

   jarg = 0

   DO WHILE ( jarg < iargc() )

      jarg = jarg + 1
      CALL getarg(jarg,cr)

      SELECT CASE (trim(cr))

      CASE('-h')
         call usage()

      CASE('-m')
         CALL GET_MY_ARG('mesh_mask', cf_mm)
         
      CASE('-i')
         CALL GET_MY_ARG('input file', cf_in)

      CASE('-v')
         CALL GET_MY_ARG('input file', cv_in)

      CASE('-x')
         CALL GET_MY_ARG('longitude', cv_lon)

      CASE('-y')
         CALL GET_MY_ARG('latitude', cv_lat)

      CASE DEFAULT
         PRINT *, 'Unknown option: ', trim(cr) ; PRINT *, ''
         CALL usage()

      END SELECT

   END DO

   IF ( (trim(cv_in) == '').OR.(trim(cf_in) == '') ) THEN
      PRINT *, ''
      PRINT *, 'You must at least specify input file (-i) !!!'
      CALL usage()
   END IF

   PRINT *, ''
   PRINT *, ''; PRINT *, 'Use "-h" for help'; PRINT *, ''
   PRINT *, ''

   PRINT *, ' * Input file = ', trim(cf_in)
   PRINT *, '   => associated variable names = ', trim(cv_in)
   PRINT *, '   => associated longitude/latitude/time = ', trim(cv_lon), ', ', trim(cv_lat)


   PRINT *, ''

   !! Name of config: lulu
   idot = SCAN(cf_in, '/', back=.TRUE.)
   cdum = cf_in(idot+1:)
   idot = SCAN(cdum, '.', back=.TRUE.)
   cconf = cdum(:idot-1)

   PRINT *, ' *** CONFIG: cconf ='//TRIM(cconf) ; PRINT *, ''


   !! testing longitude and latitude
   !! ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   INQUIRE(FILE=TRIM(cf_in), EXIST=l_exist )
   IF ( .NOT. l_exist ) THEN
      PRINT *, 'ERROR: input file not found! ', TRIM(cf_in)
      call usage()
   END IF
   INQUIRE(FILE=TRIM(cf_mm), EXIST=l_exist )
   IF ( .NOT. l_exist ) THEN
      PRINT *, 'ERROR: mesh_mask file not found! ', TRIM(cf_mm)
      call usage()
   END IF


   CALL DIMS(cf_mm, cv_lon, ni1, nj1, nk, Nt)
   !CALL DIMS(cf_in, cv_lat, ni2, nj2, nk, Nt)
   !IF ( (nj1==-1).AND.(nj2==-1) ) THEN
   !   ni = ni1 ; nj = ni2
   !   PRINT *, 'Grid is 1D: ni, nj =', ni, nj
   !   l_reg_src = .TRUE.
   !ELSE
   !   IF ( (ni1==ni2).AND.(nj1==nj2) ) THEN
   !      ni = ni1 ; nj = nj1
   !      PRINT *, 'Grid is 2D: ni, nj =', ni, nj
   !      l_reg_src = .FALSE.
   !   ELSE
   !      PRINT *, 'ERROR: problem with grid!' ; STOP
   !   END IF
   !END IF



   CALL DIMS(cf_in, cv_in, ni, nj, nk, Nt)
   PRINT *, ' *** input field: ni, nj, nk, Nt =>', ni, nj, nk, Nt
   PRINT *, ''

   IF ( (ni/=ni1).OR.(nj/=nj1) ) STOP 'Problem of shape between input field and mesh_mask!'
   
   
   !ni = ni1 ; nj = ni1
   ALLOCATE ( xlont(ni,nj), xlatt(ni,nj), xdum_r4(ni,nj) )
   ALLOCATE ( xlont_tmp(ni,nj) )
   PRINT *, ''





   !! Getting model longitude & latitude:
   ! Longitude array:
   CALL GETVAR_2D(i0, j0, cf_mm, cv_lon, 0, 0, 0, xlont)
   i0=0 ; j0=0
   !!
   ! Latitude array:
   CALL GETVAR_2D   (i0, j0, cf_mm, cv_lat, 0, 0, 0, xlatt)
   i0=0 ; j0=0

   !! Min an max lon:
   !lon_min_1 = MINVAL(xlont)
   !lon_max_1 = MAXVAL(xlont)
   !PRINT *, ' *** Minimum longitude on model grid before : ', lon_min_1
   !PRINT *, ' *** Maximum longitude on model grid before : ', lon_max_1
   !!
   !xlont_tmp = xlont
   !WHERE ( xdum_r4 < 0. ) xlont_tmp = xlont + 360.0_8
   !!
   !lon_min_2 = MINVAL(xlont_tmp)
   !lon_max_2 = MAXVAL(xlont_tmp)
   !PRINT *, ' *** Minimum longitude on model grid: ', lon_min_2
   !PRINT *, ' *** Maximum longitude on model grid: ', lon_max_2
   !! Min an max lat:
   !lat_min = MINVAL(xlatt)
   !lat_max = MAXVAL(xlatt)
   !PRINT *, ' *** Minimum latitude on model grid : ', lat_min
   !PRINT *, ' *** Maximum latitude on model grid : ', lat_max

   DO jt=1, Nt

      PRINT *, ''
      PRINT *, ' Reading field '//TRIM(cv_in)//' at record #',jt
      
      CALL GETVAR_2D   (ifi, ivi, cf_in, cv_in, Nt, 0, jt, xdum_r4)

   END DO






CONTAINS






   SUBROUTINE GET_MY_ARG(cname, cvalue)
      CHARACTER(len=*), INTENT(in)    :: cname
      CHARACTER(len=*), INTENT(inout) :: cvalue
      !!
      IF ( jarg + 1 > iargc() ) THEN
         PRINT *, 'ERROR: Missing ',trim(cname),' name!' ; call usage()
      ELSE
         jarg = jarg + 1 ;  CALL getarg(jarg,cr)
         IF ( ANY(clist_opt == trim(cr)) ) THEN
            PRINT *, 'ERROR: Missing',trim(cname),' name!'; call usage()
         ELSE
            cvalue = trim(cr)
         END IF
      END IF
   END SUBROUTINE GET_MY_ARG





   SUBROUTINE usage()
      !!
      !OPEN(UNIT=6, FORM='FORMATTED', RECL=512)
      !!
      WRITE(6,*) ''
      WRITE(6,*) '   List of command line options:'
      WRITE(6,*) '   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~'
      WRITE(6,*) ''
      WRITE(6,*) ' -m <mesh_mask.nc>    => file containing grid metrics of model'
      WRITE(6,*) ''      
      WRITE(6,*) ' -i <input_file.nc>   => input file to coarsen'
      WRITE(6,*) ''
      WRITE(6,*) ' -v <name_field>      => variable to coarsen'
      WRITE(6,*) ''
      WRITE(6,*) '    Optional:'
      WRITE(6,*) ' -h                   => Show this message'
      WRITE(6,*) ''
      WRITE(6,*) ' -x  <name>           => Specify longitude name in input file (default: '//TRIM(cv_lon)//')'
      WRITE(6,*) ''
      WRITE(6,*) ' -y  <name>           => Specify latitude  name in input file  (default: '//TRIM(cv_lon)//')'
      WRITE(6,*) ''
      WRITE(6,*) ''
      !!
      STOP
      !!
   END SUBROUTINE usage




END PROGRAM NEMO_COARSENER




!!
