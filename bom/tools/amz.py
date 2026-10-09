import sys, re, subprocess, html, json, urllib.parse, time
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36"
def get(url):
    return subprocess.run(["curl","-s","-L","--compressed","-A",UA,"-H","Accept-Language: en-CA,en;q=0.9",url],capture_output=True,text=True,errors="ignore").stdout
def search(q, n=6):
    for i in range(4):
        h=get("https://www.amazon.ca/s?k="+urllib.parse.quote_plus(q))
        if len(h)>20000: break
        time.sleep(6+i*5)
    out=[]
    for m in re.finditer(r'<div role="listitem" data-asin="([A-Z0-9]{10})"(.*?)(?=<div role="listitem" data-asin=|$)', h, re.S):
        asin, body = m.group(1), m.group(2)
        if 'Sponsored' in body[:20000] and 'puis-sponsored' in body: sp='S'
        else: sp=' '
        t=re.search(r'<h2[^>]*aria-label="([^"]+)"', body) or re.search(r'<h2[^>]*>.*?<span[^>]*>([^<]+)</span>', body, re.S)
        p=re.search(r'class="a-offscreen">([^<]+)<', body)
        out.append((asin, sp, p.group(1) if p else '-', html.unescape(t.group(1))[:110] if t else '?'))
        if len(out)>=n: break
    if not out: out.append(('NONE', '', '', 'len=%d captcha=%s'%(len(h),'captcha' in h.lower())))
    return out
if __name__=="__main__":
    for q in sys.argv[1:]:
        print("##",q)
        for r in search(q): print("  ",*r)
        time.sleep(3)
