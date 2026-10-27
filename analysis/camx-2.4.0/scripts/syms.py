import lief,re,collections,sys
b=lief.parse(sys.argv[1])
print('format',b.format,'arch',b.header.cpu_type, 'nsyms',len(b.symbols),'nfuncs',len(b.functions))
names=[s.name for s in b.symbols if s.name]
open(sys.argv[2],'w').write('\n'.join(names))
app=[n for n in names if '4CamX' in n or 'Mood' in n]
print('app-related symbols',len(app))
cnt=collections.Counter()
for n in app:
    m=re.search(r'4CamX(\d+)?([A-Za-z_]+)', n)
    if m: cnt[m.group(2)[:40]]+=1
for k,v in cnt.most_common(70): print(v,k)
