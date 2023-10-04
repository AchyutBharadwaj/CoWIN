#!/usr/bin/env julia

push!(LOAD_PATH, pwd())

using CoWIN

using Sockets
using HTTP
using Getopts
using Dates

function cowin_fetch(req::HTTP.Request)
  if DEBUG>=1
    println("Call to cowin_fetch")
  end
  baseids = 0  #No base identifiers in path, such as "cowin"
  reqtime = split(string(now()),'.')[1]
  if DEBUG>=1
    println.([lfh, stdout], "$reqtime: Request: $(req.target)")
    flush(lfh)
  else
    println.(lfh, "$reqtime: Request: $(req.target)")
    flush(lfh)
  end
  spath = HTTP.URIs.unescapeuri.(filter(x->length(x)!=0,HTTP.URIs.split(req.target,'/')))
  spath = map(x->filter(!isspace,x), spath)
  DEBUG>=2 && println("spath = $spath")
  if length(spath)>=baseids+1
    if (lowercase(spath[baseids+1]) in keywords || occursin(r"^[0-9]{6}$", spath[baseids+1]))
      cmd = "fetch"
    elseif lowercase(spath[baseids+1]) == "hist"
      cmd = "hist"
    elseif lowercase(spath[baseids+1]) == "notify"
      cmd = "notify"
    elseif lowercase(spath[baseids+1]) == "notify+"
      cmd = "notify+"
    elseif lowercase(spath[baseids+1]) == "denotify"
      cmd = "denotify"
    else
      cmd = "help"
    end
  else
    cmd = "help"
  end
  DEBUG>=2 && println("cmd = $cmd")

  filts = length(spath)>=baseids+1 ? spath[baseids+1:end] : ["all"]
  DEBUG>=2 && println("filts = $filts")

  cowinhead = readlines("cowin-header.html")

  if cmd == "fetch" || cmd == "hist"
    DEBUG>=2 && println(cmd)
    vaxfilt=r"^vax-[0-9]{4}-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]\.csv$"
    vaxfiles = filter(x->occursin(vaxfilt,x),readdir())
    if cmd == "hist"
      if length(spath)>=baseids+2 && occursin(r"^[0-9]+$", spath[baseids+2]) 
        minsago = parse(Int, spath[baseids+2])
        filts = length(spath)>=baseids+3 ? spath[baseids+3:end] : ["all"]
      elseif length(spath)>=baseids+2 && occursin(r"^[0-2]?[0-9]:[0-5][0-9](:[0-5][0-9])?$", spath[baseids+2]) 
        minsago = max(0,Int(round((DateTime(reqtime)-DateTime(string(split(reqtime,'T')[1],'T',spath[baseids+2]))).value/1000/60)))
        filts = length(spath)>=baseids+3 ? spath[baseids+3:end] : ["all"]
      else
        minsago = 0
        filts = length(spath)>=baseids+2 ? spath[baseids+2:end] : ["all"]
      end
      htimes = map(x->Int(round((DateTime(reqtime)-DateTime(x[5:end-4])).value/1000/60)),vaxfiles)
      lastvax = vaxfiles[argmin(abs.(htimes .- minsago))]
    else
      lastvax = vaxfiles[sortperm(mtime.(vaxfiles))][end]
    end
    updtime = lastvax[5:end-4]
    DEBUG>=2 && println("lastvax = $lastvax")
    outdatavec = cowin_filt(readlines(lastvax), join(filts,'/'), codex, DEBUG)
    firstrow = "PinCode,District,Block,CenterName,Address,Free/Paid,Cost,Date,Dose1,Dose2,Av.Tot,Min.Age,Vaccine\n"
    title = "CoWIN Vaccination Centers"
    text = string("Last refreshed at: ",updtime,"<br>Help: <a href=\"$myurl\">$myurl</a>")
    htmlout = tohtml(cowinhead, title, text, nothing, outdatavec, firstrow, "t01", DEBUG)
  elseif cmd == "notify" || cmd == "notify+"
    DEBUG>=2 && println("notify")
    if length(spath)>=baseids+2
      email = spath[baseids+2]
      if occursin(emregex, email)
        filts = length(spath)>=baseids+3 ? spath[baseids+3:end] : ["avail"]
        filtstr = join(filts,'/')
        rval = upnotifydb(notifydb, email, filtstr, cmd=="notify+", fnamendb, DEBUG)
        htmltxt = rval == 0 ? "Email ID: \"$email\" and filters: \"$filtstr\" already registered, no change" :
                  rval == 1 ? "Filters updated for email id: \"$email\". New filters: \"$filtstr\"" :
                              "Email ID \"$email\" and filters: \"$filtstr\" registered"
        htmltxt = string(htmltxt, "<br>Help: <a href=\"$myurl\">$myurl</a>")
        htmlout = tohtml(cowinhead, "CoWIN Notifier", htmltxt)
      else
        htmlout = tohtml(cowinhead, "CoWIN Notifier", "Error: Invalid Email ID<br>Help: <a href=\"$myurl\">$myurl</a>")
      end
    else
      htmlout = tohtml(cowinhead, "CoWIN Notifier", "Error: No email id for notification<br>Help: <a href=\"$myurl\">$myurl</a>")
    end
  elseif cmd == "denotify"
    DEBUG>=2 && println("denotify")
    if length(spath)>=baseids+2
      email = spath[baseids+2]
      if occursin(emregex, email)
        rval, filtstr = rmnotifydb(notifydb, email, fnamendb, DEBUG)
        htmltxt = rval == 1 ? "Email ID: \"$email\" removed from notification database<br>Subscribe again: <a href=\"$myurl/notify/$email/$filtstr\">$myurl/notify/$email/$filtstr</a>" :
                              "Email ID: \"$email\" not registered for notifications"
        htmltxt = string(htmltxt, "<br>Help: <a href=\"$myurl\">$myurl</a>")
        htmlout = tohtml(cowinhead, "CoWIN Notifier", htmltxt) 
      else
        htmlout = tohtml(cowinhead, "CoWIN Notifier", "Error: Invalid Email ID<br>Help: <a href=\"$myurl\">$myurl</a>")
      end
    else
      htmlout = tohtml(cowinhead, "CoWIN Notifier", "Error: No Email ID specified for denotification<br>Help: <a href=\"$myurl\">$myurl</a>")
    end
  else
    htmlout = join(readlines("cowin-help.html"),'\n')
  end

  #print(outdata)
  HTTP.Response(200, htmlout)
end

ipaddr = getipaddr()
port = 9000

DEBUG = 0
fnamendb = "cowin-notifydb.txt"
logfile = "cowin-requests.log"
codex = true

keywords = ["fetch", "all", "covax", "covsh", "covis", "avail", "avd1", "avd2", "dose1", "dose2", "18", "eight"]

emregex = r"""^(([^<>()[\]\\.,;:\s@"]+(\.[^<>()[\]\\.,;:\s@"]+)*)|(".+"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$"""

myurl = "http://cowin.sytes.net:9000"

if length(ARGS)>0
  opts, argv = getopts(ARGS)
  println("opts = $opts")
  println("argv = $argv")

  if "-ip" in keys(opts)
    ipaddr = parse(IPAddr,opts["-ip"][1])
  end
  if "-port" in keys(opts)
    port = parse(Int,opts["-port"][1])
  end
  if "-debug" in keys(opts)
    if !isempty(opts["-debug"][1])
      DEBUG = parse(Int,opts["-debug"][1])
    else
      DEBUG = 1
    end
  end
  if "-notifydb" in keys(opts)
    fnamendb = opts["-notifydb"][1]
  end
  if "-log" in keys(opts)
    logfile = opts["-log"][1]
  end
  if "-nocodex" in keys(opts)
    codex = false
  end
end

lfh = open(logfile, "a")

notifydb = rdnotifydb(fnamendb)

const COWIN = HTTP.Router()
#HTTP.@register(COWIN, "GET", "/", cowin_fetch)
HTTP.Handlers.register!(COWIN, "GET", "/", cowin_fetch)
HTTP.Handlers.register!(COWIN, "GET", "**", cowin_fetch)

println("Serving on $ipaddr:$port...")
HTTP.serve(COWIN, ipaddr, port)
