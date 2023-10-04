#!/usr/bin/env julia

push!(LOAD_PATH, pwd())

using CoWIN
using Dates
using Getopts

include("sodists.jl")
dists = unique(sort(collect(values(sodists))))

archive = "vaxdb"
retainhrs = 3.0
purgedays = 3.0
DEBUG = 0
fnamendb = "cowin-notifydb.txt"
skipref = false
codex = true

urlbase = ( bydist = "https://cdn-api.co-vin.in/api/v2/appointment/sessions/public/calendarByDistrict?",
            bypin = "https://cdn-api.co-vin.in/api/v2/appointment/sessions/public/calendarByPin?"
          )

myurl = "http://cowin.sytes.net:9000"

if length(ARGS)>0
  opts, argv = getopts(ARGS)
  println("opts = $opts")
  println("argv = $argv")

  if "-debug" in keys(opts)
    if !isempty(opts["-debug"][1])
      DEBUG = parse(Int,opts["-debug"][1])
    else
      DEBUG = 1
    end
  end
  if "-archive" in keys(opts)
    archive = opts["-archive"][1]
  end
  if "-retain" in keys(opts)
    retainhrs = parse(Float64,opts["-retain"][1])
  end
  if "-purge" in keys(opts)
    purgedays = parse(Float64,opts["-purge"][1])
  end
  if "-notifydb" in keys(opts)
    fnamendb = opts["-notifydb"][1]
  end
  if "-skipref" in keys(opts)
    skipref = true
  end
  if "-nocodex" in keys(opts)
    codex = false
  end
end

http_headers = Dict(#"User-Agent"=>"Mozilla/5.0 (X11; Linux x86_64; rv:90.0) Gecko/20100101 Firefox/90.0",
                    "user-agent"=>"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.77 Safari/537.36",
                    "accept"=>"application/json, text/plain, */*",
                    "accept-language"=>"en-US,en;q=0.9",
                    "accept-encoding"=>"gzip, deflate, br",
                    "origin"=>"https://www.cowin.gov.in",
                    "referer"=>"https://www.cowin.gov.in/")

while true
  updtime = split(string(now()),'.')[1]
  DEBUG>=1 && println("$updtime: Refreshing CoWIN database")
  tday = Date(split(updtime,'T')[1])
  date = Dates.format(tday,"dd-mm-yyyy")
  vaxfilt=r"^vax-[0-9]{4}-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]\.csv$"

  if !skipref
    fnamevax = string("vax-",updtime,".csv.tmp")
    fh = open(fnamevax, "w")
    cowin(urlbase, dists, date, false, http_headers, [fh], DEBUG)
    close(fh)
    ffnamevax = splitext(fnamevax)[1]
    mv(fnamevax, ffnamevax)
  else
    vaxfiles = filter(x->occursin(vaxfilt,x),readdir())
    ffnamevax = vaxfiles[sortperm(mtime.(vaxfiles))][end]
    DEBUG>=2 && println("Skip refresh: lastvax = $ffnamevax")
  end

  notifydb = rdnotifydb(fnamendb)
  for email in keys(notifydb)
    for filtstr in notifydb[email]
      DEBUG>=2 && println("Processing notification: $email/$filtstr")
      outdatavec = cowin_filt(readlines(ffnamevax), filtstr, codex, DEBUG)
      if !isempty(outdatavec)
        sendmail = true
        outcenters = unique(sort(map(outdatavec) do x
          split(x,',')[4]
        end))
        emhist = emf2str(string(email,'.',filtstr))
        if (emhist in readdir()) && (DateTime(updtime)-utc2ist(unix2datetime(mtime(emhist)))).value/1000/60/60 < 1
          DEBUG>=2 && println("prev $emhist exists")
          lastcenters = readlines(emhist)
          sendmail = !isempty(setdiff(outcenters,lastcenters))
        else
          sendmail = true
        end

        if sendmail
          DEBUG>=1 && println("$updtime: Sending notification: $email/$filtstr")
          title = "CoWIN Vaccination Center Availability Alert!"
          firstrow = "PinCode,District,Block,CenterName,Address,Free/Paid,Cost,Date,Dose1,Dose2,Av.Tot,Min.Age,Vaccine\n"
          text = "Centers available by your filter: <a href=\"$myurl/fetch/$filtstr\">$myurl/fetch/$filtstr</a><br>Unsubscribe: <a href=\"$myurl/denotify/$email/\">$myurl/denotify/$email/</a><br>Help: <a href=\"$myurl\">$myurl</a>"
          htmlout = tohtml(readlines("cowin-header.html"), title, text, nothing, outdatavec, firstrow, "t01", DEBUG)

          from = "From: CoWIN Notifier <vax.notifier@gmail.com>"
          to = "To: $email"
          subject = "Subject: $title"
          ctype = "Content-Type: text/html"

          mailout = join([from,to,subject,ctype,htmlout],'\n')

          mailcmd = `sendmail -t`
          open(mailcmd, "w") do fh
            print(fh, mailout)
          end
          open(emhist, "w") do fh
            print(fh, join(outcenters,'\n'))
          end
        end
      end
    end
  end

  if !skipref
    cleanup(archive, retainhrs, DateTime(updtime), DEBUG)
    purge(archive, purgedays, DateTime(updtime), DEBUG)
  end

  DEBUG>=2 && println("Done!")
  refresh = [ DateTime(string(tday,"T00:00:00")) DateTime(string(tday,"T00:59:59")) 60*60
              DateTime(string(tday,"T01:00:00")) DateTime(string(tday,"T01:59:59")) 60*60
              DateTime(string(tday,"T02:00:00")) DateTime(string(tday,"T02:59:59")) 60*60
              DateTime(string(tday,"T03:00:00")) DateTime(string(tday,"T03:59:59")) 60*60
              DateTime(string(tday,"T04:00:00")) DateTime(string(tday,"T04:59:59")) 60*60
              DateTime(string(tday,"T05:00:00")) DateTime(string(tday,"T05:59:59")) 60*60
              DateTime(string(tday,"T06:00:00")) DateTime(string(tday,"T06:59:59")) 60*60
              DateTime(string(tday,"T07:00:00")) DateTime(string(tday,"T07:59:59")) 60*60
              DateTime(string(tday,"T08:00:00")) DateTime(string(tday,"T08:59:59")) 60*60
              DateTime(string(tday,"T09:00:00")) DateTime(string(tday,"T09:59:59")) 60*60
              DateTime(string(tday,"T10:00:00")) DateTime(string(tday,"T10:59:59")) 60*60
              DateTime(string(tday,"T11:00:00")) DateTime(string(tday,"T11:59:59")) 60*60
              DateTime(string(tday,"T12:00:00")) DateTime(string(tday,"T12:59:59")) 60*60
              DateTime(string(tday,"T13:00:00")) DateTime(string(tday,"T13:59:59")) 60*60
              DateTime(string(tday,"T14:00:00")) DateTime(string(tday,"T14:59:59")) 60*60
              DateTime(string(tday,"T15:00:00")) DateTime(string(tday,"T15:59:59")) 60*60
              DateTime(string(tday,"T16:00:00")) DateTime(string(tday,"T16:59:59")) 60*60
              DateTime(string(tday,"T17:00:00")) DateTime(string(tday,"T17:59:59")) 60*60
              DateTime(string(tday,"T18:00:00")) DateTime(string(tday,"T18:59:59")) 60*60
              DateTime(string(tday,"T19:00:00")) DateTime(string(tday,"T19:59:59")) 60*60
              DateTime(string(tday,"T20:00:00")) DateTime(string(tday,"T20:59:59")) 60*60
              DateTime(string(tday,"T21:00:00")) DateTime(string(tday,"T21:59:59")) 60*60
              DateTime(string(tday,"T22:00:00")) DateTime(string(tday,"T22:59:59")) 60*60
              DateTime(string(tday,"T23:00:00")) DateTime(string(tday,"T23:59:59")) 60*60 ]
  slptime = getdelay(DateTime(updtime), refresh, 30, DEBUG)
  DEBUG>=1 && println("$updtime: Refresh sleep: waking in $slptime seconds.")
  sleep(slptime)
end
