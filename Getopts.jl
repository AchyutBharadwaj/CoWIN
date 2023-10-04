module Getopts

export getopts

done(instr, idx) = iterate(instr, idx)===nothing

"""
```
function skipcwhile(instr, startidx=1, mchars=" \\t")
```
Consume and skip characters **WHILE** they match characters specified in
mchars. Return index of first character following consumed characters
in string.
"""
function skipcwhile(instr, startidx=1, mchars=" \t")
  idx = startidx
  while !done(instr, idx) && instr[idx] in mchars
    idx = iterate(instr, idx)[2]
  end
  idx
end

"""
```
function getcuntil(instr, startidx=1, mchars=" \\t")
```
Consume and return characters in input string **UNTIL** a character
specified in mchars (match characters) occurs. Also return index
of first character following consumed characters in string.
"""
function getcuntil(instr, startidx=1, mchars=" \t")
  idx = startidx
  outstr = ""
  while !done(instr, idx) && !(instr[idx] in mchars)
    outstr = string(outstr, instr[idx])
    idx = iterate(instr, idx)[2]
  end
  outstr, idx
end

"""
```
function getcuntilunless(instr, startidx=1, mchars=" \\t", uchars="-")
```
Consume and return characters in input string **UNTIL** a character
specified in mchars (match characters) occurs, **UNLESS** the input string
starts with a character specified in uchars. Also return index
of first character following consumed characters in string.
"""
function getcuntilunless(instr, startidx=1, mchars=" \t", uchars="-")
  idx = skipcwhile(instr, startidx, mchars)
  outstr, idx = done(instr, idx) || (instr[idx] in uchars) ? ("", idx) : getcuntil(instr, idx, " \t")
end

getopt = getcuntil
getarg = getcuntilunless

function getopts(instr::String)
  opts = Dict{String,Array{String,1}}()
  argv = Array{String,1}()
  idx = 1
  while !done(instr, idx)
    while true
      arg, idx = getarg(instr, idx, " \t", "-")
      arg != "" && push!(argv, arg)
      (arg == "" || done(instr, idx)) && break
    end
    if !done(instr, idx)
      key, idx = getopt(instr, idx, " \t")
      !(key in keys(opts)) && (opts[key] = Array{String,1}())
      val, idx = getarg(instr, idx, " \t", "-")
      push!(opts[key], val)
    end
  end
  opts, argv
end

function getopts(inarray::Array{S,1}) where S<:String
  getopts(foldl(string,map(x->string(" ",x),inarray)))
end

end
