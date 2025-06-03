#########################
#  
# 
# net::client ip port
#
# $nc configure option value
#   options:
#     fconfigure related
#     -buffering
#     -blocking
#     -buffersize
#     -translation
#     -encoding
#     -eofchar
#     tls related
#     -cadir
#     -cafile
#     -certfile
#     -keyfile
#     -cipher
#     -command
#     -password
#     -request
#     -require
#     -ssl2
#     -ssl3
#     -tls1
#     events
#     -onerror
#     -onclose
#     -onget
#     -onconnect
#     -onsecured
#     -onfail
#     -ontimeout
#     -onlog
#     miselaneous
#     -timeout
#     -getsread
#     -nonewline
#
package provide net 0.11

package require tls

###
#
# netcli.tcl
#
###


#*********
#
#
#
namespace eval net {
  variable clientprofile
  variable getsreadcmd
  variable nonewlinecmd
  variable incrid

  set incrid {
    variable id [incr id 0]
    proc getid {} {
      variable id
      return [format %010x [incr id]]
    }
  }
  set clientprofile {
    variable tx           0
    variable rx           0
    variable sock         ""
    variable port         ""
    variable ip           ""
    variable timeout      0
    # events
    variable onerror      ""
    variable onclose      ""
    variable onget        ""
    variable onconnect    ""
    variable onsecured    ""
    variable onunsecured  ""
    variable onfail       ""
    variable ontimeout    ""
    variable onlog        ""
    # config fconfigure, set to default
    variable blocking     1
    variable buffering    full
    variable buffersize   4096
    variable encoding     utf-8
    variable eofchar      {{} {}}
    variable translation  {auto crlf}
    variable async        0
    # config ssl, set to default
    variable cadir        ""
    variable cafile       ""
    variable certfile     ""
    variable keyfile      ""
    variable cipher       ""
    variable command      ""
    variable password     ""
    variable request      1
    variable require      0
    variable ssl2         1
    variable ssl3         1
    variable tls1         0
    # status
    variable connected    0
    variable inprocess    0
    variable secured      0
    variable autoflush    0
    variable readsize     0
    variable aftertimeout ""
    variable loglevel     0
    variable getsread     gets
    variable nonewline    0

    proc disconnect    {}     {::net::_clidisconnect}
    proc configure     {args} {::net::_cliconfigure}
    proc cget          {arg}  {::net::_clicget}
    proc destroy       {}     {::net::_clidestroy}
    proc send          {arg}  {::net::_clisend}
    proc gosecure      {}     {::net::_gosecure}
    proc unsecure      {}     {::net::_unsecure}
    proc connflush     {}     {::net::_cliflush}
    proc clearlog      {}     {::net::_clearlog}
    proc _get          {}     {::net::_cliget}
    proc _closeconn    {}     {::net::_clicloseconn}
    proc _handshake    {}     {::net::_handshake}
    proc _awaiting     {}     {::net::_cliawaiting}
    proc _timeout      {}     {::net::_clitimeout}
    proc _clilog       {a m}  {::net::_clilog}

    namespace ensemble create

    if {$server} {
      namespace export disconnect configure cget send gosecure unsecure clearlog
    } else {
      proc connect       {}     {::net::_cliconnect}
      proc connectsecure {}     {variable secured 1 ; ::net::_cliconnect}
      namespace export connect connectsecure disconnect configure cget destroy send gosecure unsecure clearlog
    }
  }

  array set getsreadcmd {gets {gets $sock d} read {set d [read $sock]} readsize {set d [read $sock $readsize]}}
  array set nonewlinecmd {0 {puts $sock $arg} 1 {puts -nonewline $sock $arg}}

  #*********
  #
  #
  #
  namespace eval cli $incrid

  #*********
  #
  #
  #
  namespace eval srv $incrid

  ##########
  #
  # proc ::net::client
  #
  proc client {ip port args} {
    variable clientprofile
    set netid [::net::cli::getid]
    set ns ::net::cli::$netid
    namespace eval $ns {variable server 0}
    namespace eval $ns $::net::clientprofile
    set ${ns}::ip $ip
    set ${ns}::port $port
    # Falta $args (fconfigure)
    return $ns
  }

  ##########
  #
  # proc ::net::_cliconnect
  #
  proc _cliconnect {} {
    uplevel 1 {
      variable sock
      variable ip
      variable port
      variable connected
      variable inprocess
      variable secured

      if {$connected > 0} {
        # If already connected return
        return -code error "Already connected"
      } elseif {$inprocess} {
        # If connection in process return
        return -code error "Connection in process"
      } else {
        variable async

        if {$secured} {
          # Setting up options if secured
          foreach x {cadir cafile certfile keyfile cipher command password request require ssl2 ssl3 tls1} {
            variable $x
            if {[set $x] != ""} {
              append options " -$x [set $x]"
            }
          }
        }

        # Asynchronous
        if {$async} {
          set asyncop -async
        } else {
          set asyncop ""
        }

        if {$secured} {
          # Reset ssl options
          tls::init
          # Set options
          catch "tls::init $options"
          _clilog connecting "secured [string range $asyncop 1 end] $ip $port"
          set p [catch "tls::socket $asyncop $ip $port" sock]
        } else {
          # Plain connection
          _clilog connecting "[string range $asyncop 1 end] $ip $port"
          set p [catch "socket $asyncop $ip $port" sock]
        }

        # $p contains the result of the initial connection
        if {$p} {
          variable onerror
          _clilog error $sock
          if {$onerror != ""} {
            uplevel #0 [list $onerror $sock]
          } else {
            return -code error "Error on connecting: $sock"
          }
        _closeconn
        } else {
          if {$async} {
            # Asynchronous connection
            variable timeout
            variable inprocess 1
            if {$timeout > 0} {
              variable aftertimeout [after [expr {$timeout * 1000}] [namespace current]::_timeout]
            }
            if {$secured} {
              # tls handles the connection status
              fconfigure $sock -blocking 0
              fileevent $sock readable "[namespace current]::_handshake"
              _handshake
            } else {
              foreach x {blocking buffering buffersize eofchar translation encoding} {
                variable $x
                if {[set $x] != ""} {
                  fconfigure $sock -$x [set $x]
                }
              }
              fileevent $sock readable "[namespace current]::_awaiting"
            }
          } else {
            if {$secured} {
              variable inprocess 1
              fconfigure $sock -blocking 0
              fileevent $sock readable "[namespace current]::_handshake"
              _handshake
            } else {
              variable tx 0
              variable rx 0
              variable inprocess 0
              variable secured 0
              set connected [clock seconds]
              # Setting up channel options
              foreach x {blocking buffering buffersize eofchar translation encoding} {
                variable $x
                if {[set $x] != ""} {
                  fconfigure $sock -$x [set $x]
                }
              }
              _clilog connected {}
              fileevent $sock readable [namespace current]::_get
              variable server
              if {!$server} {
                variable onconnect
                if {$onconnect != ""} {
                  uplevel #0 $onconnect
                }
              }
            }
          }
        }
      }
    }
  }


  ##########
  #
  # proc ::net::_cliawaiting
  #
  proc _cliawaiting {} {
    uplevel 1 {
      variable sock
      variable aftertimeout
      variable getsread
      variable readsize
      if {$getsread == "read" && $readsize > 0} {
        set gr $::net::getsreadcmd(readsize)
      } else {
        set gr $::net::getsreadcmd($getsread)
      }
      if {$aftertimeout != ""} {
        after cancel $aftertimeout
        set aftertimeout ""
      }
      if {[eof $sock]} {
 #       variable inprocess 0
        variable connected 0
        variable onfail
        variable sock
        _clilog fail eof
        if {$onfail != ""} {
          uplevel #0 [list $onfail eof]
        }
        _closeconn
#        catch {close $sock}
      } elseif {[catch $gr err]} {
#        variable inprocess 0
        variable connected 0
        variable onfail
        variable sock
        _clilog fail $err
        if {$onfail != ""} {
          uplevel #0 [list $onfail $err]
        }
        _closeconn
#        catch {close $sock}
      } else {
        variable inprocess 0
        variable connected [clock seconds]
        foreach x {blocking buffering buffersize eofchar translation encoding} {
          variable $x
          if {[set $x] != ""} {
            fconfigure $sock -$x [set $x]
          }
        }
        fileevent $sock readable [namespace current]::_get
        _clilog connected {}
        variable server
        if {!$server} {
          variable onconnect
          if {$onconnect != ""} {
            uplevel #0 $onconnect
          }
        }
        variable onget
        variable rx 0
        variable tx 0
        set rx [expr [string length $d]]
        if {$onget != ""} {
          uplevel #0 [list $onget $d]
        }
      }
    }
  }

  ##########
  #
  # proc ::net::_handshake
  #
  proc _handshake {} {
    uplevel 1 {
      variable sock
      variable aftertimeout
      if {$aftertimeout != ""} {
        after cancel $aftertimeout
        set aftertimeout ""
      }
      if {[eof $sock]} {
        variable inprocess 0
        variable onfail
        _clilog fail eof
#        puts "EOF on handshake??"
        if {$onfail != ""} {
          uplevel #0 [list $onfail eof]
        }
        _closeconn
      } elseif {[catch {tls::handshake $sock} result]} {
        variable inprocess 0
        variable onfail
        _clilog fail $result
        if {$onfail != ""} {
          uplevel #0 [list $onfail $result]
        }
        variable onfailcount
        incr onfailcount
        if {$onfailcount > 10} {
          variable connected 0
          set onfailcount 0
          _closeconn
        }
      } elseif {$result == 1} {
        foreach x {blocking buffering buffersize eofchar translation encoding} {
          variable $x
          if {[set $x] != ""} {
            fconfigure $sock -$x [set $x]
          }
        }
        variable connected
        variable inprocess 0
        variable secured 1
        variable server
        if {$server} {
          variable onsecured
          if {$onsecured != ""} {
            uplevel #0 $onsecured
          }
        } else {
          if {$connected == 0} {
            variable rx 0
            variable tx 0
            _clilog connected {}
            set connected [clock seconds]
            variable onconnect
            if {$onconnect != ""} {
              uplevel #0 $onconnect
            }
          } else {
            variable onsecured
            if {$onsecured != ""} {
              uplevel #0 $onsecured
            }
          }
        }
        variable onget
        if {$onget == ""} {
          fileevent $sock readable {}
        } else {
          fileevent $sock readable "[namespace current]::_get"
        }
      }
    }
  }

  ##########
  #
  # proc ::net::_clitimeout
  #
  proc _clitimeout {} {
    uplevel 1 {
      variable sock
      variable inprocess 0
      variable ontimeout
      if {[fconfigure $sock -connecting]} {
        _clilog timeout {}
	      if {$ontimeout != ""} {
	        uplevel #0 $ontimeout
	      }
        _closeconn
      }
    }
  }

  ##########
  #
  # proc ::net::_gosecure
  #
  proc _gosecure {} {
    uplevel 1 {
      variable onfailcount 0
      foreach x {cadir cafile certfile keyfile cipher command password request require ssl2 ssl3 tls1 server} {
        variable $x
        if {[set $x] != ""} {
          append options " -$x [set $x]"
        }
      }
      tls::init
      # Set options
      catch "tls::init $options"
      _clilog connecting "secured import"
      variable sock
#      fconfigure $sock -blocking 0 -buffering none -buffersize 4096 -translation {auto crlf} -encoding utf-8 -eofchar {{} {}}
      set d [read $sock]
#      puts "GOSECURE FLUSH [string length $d] - $d"
      fconfigure $sock -blocking 0 -buffering line
      catch "tls::import $sock $options"
      fileevent $sock readable "[namespace current]::_handshake"
      if {!$server} {
        after 100 [namespace current]::_handshake
      }
    }
  }

  ##########
  #
  # proc ::net::_unsecure
  #
  proc _unsecure {} {
    uplevel 1 {
      variable connected
      variable secured
      if {$connected == 0} {
        return -code error "Not connected"
      } elseif {!$secured} {
        return -code error "No secured channel"
      } else {
        variable sock
        fconfigure $sock -blocking 0
        fileevent $sock readable ""
        tls::unimport $sock
        set secured 0
        foreach x {blocking buffering buffersize eofchar translation encoding} {
          variable $x
          if {[set $x] != ""} {
            fconfigure $sock -$x [set $x]
          }
        }
        variable onunsecured
        if {$onunsecured != ""} {
          uplevel #0 $onunsecured
        }
        variable onget
        if {$onget == ""} {
          fileevent $sock readable {}
        } else {
          fileevent $sock readable "[namespace current]::_get"
        }
      }
    }
  }

  ##########
  #
  # proc ::net::_clisend
  #
  proc _clisend {} {
    uplevel 1 {
      variable connected
      variable sock
      variable nonewline
      if {$connected == 0} {
        return -code error "Not connected"
      } elseif {[catch $::net::nonewlinecmd($nonewline) err]} {
        variable onerror
        _clilog error $err
        if {$onerror != ""} {
          uplevel #0 [list $onerror $err]
        }
        _closeconn
      } else {
        variable autoflush
        if {$autoflush} {
          flush $sock
        }
        variable tx
        set tx [expr [string length $arg] + $tx]
      }
      return
    }
  }

  ##########
  #
  # proc ::net::_cliget
  #
  proc _cliget {} {
    uplevel 1 {
      variable sock
      variable getsread
      variable readsize
      variable connected
#      if {[chan pending input $sock] > 5000000} {
#        puts "get! $sock $getsread [chan pending input $sock]"
#        puts "Packet size too big!!"
#        _closeconn
#      }
      if {!$connected} {return}
      if {$getsread == "read" && $readsize > 0} {
        set gr $::net::getsreadcmd(readsize)
      } else {
        set gr $::net::getsreadcmd($getsread)
      }
      if {[eof $sock]} {
        _clilog get eof
        _closeconn
      } elseif {[catch $gr err]} {
        variable onerror
        _clilog error $err
        if {$onerror != ""} {
          uplevel #0 [list $onerror $err]
        }
        _closeconn
      } else {
        variable onget
        variable rx
        set rx [expr [string length $d] + $rx]
        if {$onget != ""} {
          uplevel #0 [list $onget $d]
        }
      }
    }
  }

  ##########
  #
  # proc ::net::_clidisconnect
  #
  proc _clidisconnect {} {
    uplevel 1 {
      variable connected
      if {$connected == 0} {
        return -code error "Not connected"
      } else {
        _closeconn
      }
    }
  }

  ##########
  #
  # proc ::net::_cliconfigure
  #
  proc _cliconfigure {} {
    uplevel 1 {
      variable connected
      if {[llength $args] % 2} {
        return -code error "Uneven set of parameters"
      } else {
        set c {
          -getsread {
            variable getsread
            if {$y in "gets read"} {
              set getsread $y
            } else {
              return -code error "Unrecognized value \"$y\".  Valid values: \"gets read\""
            }
          }
          -cadir - -cafile - -certfile - -keyfile - -cipher - -command - -password - -request - -require - -ssl2 - -ssl3 - -tls1 - -nonewline - -readsize {
            set v [string range $x 1 e]
            variable $v $y
          }
          -onerror - -onclose - -onget - -onconnect - -ontimeout - -onlog - -onsecured - -onunsecured - -async - -onfail - -autoflush - -timeout {
            set v [string range $x 1 e]
            variable $v $y
            if {$connected > 0 && $v == "onget"} {
              if {$onget == ""} {
                fileevent $sock readable {}
              } else {
                variable sock
                fileevent $sock readable "[namespace current]::_get"
              }
            }
          }
          -blocking - -buffering - -buffersize - -eofchar - -translation - -encoding {
            set v [string range $x 1 e]
            variable $v $y
            variable sock
            variable connected
            if {$connected > 0} {
              fconfigure $sock $x $y
            }
          }
          default {
            foreach {a b} [lrange $c 0 end-2] {
              lappend d $a
            }
            return -code error "Unrecognized parameter \"$x\".  Valid parameters: [lsort $d]"
          }
        }
        foreach {x y} $args {
          switch -- $x $c
        }
      }
    }
  }

  ##########
  #
  # proc ::net::_clicget
  #
  proc _clicget {} {
    uplevel 1 {
      switch -- $arg [set c {
        -onerror - -onclose - -onget - -onconnect - -ontimeout - -onlog - -onsecured - -onunsecured - -onfail - 
        -autoflush - -timeout - -getsread - -nonewline {
          set v [string range $arg 1 e]
          variable $v
          return [set $v]
        }
        -blocking - -buffering - -buffersize - -eofchar - -translation - -autoflush - -encoding - -async - 
        -cadir - -cafile - -certfile - -keyfile - -cipher - -command - -password - -request - -require - -ssl2 - -ssl3 - -tls1 {
          set v [string range $arg 1 e]
          variable $v
          return [set $v]
        }
        -peername {
          variable connected
          variable sock
          if {$connected} {
            return [fconfigure $sock -peername]
          }
        }
        pending {
          variable connected
          variable sock
          if {$connected} {
            set input [chan pending input $sock]
            set output [chan pending output $sock]
            return [list $input $output]
          }
        }
        secured {
          variable secured
          return $secured
        }
        connstat {
          variable connected
          return $connected
        }
        lastlog {
          variable log
          return [join [lindex $log e]]
        }
        log {
          variable log
          return $log
        }
        clearlog {
          variable log
          set x $log
          set log [list]
          return $x
        }
        rx - tx - secured {
          variable $arg
          return [set $arg]
        }
        default {
          foreach {x y} [lrange $c 0 end-2] {
            lappend z $x
          }
          return -code error "Unrecognized parameter \"$arg\".  Valid parameters: [lsort $z]"
        }
      }]
    }
  }

  ##########
  #
  # proc ::net::_clicloseconn
  #
  proc _clicloseconn {} {
    uplevel 1 {
      variable connected
      variable server
      variable inprocess
      if {$connected > 0} {
        variable sock
        variable onclose
        variable log
        variable tx
        variable rx
        variable secured 0
        set inprocess 0
        catch {close $sock}
        set connected 0
        _clilog close "$rx $tx"
        if {$onclose != ""} {
          uplevel #0 [list $onclose]
        }
        set rx 0
        set tx 0
      } elseif {$inprocess} {
        variable sock
        set inprocess 0
        catch {close $sock}
      }
      if {$server} {
        destroy
      }
    }
  }

  ##########
  #
  # proc ::net::_clidestroy
  #
  proc _clidestroy {} {
    uplevel 1 {
      variable connected
      if {$connected > 0} {
        return -code error "Still connected, close connection first"
      } else {
        namespace delete [namespace current]
      }
    }
  }

  ##########
  #
  # proc ::net::_clilog
  #
  proc _clilog {} {
    uplevel 1 {
      variable log
      lappend log [list [clock milliseconds] $a $m]
    }
  }

  ##########
  #
  # proc ::net::_clearlog
  #
  proc _clearlog {} {
    uplevel 1 {
      variable log 
      set x $log
      set log [list]
      return $x
    }
  }
}

###
#
# netsrv.tcl
#
###

#*********
#
#
#
namespace eval net {

  ##########
  #
  # proc ::net::server
  #
  proc server {port args} {
    set netid [::net::srv::getid]
    set ns ::net::srv::$netid
    namespace eval $ns {
      variable port
      variable sock
      variable running 0
      # config fconfigure, set to default
      variable blocking    1
      variable buffering   full
      variable buffersize  4096
      variable encoding    utf-8
      variable eofchar     {{} {}}
      variable translation {auto crlf}
      # config ssl, set to default
      variable cadir     ""
      variable cafile    ""
      variable certfile  ""
      variable keyfile   ""
      variable cipher    ""
      variable command   ""
      variable password  ""
      variable request   1
      variable require   0
      variable ssl2      1
      variable ssl3      1
      variable tls1      0
      variable secured   0
      variable autoflush 0
      # Events
      variable onaccept     ""
      variable ondisconnect ""
      variable onlog        ""

      namespace eval cli $::net::incrid
      
      proc configure  {args}         {::net::_srvconfigure}
      proc cget       {arg}          {::net::_srvcget}
      proc disconnect {id}           {::net::_srvdisconnect}
      proc start      {}             {::net::_srvstart}
      proc stop       {}             {::net::_srvstop}
      proc stopall    {}             {::net::_stopall}
      proc _srvaccept {chan ip port} {::net::_srvaccept}

      namespace ensemble create
      namespace export configure cget start stop stopall
    }
    set ${ns}::port $port
    # Falta $args (fconfigure)
    return $ns
  }

  ##########
  #
  # proc ::net::_srvaccept
  #
  proc _srvaccept {} {
    uplevel 1 {
      variable secured
      set netid [cli::getid]
      set ns [namespace current]::cli::$netid
      namespace eval $ns {variable server 1}
      namespace eval $ns $::net::clientprofile
      set ${ns}::ip   $ip
      set ${ns}::port $port
      set ${ns}::sock $chan
      set ${ns}::connected [clock milliseconds]

      foreach x {cadir cafile certfile keyfile cipher command password request require ssl2 ssl3 tls1 blocking buffering buffersize eofchar translation encoding autoflush} {
        variable $x
        if {[set $x] != ""} {
          $ns configure -$x [set $x]
        }
      }

      variable onaccept
      if {$onaccept != ""} {
        uplevel #0 [list $onaccept $ns]
      }

      if {$secured} {
        fconfigure $chan -blocking 0
        fileevent $chan readable ${ns}::_handshake                
      }
      # Falta $args (fconfigure)
    }
  }

  ##########
  #
  # proc ::net::_srvconfigure
  #
  proc _srvconfigure {} {
    uplevel 1 {
      variable connected
      if {[llength $args] % 2} {
        return -code error "Uneven set of parameters"
      } else {
        foreach {x y} $args {
          switch -- $x {
            -cadir - -cafile - -certfile - -keyfile - -cipher - -command - -password - -request - -require - -ssl2 - -ssl3 - -tls1 {
              set v [string range $x 1 e]
              variable $v $y
            }
            -onaccept {
              set v [string range $x 1 e]
              variable $v $y
            }
            -blocking - -buffering - -buffersize - -eofchar - -translation - -autoflush - -encoding {
              set v [string range $x 1 e]
              variable $v $y
              variable sock
              variable connected
              if {$connected} {
                fconfigure $sock $x $y
              }
            }
            default {
              return -code error "Unrecognized parameter \"$x\".  Valid parameters: [lsort "-onaccept -buffering -blocking -buffersize -eofchar -translation -encoding"]"
            }
          }
        }
      }
    }
  }

  ##########
  #
  # proc ::net::_srvcget
  #
  proc _srvcget {} {
    uplevel 1 {
      switch $arg {
        -cadir - -cafile - -certfile - -keyfile - -cipher - -command - -password - -request - -require - -ssl2 - -ssl3 - -tls1 {
          set v [string range $x 1 e]
          variable $v
          return [set $v]
        }
        -blocking - -buffering - -buffersize - -eofchar - -translation - -autoflush - -encoding {
          set v [string range $x 1 e]
          variable $v
          return [set $x]
        }
        -connections {
          return [namespace children cli]
        }
        isrunning {
          variable running
          return $running
        }
      }
    }
  }

  ##########
  #
  # proc ::net::_srvstart
  #
  proc _srvstart {} {
    uplevel 1 {
      variable sock
      variable running
      if {!$running} {
        variable port
        variable secured
        if {$secured} {
        } else {
          set sock [socket -server [namespace current]::_srvaccept $port]
          set running 1
          foreach x {blocking buffering buffersize eofchar translation encoding} {
            variable $x
            if {[set $x] != ""} {
              fconfigure $sock -$x [set $x]
            }
          }
        }
      } else {
        return -code error "Already started"
      }
    }
  }

  ##########
  #
  # proc ::net::_srvstop
  #
  proc _srvstop {} {
    uplevel 1 {
      variable sock
      variable running
      if {$running} {
        set running 0
        catch {close $sock}
      } else {
        return -code error "Already stoped"
      }
    }
  }

  ##########
  #
  # proc ::net::_srvstopall
  #
  proc _srvstopall {} {
    uplevel 1 {
    }
  }
}
