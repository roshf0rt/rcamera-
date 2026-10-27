import lief, struct, sys, json, re
b=lief.parse(sys.argv[1]); out=sys.argv[2]
def rd(va, n):
    try: return bytes(b.get_content_from_virtual_address(va, n))
    except Exception: return b''
def cstr(va):
    d=rd(va,256); e=d.find(b'\0'); return d[:e].decode('utf8','replace') if e>0 else ''
def i32(va): return struct.unpack('<i', rd(va,4))[0]
def rel(field_va):  # relative pointer stored at field_va
    v=i32(field_va); return field_va+v if v else 0
STD={'Sf':'Float','Si':'Int','Sb':'Bool','SS':'String','Sd':'Double','SD':'Dictionary','Sa':'Array','SO':'Object','Su':'UInt','Sc':'Character','SC':'CGFloat'}
def demangle_type(va, depth=0):
    """Light, best-effort reader for a Swift mangled type reference."""
    if depth>6 or not va: return '?'
    d=rd(va,512); i=0; parts=[]
    while i<len(d) and d[i]!=0:
        c=d[i]
        if 1<=c<=0x17:  # symbolic reference: 4-byte rel offset to a descriptor
            tgt=va+i+1+struct.unpack('<i',d[i+1:i+5])[0]
            if c in (0x01,0x02,0x03):  # context descriptor: name lives at +8
                nm=rel(tgt+8)
                parts.append(cstr(nm) if nm else '<ctx>')
            else:
                parts.append('<sym%02x>'%c)
            i+=5; continue
        if c in (0x1f,0x20): parts.append('?'); i+=1; continue
        m=re.match(rb'(\d+)',d[i:i+4])
        if m:
            n=int(m.group(1)); s=d[i+len(m.group(1)):i+len(m.group(1))+n].decode('utf8','replace')
            parts.append(s); i+=len(m.group(1))+n; continue
        two=d[i:i+2].decode('latin1')
        if two in STD: parts.append(STD[two]); i+=2; continue
        if two.startswith('S') and two[1:] in ('g',):
            parts.append('?'); i+=2; continue
        parts.append(chr(c)); i+=1
    return ''.join(parts)[:120]
sec=b.get_section('__swift5_fieldmd'); base=sec.virtual_address; end=base+sec.size
va=base; types=[]
while va+16<=end:
    mt=rel(va); sup=rel(va+4)
    kind,recsz,nf=struct.unpack('<HHI', rd(va+8,8))
    if nf>5000 or recsz not in (12,16,20,24) and recsz==0: break
    fields=[]
    fv=va+16
    for k in range(nf):
        f=fv+k*recsz if recsz else fv
        flags=struct.unpack('<I', rd(f,4))[0]
        tn=rel(f+4); fnm=rel(f+8)
        fields.append({'flags':flags,'name':cstr(fnm) if fnm else '','type':demangle_type(tn) if tn else ''})
    tname=demangle_type(mt) if mt else '?'
    types.append({'va':hex(va),'kind':kind,'type':tname,'fields':fields})
    va=fv+nf*recsz
    if recsz==0: break
json.dump(types,open(out,'w'),ensure_ascii=False,indent=1)
print('descriptors',len(types),'fields',sum(len(t['fields']) for t in types))
