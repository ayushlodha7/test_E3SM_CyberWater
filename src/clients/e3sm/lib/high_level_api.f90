module high_level_api
  use iso_c_binding, only: c_char, c_double, C_NULL_CHAR, c_ptr, c_associated, c_f_pointer
  use low_level_fortran_interface
  implicit none

  character(len=256) :: server_url = ""  ! Dynamic server URL
  integer(c_int), dimension(5) :: session_id
  integer(c_int) :: invitee_id
  ! [source_model_ID, destination_model_ID, initiator_id, invitee_id, unique_counter]
  integer :: var_send  ! Global variable ID for sending data
  integer :: var_receive  ! Global variable ID for receiving data
  logical :: server_url_set = .false.    ! Flag to check if server URL has been set

  type session_data
    integer :: source_model_ID
    integer :: destination_model_ID
    integer :: initiator_id
    integer :: invitee_id
    integer, dimension(:), allocatable :: input_variables_ID
    integer, dimension(:), allocatable :: input_variables_size
    integer, dimension(:), allocatable :: output_variables_ID
    integer, dimension(:), allocatable :: output_variables_size
  end type session_data

contains

  !===============================================================================
  subroutine set_server_url(url)
    character(len=*), intent(in) :: url
    if (len(trim(url)) > 0) then
      server_url = trim(url)
      server_url_set = .true.
    else
      print *, "Error: Invalid server URL provided."
      server_url_set = .false.
    endif
  end subroutine set_server_url

  !===============================================================================

  subroutine set_session_id(id)
    integer(c_int), dimension(5), intent(in) :: id
    session_id = id
  end subroutine set_session_id
  
  !===============================================================================

  subroutine start_session(sd)
    type(session_data), intent(inout) :: sd

    ! Create a session with the server using the data from 'sd'
    call create_session(trim(server_url)// C_NULL_CHAR, sd%source_model_ID, sd%destination_model_ID, &
                          sd%initiator_id, sd%invitee_id, sd%input_variables_ID, &
                          sd%input_variables_size, size(sd%input_variables_ID), &
                          sd%output_variables_ID, sd%output_variables_size, &
                          size(sd%output_variables_ID))
    ! No cleanup needed here as 'sd' is managed by the calling program
  end subroutine start_session

  !===============================================================================
  function retrieve_specific_session_status(session_id) result(status_int)
    use iso_c_binding, only: c_int, c_char, c_null_char
    implicit none
    integer(c_int), dimension(*), intent(in) :: session_id
    integer(c_int) :: status_int

    ! Ensure the server URL is set
    if (.not. server_url_set) then
        print *, "Error: Server URL not set."
        status_int = -1  ! Indicate error
        return
    endif

    ! Call the C function and get the status as an integer
    status_int = get_specific_session_status(trim(server_url)//c_null_char, session_id)

    if (status_int == 0) then
        print *, "Failed to retrieve session status."
    endif
  end function retrieve_specific_session_status

  !===============================================================================
  function join_session_with_retries(session_id, invitee_id, max_retries, sleep_time) result(join_status)
    use iso_c_binding, only: c_int, c_char, c_null_char
    implicit none
    integer(c_int), intent(in) :: session_id(*)
    integer(c_int), intent(in) :: invitee_id, max_retries, sleep_time
    integer(c_int) :: join_status
    integer :: retries

    ! Ensure the server_url is set
    if (.not. server_url_set) then
        print *, "Error: Server URL not set. Please set a valid server URL before attempting to join the session."
        join_status = 0  ! Indicate failure
        return
    endif

    join_status = 0  ! Default to failure
    retries = 0

    do while (retries < max_retries .and. join_status == 0)
        ! Call the C function to attempt to join the session
        join_status = join_session(trim(server_url)//c_null_char, session_id, invitee_id)

        if (join_status == 1) then
            print *, "Joined the session successfully."
            return  ! Exit as soon as the session is joined successfully
        else
            print *, "Attempt to join failed, retrying..."
            call sleep(sleep_time)  ! Assuming a sleep subroutine or intrinsic is available
            retries = retries + 1
        endif
    end do

    if (join_status == 0) then
        print *, "Failed to join session after ", max_retries, " attempts."
    endif
  end function join_session_with_retries

  !===============================================================================

  function send_data_with_retries(var_send, arr_send, max_retries, sleep_time) result(status_send)
      use low_level_fortran_interface    
      use iso_c_binding, only: c_double 
      implicit none

      integer, intent(in) :: var_send, max_retries, sleep_time
      real(c_double), dimension(:), intent(in) :: arr_send

      ! Variable declarations
      integer :: arr_length                                ! Length of the array to send
      integer :: retries                                   ! Retry count allowed
      integer :: flag                                      ! Flag to check status

      integer :: status_send                               ! Function result

      status_send = 0                                       ! Initialize status_send to 0 (failure)
      retries = 0                                           ! Initialize retry counter

      ! Prepare data array
      arr_length = get_specific_variable_size(trim(server_url)// C_NULL_CHAR, session_id, var_send)

      ! Attempt to send data with retries
      do while (retries < max_retries)
          flag = get_specific_variable_flag(trim(server_url)// C_NULL_CHAR, session_id, var_send)
          print *, "Flag status:", flag

          if (flag == 0) then
              status_send = send_data(trim(server_url)// C_NULL_CHAR, session_id, var_send, arr_send, arr_length)
              if (status_send == 1) then
                  print *, "Data successfully sent."
                  return
              else
                  print *, "Failed to send data, retrying..."
                  retries = retries + 1
              end if
          else
              print *, "Flag is not set for sending, retrying..."
              retries = retries + 1
          endif
          call sleep(sleep_time)
      end do

      ! Check if maximum retries have been exceeded
      if (retries >= max_retries) then
          print *, "Failed to send data for var_id", var_send, "after", max_retries, "attempts due to flag status."
      endif
  end function send_data_with_retries

  !===============================================================================
  function check_data_availability_with_retries(var_id, max_retries, sleep_time) result(status_available)
      use low_level_fortran_interface
      use iso_c_binding, only: c_double, c_int

      implicit none
      integer, intent(in) :: var_id, max_retries, sleep_time
      integer :: retries, flag_status
      integer :: status_available

      status_available = 0                                  ! Initialize status_available to 0 (not available)
      retries = 0                                           ! Initialize retry counter

      ! Attempt to check data availability with retries
      do while (retries < max_retries)
          flag_status = get_specific_variable_flag(trim(server_url)// C_NULL_CHAR, session_id, var_id)
          print *, "Checking data availability. Flag status:", flag_status
          
          if (flag_status == 1) then
              print *, "Data is available for variable ID:", var_id
              status_available = 1                          ! Set status_available to 1 (available)
              return
          else
              print *, "Data not available, retrying..."
              retries = retries + 1
          endif
          call sleep(sleep_time)                            ! Wait before next retry
      end do

      ! Check if maximum retries have been exceeded
      if (retries >= max_retries) then
          print *, "Failed to confirm data availability for variable ID:", var_id, "after", max_retries, "attempts."
      endif
  end function check_data_availability_with_retries
  !===============================================================================
  function retrieve_specific_variable_size(session_ids, var_id) result(var_size)
    integer, dimension(:), intent(in) :: session_ids
    integer, intent(in) :: var_id
    integer :: var_size
    integer :: status  ! Internal status variable

    ! Call the low-level API function to get the size
    var_size = get_specific_variable_size(trim(server_url)//C_NULL_CHAR, session_ids, var_id)

    ! Status checking after API call
    if (var_size < 0) then
      print *, "Error: Unable to get variable size for ID", var_id
      status = -1  ! Indicating an error
    else
      status = 0   ! Indicating success
    end if

    ! Optionally, modify the function to return -1 in case of an error
    if (status == -1) then
      var_size = -1  ! Reset var_size to indicate error clearly to the caller
    end if
  end function retrieve_specific_variable_size
  !===============================================================================

  function receive_data_with_retries(var_receive, arr_receive, max_retries, sleep_off_time) result(status_receive)
      use low_level_fortran_interface      
      use iso_c_binding, only: c_double  
      implicit none

      integer, intent(in) :: var_receive, max_retries, sleep_off_time
      real(c_double), dimension(:), intent(inout) :: arr_receive

      ! Variable declarations
      integer :: retries                                        ! Retry count
      integer :: status_receive                                 ! Status of the receive operation

      retries = 0                                               ! Initialize retry counter
      status_receive = 0                                        ! Initialize receive status to 0 (failure)

      ! Attempt to receive data with retries
      do while (retries < max_retries)
          status_receive = receive_data(trim(server_url)// C_NULL_CHAR, session_id, var_receive, arr_receive, size(arr_receive))

          if (status_receive == 1) then
              print *, "Data received successfully for variable ID:", var_receive
              return  ! Exit function returning status_receive as 1 (success)
          else
              print *, "Failed to fetch data for variable ID:", var_receive, ", retrying..."
              retries = retries + 1
              call sleep(sleep_off_time)
          end if
      end do

      ! Check if maximum retries have been exceeded
      if (retries >= max_retries) then
          print *, "Failed to receive data for var_id:", var_receive, "after", max_retries, "attempts."
      endif

      ! The function will return status_receive which will be 0 if all retries failed
  end function receive_data_with_retries

  !===============================================================================

  subroutine end_session_now(user_id)
      use low_level_fortran_interface     ! Include module for HTTP interface methods
      use iso_c_binding, only: c_int      ! Use ISO C binding to ensure compatibility with C types
      implicit none

      integer(c_int), intent(in) :: user_id

      ! End the session with the server
      call end_session(trim(server_url)// C_NULL_CHAR, session_id, user_id)

  end subroutine end_session_now

  !===============================================================================

end module high_level_api

!Unused/ Extra High level endpoints provided for interacting with the server
!   subroutine join_session()
!       use iso_c_binding, only: c_int
!       implicit none

!       ! Call the C function to join a session
!       call join_session_c(trim(server_url)// C_NULL_CHAR, session_id, invitee_id)

!   end subroutine join_session

! subroutine check_session_availability()
!   ! Checks the availability of sessions and prints their statuses
!   if (.not. server_url_set) then
!       print *, "Error: Server URL not set. Please set a valid server URL before checking session statuses."
!       return
!   endif

!   ! Call the C binding to print all session statuses
!   call print_all_session_statuses(trim(server_url) // C_NULL_CHAR)
! end subroutine check_session_availability

! !===============================================================================

! subroutine check_specific_session_flags(session_ids)
!   integer, dimension(:), intent(in) :: session_ids
!   ! Checks and prints the flag status for the variables of a specific session
!   if (.not. server_url_set) then
!       print *, "Error: Server URL not set. Please set a valid server URL before checking variable flags."
!       return
!   endif

!   ! Ensure session IDs are passed correctly
!   if (size(session_ids) /= 5) then
!       print *, "Error: Invalid session ID array size."
!       return
!   endif

!   ! Call the C binding to print all variable flags for the session
!   call print_all_variable_flags(trim(server_url) // C_NULL_CHAR, session_ids)
! end subroutine check_specific_session_flags
! !===============================================================================

