import lief, capstone, struct, json, bisect, collections, csv, sys, time, re
from capstone.arm64 import ARM64_OP_IMM, ARM64_OP_REG, ARM64_OP_MEM, ARM64_INS_ADRP
BIN, OUT = sys.argv[1], sys.argv[2]
b=lief.parse(BIN)
text=b.get_section('__text'); base=text.virtual_address; data=bytes(text.content); tend=base+len(data)
stubs={int(k,16):v for k,v in json.load(open('report/stubs.json')).items()}
xr=json.load(open('ipa/xrefs.json'))
strs=collections.defaultdict(list)
for r in xr:
    if r['fn']: strs[int(r['fn'],16)].append(r['str'])
starts=sorted(set([base]+[0x100000000+f.address for f in b.functions if base<=0x100000000+f.address<tend]))
sel=b.get_section('__objc_selrefs'); sela=sel.virtual_address if sel else 0; selend=sela+(sel.size if sel else 0)
def rd(va,n):
    try: return bytes(b.get_content_from_virtual_address(va,n))
    except Exception: return b''
def cstr(va):
    d=rd(va,200); i=d.find(b'\0'); return d[:i].decode('utf8','replace') if i>0 else ''
def ptr(va):
    d=rd(va,8); return struct.unpack('<Q',d)[0] if len(d)==8 else 0
md=capstone.Cs(capstone.CS_ARCH_ARM64,capstone.CS_MODE_ARM); md.detail=True
t=time.time()
fidx=lambda a: bisect.bisect_right(starts,a)-1
rows=[]; edges=collections.Counter(); ext_global=collections.Counter()
per=collections.defaultdict(lambda: {'n':0,'calls':[],'sels':[],'int':set()})
pend={}; regsel={}
cur=None
for ins in md.disasm(data, base):
    fi=fidx(ins.address); fa=starts[fi] if fi>=0 else base
    if fa!=cur:
        pend={}; regsel={}; cur=fa
    per[fa]['n']+=1
    ops=ins.operands
    if ins.id==ARM64_INS_ADRP:
        pend[ops[0].reg]=ops[1].imm; regsel.pop(ops[0].reg,None); continue
    if ins.mnemonic=='ldr' and len(ops)==2 and ops[1].type==ARM64_OP_MEM and ops[1].mem.base in pend:
        slot=pend[ops[1].mem.base]+ops[1].mem.disp
        if sela<=slot<selend: regsel[ops[0].reg]=cstr(ptr(slot))
        else: regsel.pop(ops[0].reg,None)
    elif ins.mnemonic=='add' and len(ops)==3 and ops[1].type==ARM64_OP_REG and ops[1].reg in pend and ops[2].type==ARM64_OP_IMM:
        regsel.pop(ops[0].reg,None)
    if ins.mnemonic=='bl':
        tgt=ops[0].imm
        if tgt in stubs:
            name=stubs[tgt]
            if 'objc_msgSend' in name:
                s=regsel.get(1)
                if s: per[fa]['sels'].append(s)
                else: per[fa]['calls'].append('objc_msgSend')
            else:
                per[fa]['calls'].append(name); ext_global[name]+=1
        else:
            per[fa]['int'].add(tgt)
            edges[(fa,tgt)]+=1
    if ops and ops[0].type==ARM64_OP_REG and ins.mnemonic not in ('adrp','ldr','add'):
        regsel.pop(ops[0].reg,None)
print('disasm',round(time.time()-t),'s functions',len(starts))
GROUPS=[('camera/capture',r'AVCapture|AVCapturePhoto|capturePhoto|CaptureController|CaptureTimer|CameraController|captureOutput|AVCaptureDevice'),
 ('depth/bokeh/focus',r'Bokeh|Depth|Focus|Matte|Disparity|Portrait|LiveMetal|MVB'),
 ('core-image/filters',r'CIFilter|CIImage|CIKernel|MoodCI|CIContext|GainMap|Halation|Grain|Bloom|DynamicRange|Lut|LUT'),
 ('metal',r'MTL|Metal|CVMetal'),
 ('purchases/subscriptions',r'StoreKit|Purchase|Subscription|Entitle|NitroIap|Iap|Transaction|Offer'),
 ('storage/persistence',r'UserDefaults|FileManager|Keychain|SQLite|sqlite|AsyncStorage|Preset|presets|Store'),
 ('network',r'URLSession|CFNetwork|https?://|googleapis|mixpanel|Mixpanel|sentry'),
 ('photos/library',r'PHPhoto|PHAsset|PhotoLibrary|Photos\.|UIImageWriteToSavedPhotosAlbum'),
 ('location/motion',r'CLLocation|CoreMotion|CMMotion|LocationProvider'),
 ('ui/swiftui/uikit',r'SwiftUI|UIView|UIViewController|RCT|Reanimated|Gesture'),
 ('hermes/react-native',r'hermes|JSI|RN|react|TurboModule|Nitro'),
 ('logging/crash',r'Sentry|os_log|Logger|NSLog|Crash'),
 ('security/crypto',r'AssetCrypto|CryptoKit|CC_|SecKey|SecRandom|decrypt|cipher'),
]
GRX=[(g,re.compile(p)) for g,p in GROUPS]
def classify(names,strings):
    hay=' '.join(names[:200])+' '+' '.join(strings[:200])
    return [g for g,rx in GRX if rx.search(hay)]
rows=[]
for fa in starts:
    p=per.get(fa)
    if not p: continue
    ss=[s for s in strs.get(fa,[]) if 3<len(s)<160 and '/Users/' not in s]
    label=next((s for s in ss if not s.startswith('{')), '')
    cls=classify(p['calls']+p['sels'], ss)
    rows.append({'va':f'0x{fa:x}','file_off':f'0x{fa-0x100000000:x}','insns':p['n'],
      'ext_calls':len(p['calls']),'top_ext':'; '.join(dict.fromkeys(p['calls']))[:400],
      'selectors':'; '.join(dict.fromkeys(p['sels']))[:300],
      'internal_callees':len(p['int']),'string_refs':len(ss),'label':label[:140],'groups':','.join(cls)})
with open(OUT+'/functions.csv','w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
with open(OUT+'/edges.csv','w',newline='') as f:
    w=csv.writer(f); w.writerow(['caller_va','callee_va','call_sites'])
    for (a,c),n in edges.items(): w.writerow([f'0x{a:x}',f'0x{c:x}',n])
json.dump(ext_global.most_common(400),open(OUT+'/external_calls_top400.json','w'),indent=1)
print('functions rows',len(rows),'edges',len(edges),'ext names',len(ext_global))
