import random, sys
sys.path.insert(0,'/home/claude/proto')
from matcher import *
from simulate import noisy, keys, ayahs, idx
random.seed(3)
# simulate continuous recitation of random surahs, chopped in VAD-like segments
for cer in [0.05, 0.15, 0.25]:
  for use_ctx in [False, True]:
    ok=tot=0
    for trial in range(30):
        s = random.randint(1,114)
        ids=[k for k,(ss,aa,_) in enumerate(ayahs) if ss==s][:40]
        text=''.join(keys[k] for k in ids)
        owner=[]
        for k in ids: owner += [k]*len(keys[k])
        p=0; prev=None
        while p < len(text):
            L=random.randint(15,160); seg=text[p:p+L]
            if len(seg)<10: break
            r=match(idx, noisy(seg,cer), prev_end=prev if use_ctx else None)
            tot+=1
            if r and keys[idx.ayah_of(r['start'])]==keys[owner[p]]: ok+=1
            if r: prev=r['end']
            p+=L
    print(f'cer {cer} ctx={use_ctx}: {ok}/{tot}={ok/tot:.3f}')
