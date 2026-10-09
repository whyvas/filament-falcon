import re, html, time, json, sys
from amz import get
def verify(asin):
    for i in range(4):
        h=get(f"https://www.amazon.ca/dp/{asin}")
        if 'productTitle' in h: break
        time.sleep(5+5*i)
    t=re.search(r'id="productTitle"[^>]*>\s*(.*?)\s*</span>', h, re.S)
    title=html.unescape(t.group(1)).strip() if t else None
    price=None
    m=re.search(r'apex-pricetopay-accessibility-label"[^>]*>\s*\$([0-9,]+\.[0-9]{2})', h)
    if not m:
        j=h.find('priceToPay apex-pricetopay-value')
        if j>=0:
            mm=re.search(r'a-price-whole">([0-9,]+)<.*?a-price-fraction">([0-9]{2})<', h[j:j+1500], re.S)
            if mm: price=float((mm.group(1)+'.'+mm.group(2)).replace(',',''))
    else: price=float(m.group(1).replace(',',''))
    if price: return dict(asin=asin,title=title,price=price,unavail=False)
    for blk in ('corePriceDisplay_desktop_feature_div','corePrice_feature_div','apex_desktop','corePrice_desktop'):
        i=h.find(f'id="{blk}"')
        if i>=0:
            m=re.search(r'class="a-offscreen">\s*\$([0-9,]+\.[0-9]{2})', h[i:i+8000])
            if not m:
                m=re.search(r'a-price-whole">([0-9,]+)<.*?a-price-fraction">([0-9]{2})<', h[i:i+8000], re.S)
                if m: price=float((m.group(1)+'.'+m.group(2)).replace(',',''))
            else: price=float(m.group(1).replace(',',''))
            if price: break
    unavailable = ('Currently unavailable' in h) or ('No featured offers available' in h)
    return dict(asin=asin,title=title,price=price,unavail=unavailable)
if __name__=="__main__":
    for a in sys.argv[1:]:
        print(json.dumps(verify(a))); time.sleep(2)
