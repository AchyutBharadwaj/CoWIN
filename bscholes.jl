#! /usr/bin/env julia

module bscholes

using Dates
using SpecialFunctions

#Some common functions
ncdf(x) = 0.5*erfc(-x/sqrt(2))
ncdfinv(x) = -sqrt(2)*erfcinv(2x)
npdf(x) = 1/sqrt(2*pi)*exp(-(x^2)/2)

#S=stock price, n = number of SDs, mu = mean, s = sd, dt = dt, de = expiry price resolution
#spread(S,n,mu,s,dt,de) = floor(S*(1+mu*dt)*(1-n*s*sqrt(dt))/de)*de, ceil(S*(1+mu*dt)*(1+n*s*sqrt(dt))/de)*de
pnsd(n) = erf(n/sqrt(2))

#Black-Scholes
d1(S,E,dt,s,r,D) = (log(S/E)+(r-D+0.5*s^2)dt)/(s*sqrt(dt))
d2(S,E,dt,s,r,D) = d1(S,E,dt,s,r,D) - s*sqrt(dt)
#Call and put values
cval(S,E,dt,s,r,D) = S*exp(-D*dt)*ncdf(d1(S,E,dt,s,r,D)) - E*exp(-r*dt)*ncdf(d2(S,E,dt,s,r,D))
pval(S,E,dt,s,r,D) = -S*exp(-D*dt)*ncdf(-d1(S,E,dt,s,r,D)) + E*exp(-r*dt)*ncdf(-d2(S,E,dt,s,r,D))
#Delta
dcall(S,E,dt,s,r,D) = exp(-D*dt)*ncdf(d1(S,E,dt,s,r,D))
dput(S,E,dt,s,r,D) = exp(-D*dt)*(ncdf(d1(S,E,dt,s,r,D))-1)
#Gamma
gcall(S,E,dt,s,r,D) = exp(-D*dt)*npdf(d1(S,E,dt,s,r,D))/(s*S*sqrt(dt))
gput(S,E,dt,s,r,D) = gcall(S,E,dt,s,r,D)
#Theta
tcall(S,E,dt,s,r,D) = -s*S*exp(-D*dt)*npdf(d1(S,E,dt,s,r,D))/(2*sqrt(dt)) + D*S*ncdf(d1(S,E,dt,s,r,D))*exp(-D*dt) - r*E*exp(-r*dt)*ncdf(d2(S,E,dt,s,r,D))
tput(S,E,dt,s,r,D) = -s*S*exp(-D*dt)*npdf(-d1(S,E,dt,s,r,D))/(2*sqrt(dt)) - D*S*ncdf(-d1(S,E,dt,s,r,D))*exp(-D*dt) + r*E*exp(-r*dt)*ncdf(-d2(S,E,dt,s,r,D))
#Speed
scall(S,E,dt,s,r,D) = -exp(-D*dt)*npdf(d1(S,E,dt,s,r,D))/((s^2)*(S^2)*dt)*(d1(S,E,dt,s,r,D)+s*sqrt(dt))
sput(S,E,dt,s,r,D) = scall(S,E,dt,s,r,D)
#Vega
vcall(S,E,dt,s,r,D) = S*sqrt(dt)*exp(-D*dt)*npdf(d1(S,E,dt,s,r,D))
vput(S,E,dt,s,r,D) = vcall(S,E,dt,s,r,D)
#Rho
rcall(S,E,dt,s,r,D) = E*dt*exp(-r*dt)*ncdf(d2(S,E,dt,s,r,D))
rput(S,E,dt,s,r,D) = -E*dt*exp(-r*dt)*ncdf(-d2(S,E,dt,s,r,D))

#Prob. of S above/below E
d1p(S,E,dt,s,mu,D) = (log(S/E)+(mu-0.5s^2)dt)/(s*sqrt(dt))
pBelow(S,E,dt,s,mu,D) = 1-ncdf(d1p(S,E,dt,s,mu,D))
pAbove(S,E,dt,s,mu,D) = ncdf(d1p(S,E,dt,s,mu,D))
pBeyond(S,E,dt,s,mu,D) = E>S ? pAbove(S,E,dt,s,mu,D) : pBelow(S,E,dt,s,mu,D)

function EBeyond(S,E,dt,s,mu,D,dE,pT=1e-6)
  eVal = 0
  inc = E>S ? 1 : -1
  n = 1
  pLoss = pBeyond(S,E,dt,s,mu,D)
  while pLoss>pT
    pLossFar = pBeyond(S,E+inc*n*dE,dt,s,mu,D)
    eVal += (pLoss - pLossFar)*(E+inc*n*dE/2)
    n += 1
    pLoss = pLossFar
  end
  return eVal/pBeyond(S,E,dt,s,mu,D)
end

function spLB(p,S,dt,s,mu,D,eps=1e-6)
  E = S
  dE = eps + 1
  while(abs(dE)>eps)
    perr = pBelow(S,E,dt,s,mu,D) - p
    dpbydE = (1/E)*npdf(d1p(S,E,dt,s,mu,D))/(s*sqrt(dt))
    dpbydE = sign(dpbydE)*maximum([abs(dpbydE) 0.01])
    dE = perr/dpbydE
    E = E - dE
  end
  return E
end

function spUB(p,S,dt,s,mu,D,eps=1e-6)
  E = S*(1+mu*dt)
  dE = eps + 1
  while(abs(dE)>eps)
    perr = pAbove(S,E,dt,s,mu,D) - p
    dpbydE = -(1/E)*npdf(d1p(S,E,dt,s,mu,D))/(s*sqrt(dt))
    dpbydE = sign(dpbydE)*maximum([abs(dpbydE) 0.01])
    dE = perr/dpbydE
    E = E - dE
  end
  return E
end

spread(p,S,dt,s,mu,D,dE,eps=1e-6) = floor(spLB(p,S,dt,s,mu,D,eps)/dE)*dE, ceil(spUB(p,S,dt,s,mu,D,eps)/dE)*dE

#Implied volatility from call value
function ivcall(V,S,E,dt,r,D,eps=1e-6)
  s = 0.2
  ds = eps + 1
  while(abs(ds)>eps)
    perr = cval(S,E,dt,s,r,D) - V
    #print("ivcall: $E, $S, $s, $ds, $V, $perr\n")
    vega = vcall(S,E,dt,s,r,D)
    ds = perr/vega
    #ds = sign(ds)*minimum([0.1*s abs(ds)])
    ds = sign(ds)*minimum([0.1*abs(s) abs(ds)])
    s = s - ds
  end
  return s
end

#Implied volatility from put value
function ivput(V,S,E,dt,r,D,eps=1e-6)
  s = 0.2
  ds = eps + 1
  while(abs(ds)>eps)
    perr = pval(S,E,dt,s,r,D) - V
    #print("ivput: $E, $S, $s, $ds, $V, $perr\n")
    vega = vput(S,E,dt,s,r,D)
    ds = perr/vega
    #ds = sign(ds)*minimum([0.1*s abs(ds)])
    ds = sign(ds)*minimum([0.1*abs(s) abs(ds)])
    s = s - ds
  end
  return s
end

#Compute yield with sampling interval n
yield(data,n=1) = [(data[i+n]-data[i])/data[i] for i in 1:length(data)-n]

#Compute mu, sigma with sampling interval n, scaled with scale
musig(data,n,scale=1.0) = (y=yield(data,n); (mean(y)*scale,std(y)*sqrt(scale)))

mav(data,n) = (m=[mean(data[i-n:i]) for i in [n+1:length(data)]]; [ones(n)*m[1]; m])

sav(data,n) = (m=[std(data[i-n:i]) for i in [n+1:length(data)]]; [ones(n)*m[1]; m])

musigav(data,n,scale=1.0) = (y=yield(data,1); [mav(y,n)*scale sav(y,n)*sqrt(scale)])

function garch(data, lambda=0.94, sbar=0.025, alpha=0)
  v = zeros(length(data),1)
  v[1] = alpha*sbar^2
  y = yield(data,1)
  for i = 2 : length(data)
    v[i]=alpha*sbar^2 + (1-alpha)*(lambda*v[i-1]+(1-lambda)*y[i-1]^2)
  end
  return sqrt.(v[2:end])
end

function rogers(data, N)
  v = zeros(size(data,1))
  for i = 2 : size(data,1)
    for j = maximum([2 i-N+1]) : i
      v[i] += log(data[j,3]/data[j,6])*log(data[j,3]/data[j,2])+log(data[j,4]/data[j,6])*log(data[j,4]/data[j,2])
    end
    v[i] /= (i-1)
  end
  return sqrt(v[2:end])
end

function rls(data,x,L=21,eps=0.1)
  y = yield(data,1)
  v = zeros(length(y))
  w = zeros(L)
  P = 1/eps*eye(L)
  for i = 1 : length(y)
    yk = i>=L ? y[i-L+1:i].^2 : [zeros(L-i);y[1:i]].^2
    v[i] = (w'*yk)[1]

    D = 1 + yk'*P*yk
    g = (1/D[1])*P*yk
    w = w + g*(x[i]-(yk'*w)[1])
  end
  #i = length(y)
  #yk = i>=L ? y[i-L+1:i].^2 : [zeros(L-i);y[1:i]].^2
  #v[i] = (w'*yk)[1]
  println("weights = ", w)
  return(sqrt(v))
end

function rlsUpdate(y_k, w_k_1, u_k, R_k_1_inv, lambda=0.94, cterm=true)
  #print("rlsUpdate: y_k=$y_k, w_k_1=$w_k_1, u_k=$u_k, R_k_1_inv=$R_k_1_inv, lambda=$lambda, cterm=$cterm\n")
  l = (1-lambda)/lambda
  pi_k = R_k_1_inv*u_k
  g_k = l*pi_k/(1+l*(u_k'*pi_k)[1])
  R_k_inv = 1/lambda * R_k_1_inv - 1/lambda * g_k * u_k' * R_k_1_inv
  w_k = w_k_1 + g_k * (y_k - (u_k'*w_k_1)[1])
  Y_k = cterm ? [1.0; y_k; u_k[2:end-1]] : [y_k; u_k[1:end-1]]
  return w_k, Y_k, R_k_inv
end

function rlsUpdate2(y_k, w_k_1, u_k, R_k_1_inv, lambda=0.94, cterm=true)
  pi_k = R_k_1_inv*u_k
  g_k = pi_k/(lambda+(u_k'*pi_k)[1])
  R_k_inv = 1/lambda * R_k_1_inv - 1/lambda * g_k * u_k' * R_k_1_inv
  w_k = w_k_1 + g_k * (y_k - (u_k'*w_k_1)[1])
  Y_k = cterm ? [1.0; y_k; u_k[2:end-1]] : [y_k; u_k[1:end-1]]
  return w_k, Y_k, R_k_inv
end

function klmnUpdate(y_k, x_k_cap, R_k_km1, C_k, F_k_kp1, Qx_k, Qy_k)
  G_k = F_k_kp1*R_k_km1*C_k'*inv(C_k*R_k_km1*C_k'+Qy_k)
  alpha_k = y_k - C_k*x_k_cap
  x_kp1_cap = F_k_kp1*x_k_cap + G_k*alpha_k
  R_k = R_k_km1 - F_k_kp1*G_k*C_k*R_k_km1
  print("y_k = $y_k, x_k_cap = $x_k_cap, alpha = $alpha_k, F = $F_k_kp1, G = $G_k, R = $R_k, Qx = $Qx_k\n")
  print("$(typeof(F_k_kp1)), $(typeof(R_k)), $(typeof(Qx_k))\n")
  R_kp1_k = F_k_kp1*R_k*F_k_kp1' + Qx_k 
  return x_kp1_cap, R_kp1_k
end

####################################################################################
# Date and time functions
####################################################################################

utc2ist(dt::DateTime, ho=5, mo=30) = dt+Dates.Hour(ho)+Dates.Minute(mo)

utc2ist(dtstr::AbstractString, ho=5, mo=30) = dtstr2dttm(dtstr)+Dates.Hour(ho)+Dates.Minute(mo)

tsec2dt(tsec, ho=5, mo=30) = utc2ist(Dates.unix2datetime(tsec), ho, mo)

tsec2dtstr(tsec, ho=5, mo=30) = dt2dtstr(tsec2dt(tsec, ho, mo))

tms2dt(tms, ho=5, mo=30) = tsec2dt(tms/1000, ho, mo)

tms2dtstr(tms) = dt2dtstr(tms2dt(tms))

dtstr2dt(dtstr) = occursin("-",dtstr) ? (length(dtstr)>7 ? Date(dtstr[1:10]) :
                                                           Date(string(dtstr[1:7],"-01"))) :
                                        (length(dtstr)>6 ? Date(string(dtstr[1:4],"-",dtstr[5:6],"-",dtstr[7:8])) :
                                                           Date(string(dtstr[1:4],"-",dtstr[5:6],"-01")))

dtstr2dttm(dtstr) = DateTime(parse(Int,dtstr[1:4]),parse(Int,dtstr[5:6]),parse(Int,dtstr[7:8]),parse(Int,dtstr[10:11]),parse(Int,dtstr[13:14]),parse(Int,dtstr[16:17]),0)

dt2dtstr(dt::Union{DateTime,Date}; dsep="", tsep=":", dtsep="T") = (s=string(dt); length(s)>=19 ? "$(s[1:4])$dsep$(s[6:7])$dsep$(s[9:10])$dtsep$(s[12:13])$tsep$(s[15:16])$tsep$(s[18:19])" : "$(s[1:4])$dsep$(s[6:7])$dsep$(s[9:10])")

dtstr2dtsql(dtstr) = length(dtstr)>8 ? "$(dtstr[1:4])-$(dtstr[5:6])-$(dtstr[7:8]) $(dtstr[10:17])" : "$(dtstr[1:4])-$(dtstr[5:6])-$(dtstr[7:8])"

dt2dtsql(dt) = (s=string(dt); string(s[1:4],"-",s[6:7],"-",s[9:10]))

dtsql2dtstr(dtsql) = length(dtsql)>10 ? "$(dtsql[1:4])$(dtsql[6:7])$(dtsql[9:10]) $(dtsql[12:19])" : "$(dtsql[1:4])$(dtsql[6:7])$(dtsql[9:10])"

ist() = now()

tday() = Date(ist())

function tsec2hrs(tsec) 
  dt = tsec2dt(tsec)
  return float(dt-DateTime(Date(dt)))/1000/60/60
end

tdaytime(tnow=ist(), HMS="00:00:00") = DateTime(Dates.year(tnow),Dates.month(tnow),Dates.day(tnow),parse(Int,HMS[1:2]),parse(Int,HMS[4:5]),parse(Int,HMS[7:8]),0)

function nextXday(dt::Union{DateTime,Date}, xday, offset=0)
  idn = Dates.dayofweek(dt+Day(offset))
  return dt2dtstr(dt + Day(offset) + ((xday-idn)>=0 ? Dates.Day(xday-idn) : Dates.Day(xday-idn+7)))
end

nextXday(dtstr::AbstractString, xday, offset=0) = nextXday(dtstr2dt(dtstr), xday, offset)

nextThursday(dt::Union{DateTime,Date}, offset=0) = nextXday(dt, Dates.Thursday, offset)
nextThursday(dtstr::AbstractString, offset=0) = nextXday(dtstr, Dates.Thursday, offset)

function lastXdayOfMnth(dt::Union{DateTime,Date}, xday, plusMonths=0)
  dtstrplus = Dates.firstdayofmonth(dt)+Dates.Month(plusMonths)
  ldate = Dates.lastdayofmonth(dtstrplus)
  lday = Dates.dayofweek(ldate)
  lth = (lday>=xday) ? ldate-Dates.Day(lday-xday) : ldate-Dates.Day(7-(xday-lday))
  return dt2dtstr(lth)
end

lastXdayOfMnth(dtstr::AbstractString, xday, plusMonths=0) = lastXdayOfMnth(dtstr2dt(dtstr), xday, plusMonths)

lastThursday(dt::Union{DateTime,Date}, plusMonths=0) = lastXdayOfMnth(dt, Dates.Thursday, plusMonths)
lastThursday(dtstr::AbstractString, plusMonths=0) = lastXdayOfMnth(dtstr, Dates.Thursday, plusMonths)

function getExpiryDate(dt::Union{DateTime,Date}, plusMonths=0, holidays=[], holexcept=[])
  expDate = dtstr2dt(lastThursday(dt))
  expDate = (expDate >= dt) ? dtstr2dt(lastThursday(dt,plusMonths)) : dtstr2dt(lastThursday(dt,plusMonths+1))
  while isholiday(expDate, holidays, holexcept)
    expDate -= Dates.Day(1)
  end
  return dt2dtstr(expDate)
end

getExpiryDate(dtstr::AbstractString, plusMonths=0, holidays=[], holexcept=[]) = getExpiryDate(dtstr2dt(dt), plusMonths, holidays, holexcept)

function bizDays(fdt::Date, tdt::Date, holidays=[], holexcept=[])
  dbw = round(Int, floor(float(Dates.value(tdt-fdt))/7)*5 + (Dates.dayofweek(tdt)>=Dates.dayofweek(fdt) ? (Dates.dayofweek(tdt)>5 ? 5 : Dates.dayofweek(tdt))-Dates.dayofweek(fdt) : (5-(Dates.dayofweek(fdt)>5 ? 5 : Dates.dayofweek(fdt)))+Dates.dayofweek(tdt)))
  dbw -= length(findall(h->(fdt < dtstr2dt(h) <= tdt), holidays))
  dbw += length(findall(h->(fdt < dtstr2dt(h) <= tdt), holexcept))
  #for h in holidays
  #  dbw = (fdt < dtstr2dt(h) <= tdt) ? dbw-1 : dbw
  #end
  return dbw
end

bizDays(frmDate::AbstractString, toDate::AbstractString, holidays=[], holexcept=[]) = bizDays(dtstr2dt(frmDate), dtstr2dt(toDate), holidays, holexcept)

time2hrs(timestr::AbstractString) = parse(Int,timestr[1:2])+parse(Int,timestr[4:5])/60+parse(Int,timestr[7:8])/(60*60)

time2hrs(dttm::DateTime) = time2hrs(dt2dtstr(dttm)[10:end])

function bizHours(frmDttm::DateTime, toDttm::DateTime, holidays=[], holexcept=[], dayStart="09:15:00", dayEnd="15:30:00")
  hrsPerDay = time2hrs(dayEnd)-time2hrs(dayStart)
  frmDttm = time2hrs(frmDttm)<time2hrs(dayStart) ? trunc(frmDttm, Dates.Day)+Dates.Hour(parse(Int,dayStart[1:2]))+Dates.Minute(parse(Int,dayStart[4:5]))+Dates.Second(parse(Int,dayStart[7:8])) : frmDttm
  toDttm = time2hrs(toDttm)>time2hrs(dayEnd) ? trunc(toDttm, Dates.Day)+Dates.Hour(parse(Int,dayEnd[1:2]))+Dates.Minute(parse(Int,dayEnd[4:5]))+Dates.Second(parse(Int,dayEnd[7:8])) : toDttm
  dbw = bizDays(Date(frmDttm), Date(toDttm), holidays, holexcept)
  hrsLast = time2hrs(toDttm)-time2hrs(dayStart)
  hrsLast = hrsLast<=0 || isholiday(toDttm,holidays,holexcept) ? 0 : hrsLast
  hrsFirst = time2hrs(dayEnd)-time2hrs(frmDttm)
  hrsFirst = hrsFirst<=0 || isholiday(frmDttm,holidays,holexcept) ? 0 : hrsFirst
  bizHrs = dbw>=1 ? hrsPerDay*(dbw-1) + hrsFirst + hrsLast : 
           dbw>=0 && hrsFirst+hrsLast>hrsPerDay ? hrsFirst + hrsLast - hrsPerDay : 0
  return bizHrs
end

bizHours(frmDttm::AbstractString, toDttm::AbstractString, holidays=[], holexcept=[], dayStart="09:15:00", dayEnd="15:30:00") = bizHours(dtstr2dttm(frmDttm), dtstr2dttm(toDttm), holidays, holexcept, dayStart, dayEnd)

function bizDaysToExpiry(dt::Union{DateTime,Date}, plusMonths=0, holidays=[], holexcept=[])
  expDate = dtstr2dt(getExpiryDate(dt, plusMonths, holidays, holexcept))
  d2e = bizDays(dt, expDate, holidays, holexcept)
  return d2e
end

bizDaysToExpiry(dtstr::AbstractString, plusMonths=0, holidays=[], holexcept=[]) = bizDaysToExpiry(dtstr2dt(dtstr), plusMonths, holidays, holexcept)

isholiday(dt::Union{DateTime,Date}, dtstr::AbstractString, holidays=[], holexcept=[]) = !(((Dates.dayofweek(dt)>=1 && Dates.dayofweek(dt)<=5) || dtstr in holexcept) && !(dtstr in holidays))

function isholiday(dt::Union{DateTime,Date}, holidays=[], holexcept=[])
  dtstr = dt2dtstr(dt)
  isholiday(dt, dtstr, holidays, holexcept)
end

function isholiday(dtstr::AbstractString, holidays=[], holexcept=[])
  dt = dtstr2dt(dtstr)
  isholiday(dt, dtstr, holidays, holexcept)
end

isValidDtStr(x) = try
  dtstr2dt(x)
  true
catch
  false
end

isNotValidDtStr(x) = !isValidDtStr(x)

####################################################################################
# Other utilities
####################################################################################

randint(n,a,b) = n==1 ? (round(Int, rand(n)*(b-a)).+a)[1] : (round(Int,rand(n)*(b-a)).+a)

function lprint(fp=STDOUT, x...)
  fp!=STDOUT && ([write(fp, p) for p in x]; flush(fp))
  print(x...)
end

function lprintf(fp=STDOUT, x...)
  ([write(fp, p) for p in x]; flush(fp))
end

acquire(mutex) = put!(mutex, true)
release(mutex) = take!(mutex)
isavail(mutex) = !isready(mutex)

round2p(x, p=0.05) = round(x/p)*p

end #module
