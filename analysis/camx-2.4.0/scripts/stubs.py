import lief, capstone, struct, json, sys
b=lief.parse(sys.argv[1])
# GOT slot -> symbol from bind info
got={}
for bd in b.bindings:
    try: got[bd.address]=bd.symbol.name
    except Exception: pass
print('bindings',len(got))
md=capstone.Cs(capstone.CS_ARCH_ARM64,capstone.CS_MODE_ARM); md.detail=True
stubs={}
for sname in ('__stubs','__auth_stubs'):
    s=b.get_section(sname)
    if s is None: continue
    data=bytes(s.content); base=s.virtual_address
    for off in range(0,len(data)-12,12):
        ins=list(md.disasm(data[off:off+12], base+off))
        if len(ins)>=2 and ins[0].mnemonic=='adrp':
            page=ins[0].operands[1].imm
            ldr=ins[1]
            if ldr.mnemonic=='ldr':
                slot=page+ldr.operands[1].mem.disp
                if slot in got: stubs[base+off]=got[slot]
print('stubs resolved',len(stubs))
json.dump({hex(k):v for k,v in stubs.items()},open(sys.argv[2],'w'))
