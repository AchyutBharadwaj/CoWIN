module CoWIN

using Dates
using JSON
using GZip
using HTTP

export tohtml, cowin, cowin_filt, rdnotifydb, wrnotifydb, upnotifydb, rmnotifydb, utc2ist, cleanup, purge, getdelay, emf2str

const vavnop = r"^avail(<=?|>=?|==|!=)[0-9]+$" #only matches avail followed by relational operator
const vd1nop = r"^dose1(<=?|>=?|==|!=)[0-9]+$" #only matches dose1 followed by relational operator
const vd2nop = r"^dose2(<=?|>=?|==|!=)[0-9]+$" #only matches dose2 followed by relational operator

const vav = r"^avail((<=?|>=?|==|!=)[0-9]+)?$" #also matches just avail
const vd1 = r"^dose1((<=?|>=?|==|!=)[0-9]+)?$" #also matches just dose1
const vd2 = r"^dose2((<=?|>=?|==|!=)[0-9]+)?$" #also matches just dose2

const vaxfilt=r"^vax-[0-9]{4}-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]\.csv$"
const rpairs = [Pair("/","."), Pair("@",".at."), Pair("<=",".le."), Pair(">=",".ge."), Pair("==",".eq."), Pair("<",".lt."), Pair(">",".gt.")]

function tohtml(header=nothing, title=nothing, text=nothing, rawhtml=nothing, csvvec=nothing, firstrow=nothing, tableid=nothing, DEBUG=0)
  if csvvec !== nothing
    htmlvec = map(csvvec) do x
                string("<tr><td>",replace(x,","=>"</td><td>"),"</td></tr>")
              end
    if firstrow!==nothing
      pushfirst!(htmlvec, string("<tr><th>",replace(firstrow,","=>"</th><th>"),"</th></tr>"))
    end
    pushfirst!(htmlvec,tableid===nothing ? "<table>" : "<table id=\"$tableid\">")
    push!(htmlvec,"</table>")
  else
    htmlvec = Vector{String}()
  end
  if text !== nothing
    pushfirst!(htmlvec, "<p>$text</p>")
  end
  if rawhtml !== nothing
    pushfirst!(htmlvec, rawhtml)
  end
  if title !== nothing
    pushfirst!(htmlvec, "<h2>$title</h2>")
  end
  if header !== nothing
    pushfirst!(htmlvec, "<body>")
    if title !== nothing
      pushfirst!(htmlvec, "<title>$title</title>")
    end
    prepend!(htmlvec, header)
    push!(htmlvec, "</body></html>")
  end
  return join(htmlvec,'\n')
end

function cowin(urlbase, distpins, date, bypin=false, http_headers=nothing, fh=nothing, DEBUG=0)
  outvec = Vector{String}()
  urlfetched = false
  for dp in distpins
    url = bypin ? string(urlbase.bypin, "pincode=$dp&date=$date") : 
                  string(urlbase.bydist, "district_id=$dp&date=$date")
    r = HTTP.Messages.Response()
    try
      if http_headers !== nothing
        r = HTTP.get(url, http_headers)
      else
        r = HTTP.get(url)
      end
      urlfetched = true
    catch ex
      urlfetched = false
      println("Error fetching url: $url")
    end
    if urlfetched
      s = String(r.body)
      j = JSON.parse(s)
      if "centers" in keys(j)
        nc = length(j["centers"])
      else
        nc = 0
        println(s)
        println("Error!: No centers found in received data for district/pin $dp")
      end
      for c = 1 : nc
        jc = j["centers"][c]
        jvf = "vaccine_fees" in keys(jc) ? jc["vaccine_fees"] : Dict()
        csvstr0 = ""
        csvstr0 = "pincode" in keys(jc) ? string(csvstr0,jc["pincode"]) : string(csvstr0,"NA")
        csvstr0 = "district_name" in keys(jc) ? string(csvstr0,",",jc["district_name"]) : string(csvstr0,",NA")
        csvstr0 = "block_name" in keys(jc) ? string(csvstr0,",",jc["block_name"]) : string(csvstr0,",NA")
        csvstr0 = "name" in keys(jc) ? string(csvstr0,",",replace(jc["name"],","=>" ")) : string(csvstr0,",NA")
        csvstr0 = "address" in keys(jc) ? string(csvstr0,",",replace(jc["address"],","=>" ")) : string(csvstr0,",NA")
        csvstr0 = "fee_type" in keys(jc) ? string(csvstr0,",",jc["fee_type"]) : string(csvstr0,",NA")
        if "sessions" in keys(jc)
          ns = length(jc["sessions"])
        else
          ns = 0
          println("Error! No sessions found for center")
        end
        for s = 1 : ns
          js = jc["sessions"][s]
          vax = "vaccine" in keys(js) ? js["vaccine"] : "NA"
          csvstr1 = ""
          csvstr1 = jc["fee_type"]=="Paid" ? string(csvstr1, getvaxfee(jvf, vax)) : string(csvstr1,"0")
          csvstr1 = "date" in keys(js) ? string(csvstr1,",",js["date"]) : string(csvstr1,"NA")
          csvstr1 = "available_capacity_dose1" in keys(js) ? string(csvstr1,",",string(js["available_capacity_dose1"])) : string(csvstr1,",0")
          csvstr1 = "available_capacity_dose2" in keys(js) ? string(csvstr1,",",string(js["available_capacity_dose2"])) : string(csvstr1,",0")
          csvstr1 = "available_capacity" in keys(js) ? string(csvstr1,",",string(js["available_capacity"])) : string(csvstr1,",0")
          csvstr1 = "min_age_limit" in keys(js) ? string(csvstr1,",",string(js["min_age_limit"])) : string(csvstr1,",0")
          csvstr1 = string(csvstr1,",",vax)
          push!(outvec,string(csvstr0, ",", csvstr1))
        end
      end
      if !bypin
        sleep(2)
      end
    end
  end
  if !isempty(outvec)
    sort!(outvec)
    unique!(outvec)
    if fh!==nothing
      print.(fh, join(outvec,'\n'))
    end
  end
  return outvec
end

function getvaxfee(jvf, vax)
  found = false
  idx = 0
  for v = 1 : length(jvf)
    if jvf[v]["vaccine"] == vax
      idx = v
      found = true
      break;
    end
  end
  if found
    return jvf[idx]["fee"]
  else
    return "0"
  end
end

function cowin_filt(indatavec, criteria, codex=false, DEBUG=0)
  DEBUG>=2 && println("criteria = $criteria")
  outdatavec = indatavec
  for crit in split(criteria,'/')
    DEBUG>=2 && println("filt $crit")
    if occursin(r"^[0-9]{6}$", crit)
      outdatavec = filter(x->occursin(r"^[0-9]{6}$",x[1:6])&&parse(Int,x[1:6])==parse(Int,crit), outdatavec)
    elseif length(crit)>=5 && lowercase(crit[1:5]) == "dose1"
      if codex && occursin(vd1nop,filter(!isspace,crit))
        outdatavec = filter(outdatavec) do x
                       dose1 = occursin(r"^[0-9]*$",split(x,',')[end-4]) ? parse(Int,split(x,',')[end-4]) : 0
                       dose1!=0 ? Meta.eval(Meta.parse(string("dose1=$dose1;",crit))) : false
                     end
      else
        outdatavec = filter(x->occursin(r"^[0-9]*$",split(x,',')[end-4]) && parse(Int,split(x,',')[end-4])!=0, outdatavec)
      end
    elseif length(crit)>=5 && lowercase(crit[1:5]) == "dose2"
      if codex && occursin(vd2nop,filter(!isspace,crit))
        outdatavec = filter(outdatavec) do x
                       dose2 = occursin(r"^[0-9]*$",split(x,',')[end-3]) ? parse(Int,split(x,',')[end-3]) : 0
                       dose2!=0 ? Meta.eval(Meta.parse(string("dose2=$dose2;",crit))) : false
                     end
      else
        outdatavec = filter(x->occursin(r"^[0-9]*$",split(x,',')[end-3]) && parse(Int,split(x,',')[end-3])!=0, outdatavec)
      end
    elseif length(crit)>=5 && lowercase(crit[1:5]) == "avail"
      if codex && occursin(vavnop,filter(!isspace,crit))
        outdatavec = filter(outdatavec) do x
                       avail = occursin(r"^[0-9]*$",split(x,',')[end-2]) ? parse(Int,split(x,',')[end-2]) : 0
                       avail!=0 ? Meta.eval(Meta.parse(string("avail=$avail;",crit))) : false
                     end
      else
        outdatavec = filter(x->occursin(r"^[0-9]*$",split(x,',')[end-2]) && parse(Int,split(x,',')[end-2])!=0, outdatavec)
      end
    elseif lowercase(crit) == "covax"
      outdatavec = filter(outdatavec) do x
                     y = split(x,',')[end]
                     length(y)>=5 && y[1:5]=="COVAX"
                   end
    elseif lowercase(crit) == "covsh" || lowercase(crit) == "covis"
      outdatavec = filter(outdatavec) do x
                     y = split(x,',')[end]
                     length(y)>=5 && y[1:5]=="COVIS"
                   end
    elseif lowercase(crit) == "eight" || crit == "18"
      outdatavec = filter(x->occursin(r"^[0-9]*$",split(x,',')[end-1]) && parse(Int,split(x,',')[end-1])==18, outdatavec)
    elseif lowercase(crit) != "all" && lowercase(crit) != "fetch"
      outdatavec = filter(outdatavec) do x
                     r = length(crit)>=4 && crit[1:4]=="(?i)" ? crit : string("(?i)(",crit,")")
                     occursin(Regex(r),x)
                   end
    end
  end
  return outdatavec
end

function rdnotifydb(fname="cowin-notifydb.txt", DEBUG=0)
  ndb = Dict{String,Vector{String}}()
  if fname in readdir()
    for x in readlines(fname)
      y = split(x,'/')
      if length(y)>=2 && !isempty(y[1])
        if y[1] in keys(ndb)
          push!(ndb[y[1]], join(y[2:end],'/'))
        else
          ndb[y[1]] = [join(y[2:end],'/')]
        end
      end
    end
  end
  return ndb
end

function wrnotifydb(ndb, fname="cowin-notifydb.txt", DEBUG=0)
  fh = open(fname, "w")
  for email in keys(ndb)
    for filt in ndb[email]
      write(fh, string(email,'/',filt,'\n'))
    end
  end
  close(fh)
end

function upnotifydb(ndb, email, filts, plus=false, fname="cowin-notifydb.txt", DEBUG=0)
  #RetVal: 0 => nothing, 1 => filt replaced, 2 => email, filt added
  rval = 0
  filtsvec = filter(!isempty, split(filts,'/'))
  if isempty(filter(x->occursin(vav,x), filtsvec)) &&
     isempty(filter(x->occursin(vd1,x), filtsvec)) && isempty(filter(x->occursin(vd2,x), filtsvec)) 
    push!(filtsvec, "avail")
  end
  sort!(filtsvec)
  filts = join(filtsvec,'/')

  if email in keys(ndb)
    if !plus
      ndb[email] = [filts]
      rval = 1
    else
      if !(filts in ndb[email])
        push!(ndb[email], filts)
        rval = 2
      end
    end
  else
    ndb[email] = [filts]
    rval = 2
  end
  if rval != 0
    wrnotifydb(ndb, fname)
  end
  return rval
end

function emf2str(instr)
  outstr = filter(!isspace,instr)
  for r in rpairs
    outstr = replace(outstr, r)
  end
  return outstr
end

function rmnotifydb(ndb, email, fname="cowin-notifydb.txt", DEBUG=0)
  rval = 0
  filts = nothing
  if email in keys(ndb)
    for filtstr in ndb[email]
      emhist = emf2str(string(email,'.',filtstr))
      if emhist in readdir()
        rm(emhist)
      end
    end
    rval = 1
    filts = ndb[email][1]
    delete!(ndb, email)
    wrnotifydb(ndb, fname)
  end
  return rval, filts
end

utc2ist(dt::DateTime, ho=5, mo=30) = dt+Dates.Hour(ho)+Dates.Minute(mo)

function cleanup(archive="vaxdb", retainhrs=3.0, currtime=now(), DEBUG=0)
  files = readdir()
  if !(archive in files) mkdir(archive); end
  files = filter(x->occursin(vaxfilt, x), files)
  for x in files
    if (currtime-utc2ist(unix2datetime(mtime(x)))).value/1000/60/60 > retainhrs
      DEBUG>=2 && println("Moving $x, ct=$currtime, mt=$(utc2ist(unix2datetime(mtime(x)))), rh=$retainhrs")
      fh = GZip.open("$archive/$x.gz","w")
      GZip.write(fh, join(readlines(x),'\n'))
      close(fh)
      rm(x)
    end
  end
end

function purge(archive="vaxdb", retaindays=3.0, currtime=now(), DEBUG=0)
  if archive in readdir()
    for x in filter(x->occursin(vaxfilt, x),readdir(archive))
      if (currtime-utc2ist(unix2datetime(mtime("$archive/$x")))).value/1000/60/60/24 > retaindays
        DEBUG>=2 && println("Purging $x, ct=$currtime, mt=$(utc2ist(unix2datetime(mtime("$archive/$x")))), rd=$retaindays")
        rm("$archive/$x")
      end
    end
  end
end

function getdelay(ctime, refresh, mindelay=30, DEBUG=0)
  delay = 5*60
  for i = 1 : size(refresh)[1]
    if refresh[i,1]<=ctime<=refresh[i,2]
      delay = refresh[i,3]
      enddelay = ctime + Second(delay)
      if enddelay > refresh[i,2]
        delay = Second(refresh[i,2]-ctime).value
      end
      break;
    end
  end
  return max(delay,mindelay)
end

end
