#!/usr/bin/env python3
"""
US News Best High Schools 2025-2026 scraper.

Fetches every public high school for a given US state from US News and writes
data/{state_slug}_high_schools.json. Uses curl_cffi (Chrome TLS impersonation)
because US News stalls non-browser TLS fingerprints.

Extraction logic is a 1:1 port of the browser-MCP harness that produced the
already-verified Alabama and Alaska files. Accuracy first: any value that can't
be pulled with confidence is written as null, never guessed.

Usage:
  python usnews_scraper.py alabama                # one state
  python usnews_scraper.py alabama alaska arizona # several
  python usnews_scraper.py --all                  # all states, skip utah + already-done
  python usnews_scraper.py --all --force          # re-scrape even if file exists
"""
import sys, os, re, json, html, time, threading, random
from concurrent.futures import ThreadPoolExecutor
from curl_cffi import requests as cr
import lxml.html as LH

BASE = "https://www.usnews.com/education/best-high-schools"
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
WORKERS = 16

STATE_ABBR = {"AL":"Alabama","AK":"Alaska","AZ":"Arizona","AR":"Arkansas","CA":"California",
"CO":"Colorado","CT":"Connecticut","DE":"Delaware","FL":"Florida","GA":"Georgia","HI":"Hawaii",
"ID":"Idaho","IL":"Illinois","IN":"Indiana","IA":"Iowa","KS":"Kansas","KY":"Kentucky",
"LA":"Louisiana","ME":"Maine","MD":"Maryland","MA":"Massachusetts","MI":"Michigan","MN":"Minnesota",
"MS":"Mississippi","MO":"Missouri","MT":"Montana","NE":"Nebraska","NV":"Nevada","NH":"New Hampshire",
"NJ":"New Jersey","NM":"New Mexico","NY":"New York","NC":"North Carolina","ND":"North Dakota",
"OH":"Ohio","OK":"Oklahoma","OR":"Oregon","PA":"Pennsylvania","RI":"Rhode Island","SC":"South Carolina",
"SD":"South Dakota","TN":"Tennessee","TX":"Texas","UT":"Utah","VT":"Vermont","VA":"Virginia",
"WA":"Washington","WV":"West Virginia","WI":"Wisconsin","WY":"Wyoming","DC":"District of Columbia"}

WORDNUM = {"first":1,"second":2,"third":3,"fourth":4,"fifth":5,"sixth":6,"seventh":7,
"eighth":8,"ninth":9,"tenth":10}

# All states alphabetical, skipping Utah (already scraped in a prior session)
ALL_STATES = [("alabama","Alabama"),("alaska","Alaska"),("arizona","Arizona"),("arkansas","Arkansas"),
("california","California"),("colorado","Colorado"),("connecticut","Connecticut"),("delaware","Delaware"),
("florida","Florida"),("georgia","Georgia"),("hawaii","Hawaii"),("idaho","Idaho"),("illinois","Illinois"),
("indiana","Indiana"),("iowa","Iowa"),("kansas","Kansas"),("kentucky","Kentucky"),("louisiana","Louisiana"),
("maine","Maine"),("maryland","Maryland"),("massachusetts","Massachusetts"),("michigan","Michigan"),
("minnesota","Minnesota"),("mississippi","Mississippi"),("missouri","Missouri"),("montana","Montana"),
("nebraska","Nebraska"),("nevada","Nevada"),("new-hampshire","New Hampshire"),("new-jersey","New Jersey"),
("new-mexico","New Mexico"),("new-york","New York"),("north-carolina","North Carolina"),
("north-dakota","North Dakota"),("ohio","Ohio"),("oklahoma","Oklahoma"),("oregon","Oregon"),
("pennsylvania","Pennsylvania"),("rhode-island","Rhode Island"),("south-carolina","South Carolina"),
("south-dakota","South Dakota"),("tennessee","Tennessee"),("texas","Texas"),("vermont","Vermont"),
("virginia","Virginia"),("washington","Washington"),("west-virginia","West Virginia"),
("wisconsin","Wisconsin"),("wyoming","Wyoming")]

_tl = threading.local()
def _session():
    s = getattr(_tl, "s", None)
    if s is None:
        s = _tl.s = cr.Session(impersonate="chrome")
    return s

def fetch(url, accept_json=False, tries=5):
    """GET with Chrome impersonation + retry/backoff. Returns text or None."""
    headers = {"Accept": "application/json"} if accept_json else {}
    for i in range(tries):
        try:
            r = _session().get(url, headers=headers, timeout=35)
            if r.status_code == 200:
                return r.text
            if r.status_code in (404, 410):
                return None  # genuinely missing; don't retry
        except Exception:
            pass
        time.sleep(min(8, 1.5 * (i + 1)) + random.random())
    return None

def slugify(name):
    return name.lower().replace(".", "").replace("&", "").replace("'", "-").replace(" ", "-")

def parse_pct(s):
    if s is None: return None
    m = re.match(r"^(\d{1,3})%$", s.strip())
    if not m: return None
    n = int(m.group(1))
    return n if 0 <= n <= 100 else None

def get_districts(state_slug):
    txt = fetch(f"{BASE}/api/districts/dropdown?state-urlname={state_slug}", accept_json=True)
    if not txt: return []
    j = json.loads(txt)
    d = j.get("data", j)
    out = []
    for o in d.get("items", []):
        nm = o["name"]
        out.append({"id": str(o["district_id"]), "name": nm, "slug": slugify(nm)})
    return out

SCHOOL_RE_CACHE = {}
def school_url_regex(state_slug):
    if state_slug not in SCHOOL_RE_CACHE:
        SCHOOL_RE_CACHE[state_slug] = re.compile(
            r"/education/best-high-schools/" + re.escape(state_slug) + r"/districts/[^\"'\s]+?/[a-z0-9-]+-\d+")
    return SCHOOL_RE_CACHE[state_slug]

def crawl_district(state_slug, d):
    url = f"{BASE}/{state_slug}/districts/{d['slug']}-{d['id']}"
    html_txt = fetch(url)
    if not html_txt:
        return d["name"], None, []  # fetch failed
    found = list(dict.fromkeys(school_url_regex(state_slug).findall(html_txt)))
    return d["name"], "https://www.usnews.com", found

def find_ld(tree):
    for sc in tree.xpath('//script[@type="application/ld+json"]'):
        raw = sc.text_content()
        try:
            j = json.loads(raw)
        except Exception:
            continue
        arr = j if isinstance(j, list) else (j.get("@graph") if isinstance(j, dict) and "@graph" in j else [j])
        for o in arr:
            if not isinstance(o, dict): continue
            t = o.get("@type", "")
            t = " ".join(t) if isinstance(t, list) else str(t)
            if re.search(r"school", t, re.I) or (isinstance(o.get("location"), dict) and o["location"].get("address")):
                return o
    return None

def tid_text(tree, test_id):
    els = tree.xpath(f'//*[@data-test-id="{test_id}"]')
    return els[0].text_content().strip() if els else None

def extract_school(html_txt, url, district, state_name):
    rec = {"school_name":None,"district":district,"address":None,"overall_score":None,
        "state_rank":None,"national_rank":None,"ap_taken_pct":None,"ap_passed_pct":None,
        "math_proficiency":None,"reading_proficiency":None,"science_proficiency":None,
        "graduation_rate":None,"graduation_rate_raw":None,"year":"2025-2026","source_url":url}
    tree = LH.fromstring(html_txt)
    ld = find_ld(tree)
    if ld and ld.get("name"):
        rec["school_name"] = html.unescape(str(ld["name"]).strip())
    if ld:
        addr = (ld.get("location") or {}).get("address") if isinstance(ld.get("location"), dict) else None
        if not addr: addr = ld.get("address")
        if isinstance(addr, dict):
            street = html.unescape(str(addr["streetAddress"]).strip()) if addr.get("streetAddress") else None
            locality = html.unescape(str(addr["addressLocality"]).strip()) if addr.get("addressLocality") else None
            region = str(addr["addressRegion"]).strip() if addr.get("addressRegion") else None
            zip_ = str(addr["postalCode"]).strip() if addr.get("postalCode") else None
            if region and len(region) == 2 and region.upper() in STATE_ABBR:
                region = STATE_ABBR[region.upper()]
            if street and locality and region:
                rec["address"] = f"{street}, {locality}, {region}" + (f" {zip_}" if zip_ else "")
    # overall score
    ov = tid_text(tree, "scorecard_Overall")
    if ov is not None and "less than" not in ov.lower():
        try:
            f = float(ov)
            if 0 <= f <= 100: rec["overall_score"] = f
        except ValueError:
            pass
    # full page text for rank regexes (mirrors browser doc.body.textContent)
    body = tree.xpath("//body")
    text = body[0].text_content() if body else tree.text_content()
    # national rank (safe first-match)
    nm = re.search(r"#([\d,]+)\s+in\s+National Rankings", text)
    if nm:
        n = int(nm.group(1).replace(",", ""))
        if n > 0: rec["national_rank"] = n
    # state rank: PRIMARY = JSON-LD description; FALLBACK = page text if ranked
    st = re.escape(state_name)
    if ld and ld.get("description"):
        desc = html.unescape(ld["description"])
        m = re.search(r"is ranked (\d+)(?:st|nd|rd|th)?\s+within\s+" + st, desc)
        if m:
            n = int(m.group(1))
            if n > 0: rec["state_rank"] = n
        else:
            m = re.search(r"is ranked (first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)\s+within\s+" + st, desc, re.I)
            if m:
                rec["state_rank"] = WORDNUM[m.group(1).lower()]
    if rec["state_rank"] is None and rec["national_rank"] is not None:
        sm = re.search(r"#(\d+)\s+in\s+" + st + r" High Schools", text)
        if sm:
            n = int(sm.group(1))
            if n > 0: rec["state_rank"] = n
    # percent fields
    rec["ap_taken_pct"] = parse_pct(tid_text(tree, "participation_rate"))
    rec["ap_passed_pct"] = parse_pct(tid_text(tree, "participant_passing_rate"))
    rec["math_proficiency"] = parse_pct(tid_text(tree, "school_percent_proficient_in_math"))
    rec["reading_proficiency"] = parse_pct(tid_text(tree, "school_percent_proficient_in_english"))
    rec["science_proficiency"] = parse_pct(tid_text(tree, "school_percent_proficient_in_science"))
    # graduation
    graw = tid_text(tree, "gradrate")
    if graw is not None:
        rec["graduation_rate_raw"] = graw  # lxml already entity-decoded
        gm = re.match(r"^(\d{1,3})%$", graw)
        if gm:
            n = int(gm.group(1))
            if 0 <= n <= 100: rec["graduation_rate"] = n
    return rec

def stats(records):
    ranks = sorted(r["state_rank"] for r in records if r["state_rank"] is not None)
    present = set(ranks); maxr = ranks[-1] if ranks else 0
    missing = [i for i in range(1, maxr + 1) if i not in present]
    urls = [r["source_url"] for r in records]
    dup_urls = len(urls) - len(set(urls))
    badpct = 0
    for r in records:
        for f in ("ap_taken_pct","ap_passed_pct","math_proficiency","reading_proficiency","science_proficiency","graduation_rate"):
            v = r[f]
            if v is not None and (not isinstance(v, int) or v < 0 or v > 100): badpct += 1
    return {"total":len(records),"ranked":len(ranks),"max_state_rank":maxr,
        "missing_ranks":len(missing),"missing_sample":missing[:20],
        "dup_ranks":len(ranks)-len(present),"national_ranked":sum(1 for r in records if r["national_rank"] is not None),
        "with_score":sum(1 for r in records if r["overall_score"] is not None),
        "dup_urls":dup_urls,"bad_pct":badpct,"no_name":sum(1 for r in records if not r["school_name"])}

def write_file(state_slug, records):
    os.makedirs(DATA_DIR, exist_ok=True)
    lines = ["  " + json.dumps(r, ensure_ascii=False, separators=(",", ":")) for r in records]
    content = "[\n" + ",\n".join(lines) + "\n]\n"
    path = os.path.join(DATA_DIR, f"{state_slug}_high_schools.json")
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    return path

def scrape_state(state_slug, state_name):
    t0 = time.time()
    districts = get_districts(state_slug)
    print(f"[{state_slug}] {len(districts)} districts")
    # crawl district landing pages -> ordered, deduped (url, district)
    ordered, seen, fail_d = [], set(), []
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        for dname, domain, found in ex.map(lambda d: crawl_district(state_slug, d), districts):
            if domain is None:
                fail_d.append(dname); continue
            for u in found:
                full = domain + u
                if full not in seen:
                    seen.add(full); ordered.append((full, dname))
    print(f"[{state_slug}] {len(ordered)} school URLs ({len(fail_d)} district fetch fails){' '+str(fail_d[:5]) if fail_d else ''}")
    # fetch + extract school pages
    recs_by_url, fail_s = {}, []
    def do(item):
        url, dist = item
        h = fetch(url)
        if not h: return url, None
        return url, extract_school(h, url, dist, state_name)
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        for url, rec in ex.map(do, ordered):
            if rec is None: fail_s.append(url)
            else: recs_by_url[url] = rec
    # one retry pass for failures
    if fail_s:
        retry = list(fail_s); fail_s = []
        dmap = dict(ordered)
        with ThreadPoolExecutor(max_workers=8) as ex:
            for url, rec in ex.map(lambda u: do((u, dmap[u])), retry):
                if rec is None: fail_s.append(url)
                else: recs_by_url[url] = rec
    records = [recs_by_url[u] for (u, _) in ordered if u in recs_by_url]
    st = stats(records)
    path = write_file(state_slug, records)
    dt = time.time() - t0
    print(f"[{state_slug}] wrote {st['total']} -> {os.path.basename(path)} in {dt:.0f}s | "
          f"ranked={st['ranked']} maxRank={st['max_state_rank']} missingRanks={st['missing_ranks']}{st['missing_sample'] if st['missing_ranks'] else ''} "
          f"dupRanks={st['dup_ranks']} dupURLs={st['dup_urls']} badPct={st['bad_pct']} noName={st['no_name']} schoolFails={len(fail_s)}")
    if fail_s:
        print(f"[{state_slug}] PERSISTENT SCHOOL FAILS ({len(fail_s)}): {fail_s[:10]}")
    return st

def main():
    args = [a for a in sys.argv[1:]]
    force = "--force" in args; args = [a for a in args if a != "--force"]
    if "--all" in args:
        todo = ALL_STATES
    else:
        want = set(args)
        todo = [(s, n) for (s, n) in ALL_STATES if s in want]
        if not todo:
            print("No matching states. Pass slugs (e.g. arizona) or --all."); return
    for slug, name in todo:
        path = os.path.join(DATA_DIR, f"{slug}_high_schools.json")
        if os.path.exists(path) and not force:
            print(f"[{slug}] exists, skipping (use --force to redo)"); continue
        try:
            scrape_state(slug, name)
        except Exception as e:
            print(f"[{slug}] ERROR {type(e).__name__}: {e}")

if __name__ == "__main__":
    main()
