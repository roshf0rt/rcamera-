import json,sys,collections
R=json.load(open('ipa/xrefs.json'))
by=collections.defaultdict(list)
for r in R:
    if r['fn']: by[r['fn']].append(r['str'])
kw=sys.argv[1].split('|'); limit=int(sys.argv[2]) if len(sys.argv)>2 else 40
hits=[f for f,ss in by.items() if any(any(k.lower() in s.lower() for k in kw) for s in ss)]
print('functions matching',len(hits))
for f in sorted(hits)[:limit]:
    ss=[s for s in by[f] if len(s)>3]
    print(f, '|', ' ;; '.join(s[:90] for s in ss[:12]))
