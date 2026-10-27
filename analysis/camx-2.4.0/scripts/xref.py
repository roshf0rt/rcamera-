import lief, capstone, bisect, json, sys, time
from capstone.arm64 import ARM64_OP_IMM, ARM64_OP_REG, ARM64_OP_MEM, ARM64_INS_ADRP
path=sys.argv[1]; out=sys.argv[2]
b=lief.parse(path)
text=b.get_section('__text')
base=text.virtual_address; data=bytes(text.content)
cs=b.get_section('__cstring')
cstr_lo=cs.virtual_address; cstr_hi=cs.virtual_address+cs.size
cdata=bytes(cs.content)
starts=sorted(set([base]+[0x100000000+f.address for f in b.functions if base<=0x100000000+f.address<base+len(data)]))
md=capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM); md.detail=True
pending={}   # reg -> (page, insn addr)
refs={}      # target string va -> list of insn addrs
t=time.time()
for ins in md.disasm(data, base):
    d=ins.operands
    # ADRP xN, page
    if ins.id==ARM64_INS_ADRP:
        dst=d[0].reg; page=d[1].imm
        pending[dst]=page
        continue
    tgt=None
    if ins.mnemonic in ('add','ldr','ldrb','ldrh','ldur','ldrsw') and len(d)>=2:
        src=d[1]
        if src.type==ARM64_OP_MEM and src.mem.base in pending:
            tgt=pending[src.mem.base]+src.mem.disp
        elif ins.mnemonic=='add' and len(d)==3 and d[1].type==ARM64_OP_REG and d[1].reg in pending and d[2].type==ARM64_OP_IMM:
            tgt=pending[d[1].reg]+d[2].imm
    if tgt is not None and cstr_lo<=tgt<cstr_hi:
        refs.setdefault(tgt,[]).append(ins.address)
    # any write to a reg invalidates pending
    if d and d[0].type==ARM64_OP_REG and d[0].reg in pending and ins.mnemonic!='adrp':
        pending.pop(d[0].reg,None)
print('disasm',round(time.time()-t),'s; string targets referenced:',len(refs))
def cstring(va):
    o=va-cstr_lo; e=cdata.find(b'\0',o)
    return cdata[o:e].decode('utf8','replace')
res=[]
for tva,addrs in refs.items():
    s=cstring(tva)
    for a in addrs:
        i=bisect.bisect_right(starts,a)-1
        fn=starts[i] if i>=0 else None
        res.append({'str':s,'insn':hex(a),'fn':hex(fn) if fn else None})
json.dump(res,open(out,'w'))
print('xref records',len(res))
