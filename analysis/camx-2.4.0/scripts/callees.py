import lief, capstone, struct, json, sys, bisect
from capstone.arm64 import ARM64_OP_IMM, ARM64_OP_REG, ARM64_OP_MEM
from capstone.arm64 import ARM64_INS_ADRP
b=lief.parse(sys.argv[1]); stubs={int(k,16):v for k,v in json.load(open(sys.argv[2])).items()}
addrs=[int(a,16) for a in sys.argv[3].split(',')]
text=b.get_section('__text'); base=text.virtual_address; data=bytes(text.content)
starts=sorted(set([base]+[0x100000000+f.address for f in b.functions if base<=0x100000000+f.address<base+len(data)]))
sel=b.get_section('__objc_selrefs'); selva=sel.virtual_address if sel else 0
def ptr(va):
    try: return struct.unpack('<Q', bytes(b.get_content_from_virtual_address(va,8)))[0]
    except Exception: return 0
def cstr(va):
    try:
        d=bytes(b.get_content_from_virtual_address(va,200)); return d[:d.find(b'\0')].decode('utf8','replace')
    except Exception: return ''
md=capstone.Cs(capstone.CS_ARCH_ARM64,capstone.CS_MODE_ARM); md.detail=True
for fa in addrs:
    i=bisect.bisect_right(starts,fa)
    end=starts[i] if i<len(starts) else base+len(data)
    code=data[fa-base:end-base]
    calls=[]; pend={}; regval={}
    n_ins=0
    for ins in md.disasm(code, fa):
        n_ins+=1
        ops=ins.operands
        if ins.id==ARM64_INS_ADRP:
            pend[ops[0].reg]=ops[1].imm; regval.pop(ops[0].reg,None); continue
        if ins.mnemonic=='ldr' and len(ops)==2 and ops[1].type==ARM64_OP_MEM and ops[1].mem.base in pend:
            slot=pend[ops[1].mem.base]+ops[1].mem.disp
            if selva and sel.virtual_address<=slot<sel.virtual_address+sel.size:
                regval[ops[0].reg]=('sel',ptr(slot))
            else:
                regval.pop(ops[0].reg,None)
        elif ins.mnemonic=='add' and len(ops)==3 and ops[1].type==ARM64_OP_REG and ops[1].reg in pend and ops[2].type==ARM64_OP_IMM:
            regval[ops[0].reg]=('str',pend[ops[1].reg]+ops[2].imm); pend[ops[0].reg]=pend.get(ops[0].reg)
        if ins.mnemonic=='bl':
            tgt=ops[0].imm
            name=stubs.get(tgt,None)
            if name is None and tgt in stubs: name=stubs[tgt]
            if name=='_objc_msgSend' or (name and 'objc_msgSend' in name):
                v=regval.get(1)
                s=cstr(v[1]) if v and v[0]=='sel' else None
                if v and v[0]=='str': s=cstr(v[1])
                calls.append(('objc:'+(s or '?')))
            else:
                calls.append(name or hex(tgt))
        # invalidate written regs (crude)
        if ops and ops[0].type==ARM64_OP_REG and ins.mnemonic not in ('adrp','ldr','add'):
            regval.pop(ops[0].reg,None)
        if ins.mnemonic in ('ret','b') and n_ins>3: pass
    print('== %s  size=%d insns  calls=%d'%(hex(fa),len(code),len(calls)))
    seen=[]
    for c in calls:
        if c not in seen: seen.append(c)
    for c in seen[:200]: print('   ',c[:150])
