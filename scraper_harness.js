// US News scraper harness v3 — XHR transport (bypasses Akamai fetch-hook), gentle pacing +
// block-aware cooldown backoff, AND per-district pagination (&page=N) so big districts
// (Miami-Dade, LAUSD, Hawaii DOE) aren't truncated to their first 20 schools.
// Inject into an authenticated www.usnews.com tab on a NON-gated page (a school page, NOT
// national-rankings which redirects to the paywall). Sets window.__SCRAPE.
(function(){
const S = window.__SCRAPE = {};
const sleep = ms => new Promise(r=>setTimeout(r,ms));
const CM = 50000; const COOL = 90000;
const SCH_BATCH = 5, SCH_SLEEP = 700, SCH_BLOCK = 3;
const DIS_BATCH = 8, DIS_SLEEP = 500, DIS_BLOCK = 4;
S.STATE_ABBR = {AL:'Alabama',AK:'Alaska',AZ:'Arizona',AR:'Arkansas',CA:'California',CO:'Colorado',CT:'Connecticut',DE:'Delaware',FL:'Florida',GA:'Georgia',HI:'Hawaii',ID:'Idaho',IL:'Illinois',IN:'Indiana',IA:'Iowa',KS:'Kansas',KY:'Kentucky',LA:'Louisiana',ME:'Maine',MD:'Maryland',MA:'Massachusetts',MI:'Michigan',MN:'Minnesota',MS:'Mississippi',MO:'Missouri',MT:'Montana',NE:'Nebraska',NV:'Nevada',NH:'New Hampshire',NJ:'New Jersey',NM:'New Mexico',NY:'New York',NC:'North Carolina',ND:'North Dakota',OH:'Ohio',OK:'Oklahoma',OR:'Oregon',PA:'Pennsylvania',RI:'Rhode Island',SC:'South Carolina',SD:'South Dakota',TN:'Tennessee',TX:'Texas',UT:'Utah',VT:'Vermont',VA:'Virginia',WA:'Washington',WV:'West Virginia',WI:'Wisconsin',WY:'Wyoming',DC:'District of Columbia'};
S.WORDNUM = {first:1,second:2,third:3,fourth:4,fifth:5,sixth:6,seventh:7,eighth:8,ninth:9,tenth:10};
S._ta = document.createElement('textarea'); S.decode = s => { S._ta.innerHTML = s; return S._ta.value; };
S.parsePct = s => { if(s==null) return null; const m=String(s).trim().match(/^(\d{1,3})%$/); if(!m) return null; const n=parseInt(m[1],10); return (n>=0&&n<=100)?n:null; };
S.esc = x => x.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
S.slugify = n => n.toLowerCase().replace(/'/g,'-').replace(/[^a-z0-9 -]/g,'').replace(/ /g,'-');
S.xhrGet = (url,json) => new Promise((resolve)=>{ const x=new XMLHttpRequest(); try{x.open('GET',url,true);}catch(e){return resolve({status:0,text:''});} x.withCredentials=true; if(json){try{x.setRequestHeader('accept','application/json');}catch(e){}} x.timeout=35000; x.onreadystatechange=()=>{ if(x.readyState===4) resolve({status:x.status,text:x.responseText||''}); }; x.onerror=()=>resolve({status:0,text:''}); x.ontimeout=()=>resolve({status:0,text:''}); x.send(); });
S.init = (slug,name) => { S.stateSlug=slug; S.stateName=name; S.districts=[]; S.districtMap={}; S.schoolUrls=[]; S.seenUrls=new Set(); S.results=[]; S.processed=new Set(); S.failedDistrictObjs=[]; S.zeroDistricts=[]; S.failedSchools=[]; S.rankedUrls=[]; S.bg=null; S.fileContent=''; return 'init '+slug; };
S.loadDistricts = async () => { const r=await S.xhrGet(`https://www.usnews.com/education/best-high-schools/api/districts/dropdown?state-urlname=${S.stateSlug}`,true); const j=JSON.parse(r.text); const d=j.data||j; const items=d.items||[]; S.districts=items.map(o=>({id:String(o.district_id),name:o.name,slug:S.slugify(o.name)})); S.districtMap={}; S.districts.forEach(x=>{S.districtMap[x.slug]=x.name;}); return JSON.stringify({total:d.totalItems,loaded:S.districts.length}); };
S.extractSchool = (html, url, districtName) => {
  const rec = { school_name:null, district:districtName, address:null, overall_score:null, state_rank:null, national_rank:null, ap_taken_pct:null, ap_passed_pct:null, math_proficiency:null, reading_proficiency:null, science_proficiency:null, graduation_rate:null, graduation_rate_raw:null, year:"2025-2026", source_url:url };
  const doc = new DOMParser().parseFromString(html, 'text/html'); let ld = null;
  for (const s of Array.from(doc.querySelectorAll('script[type="application/ld+json"]'))) { try { const j=JSON.parse(s.textContent); const arr=Array.isArray(j)?j:(j['@graph']?j['@graph']:[j]); for(const o of arr){ if(o && (/school/i.test(o['@type']||'')||(o.location&&o.location.address))){ld=o;break;} } } catch(e){} if (ld) break; }
  if (ld && ld.name) rec.school_name = S.decode(String(ld.name).trim());
  if (ld) { const addr=(ld.location&&ld.location.address)||ld.address; if(addr){ const street=addr.streetAddress?S.decode(String(addr.streetAddress).trim()):null; const locality=addr.addressLocality?S.decode(String(addr.addressLocality).trim()):null; let region=addr.addressRegion?String(addr.addressRegion).trim():null; const zip=addr.postalCode?String(addr.postalCode).trim():null; if(region&&region.length===2&&S.STATE_ABBR[region.toUpperCase()]) region=S.STATE_ABBR[region.toUpperCase()]; if(street&&locality&&region) rec.address=`${street}, ${locality}, ${region}${zip?' '+zip:''}`; } }
  const ov = doc.querySelector('[data-test-id="scorecard_Overall"]'); if (ov) { const t=ov.textContent.trim(); const f=parseFloat(t); if(!/less than/i.test(t)&&!isNaN(f)&&f>=0&&f<=100) rec.overall_score=f; }
  const txt = (doc.body&&doc.body.textContent)||''; const nm = txt.match(/#([\d,]+)\s+in\s+National Rankings/); if (nm){ const n=parseInt(nm[1].replace(/,/g,''),10); if(n>0) rec.national_rank=n; }
  const st = S.esc(S.stateName);
  if (ld && ld.description) { const desc=S.decode(ld.description); let m=desc.match(new RegExp(`is ranked ([\\d,]+)(?:st|nd|rd|th)?\\s+within\\s+${st}`)); if(m){const n=parseInt(m[1].replace(/,/g,''),10); if(n>0) rec.state_rank=n;} else { m=desc.match(new RegExp(`is ranked (first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)\\s+within\\s+${st}`,'i')); if(m){const n=S.WORDNUM[m[1].toLowerCase()]; if(n) rec.state_rank=n;} } }
  if (rec.state_rank==null && rec.national_rank!=null) { const sm = txt.match(new RegExp(`#([\\d,]+)(-[\\d,]+)?\\s+in\\s+${st} High Schools`)); if (sm && !sm[2]) { const n=parseInt(sm[1].replace(/,/g,''),10); if(n>0) rec.state_rank=n; } }
  const gid = id=>{const el=doc.querySelector(`[data-test-id="${id}"]`); return el?el.textContent.trim():null;};
  rec.ap_taken_pct=S.parsePct(gid('participation_rate')); rec.ap_passed_pct=S.parsePct(gid('participant_passing_rate')); rec.math_proficiency=S.parsePct(gid('school_percent_proficient_in_math')); rec.reading_proficiency=S.parsePct(gid('school_percent_proficient_in_english')); rec.science_proficiency=S.parsePct(gid('school_percent_proficient_in_science'));
  const gradEl=doc.querySelector('[data-test-id="gradrate"]'); if(gradEl){const raw=S.decode(gradEl.textContent.trim()); rec.graduation_rate_raw=raw; const gm=raw.match(/^(\d{1,3})%$/); if(gm){const n=parseInt(gm[1],10); if(n>=0&&n<=100) rec.graduation_rate=n;}}
  return rec;
};
// paginate ONE district fully (&page=N) — fixes big-district truncation
S.crawlOneDistrict = async (d) => {
  const re=new RegExp(`/education/best-high-schools/${S.stateSlug}/districts/[^"'\\s]+?/[a-z0-9-]+-\\d+`,'g');
  const base=`https://www.usnews.com/education/best-high-schools/${S.stateSlug}/districts/${d.slug}-${d.id}`;
  const found=new Set(); let p=1;
  while(p<=25){ const r=await S.xhrGet(base+(p>1?`?page=${p}`:'')); if(r.status===403||r.status===0) return {block:true}; if(r.status!==200||r.text.length<CM){ if(p===1) return {fail:true}; break; } const urls=Array.from(new Set(r.text.match(re)||[])); const before=found.size; urls.forEach(u=>found.add(u)); if(found.size===before||urls.length<20) break; p++; await sleep(120); }
  return {found:Array.from(found)};
};
S.fetchDistrictBatch = async (start,count) => { const slice=S.districts.slice(start,start+count); let blk=0; await Promise.allSettled(slice.map(async d=>{ const res=await S.crawlOneDistrict(d); if(res.block){blk++; S.failedDistrictObjs.push(d); return;} if(res.fail){S.failedDistrictObjs.push(d); return;} if(res.found.length===0) S.zeroDistricts.push(d); res.found.forEach(u=>{const full='https://www.usnews.com'+u; if(!S.seenUrls.has(full)){S.seenUrls.add(full); S.schoolUrls.push({url:full,district:d.name});}}); })); return blk; };
S.retryDistricts = async () => { const items=S.failedDistrictObjs.slice(); S.failedDistrictObjs=[]; let blk=0; for(const d of items){ const res=await S.crawlOneDistrict(d); if(res.block){blk++; S.failedDistrictObjs.push(d); await sleep(1500); continue;} if(res.fail){S.failedDistrictObjs.push(d); await sleep(150); continue;} if(res.found.length===0) S.zeroDistricts.push(d); res.found.forEach(u=>{const full='https://www.usnews.com'+u; if(!S.seenUrls.has(full)){S.seenUrls.add(full); S.schoolUrls.push({url:full,district:d.name});}}); await sleep(120); } return blk; };
S.fetchOne = async (item) => { const r=await S.xhrGet(item.url); if(r.status===403) return '403'; if(r.status===0) return 'block'; if(r.status!==200||r.text.length<CM||r.text.indexOf('application/ld+json')===-1) return 'bad'; const rec=S.extractSchool(r.text,item.url,item.district); if(!rec.school_name) return 'noname'; if(!S.processed.has(item.url)){S.processed.add(item.url); S.results.push(rec);} return true; };
S.fetchSchoolBatch = async (start,count) => { const slice=S.schoolUrls.slice(start,start+count).filter(it=>!S.processed.has(it.url)); let fails=0; await Promise.allSettled(slice.map(async it=>{ const res=await S.fetchOne(it); if(res!==true){ S.failedSchools.push(it.url); if(res==='403'||res==='block') fails++; } })); return fails; };
S.retryFailed = async () => { const urls=Array.from(new Set(S.failedSchools)); S.failedSchools=[]; const dmap={}; S.schoolUrls.forEach(x=>dmap[x.url]=x.district); let blk=0; for(const u of urls){ if(S.processed.has(u)) continue; const res=await S.fetchOne({url:u,district:dmap[u]||null}); if(res!==true){ S.failedSchools.push(u); if(res==='403'||res==='block'){blk++; await sleep(1000);} else await sleep(120); } } return blk; };
S.enumerateRanked = async () => { S.rankedUrls=[]; const seen=new Set(); const re=new RegExp(`/education/best-high-schools/${S.stateSlug}/districts/[a-z0-9-]+/[a-z0-9-]+-\\d+`,'g'); let p=1,end=false,dup=0,scanned=0; while(!end&&scanned<220){ let urls=null; for(let t=0;t<5;t++){ const r=await S.xhrGet(`https://www.usnews.com/education/best-high-schools/search?state-urlname=${S.stateSlug}&ranked=true&page=${p}`); if(r.status===200){urls=r.text.match(re)||[]; break;} if(r.status===403||r.status===0){await sleep(4000); continue;} await sleep(700); } scanned++; if(urls===null){end=true; break;} if(urls.length===0){end=true; break;} let n=0; urls.forEach(u=>{const full='https://www.usnews.com'+u; if(!seen.has(full)){seen.add(full); S.rankedUrls.push(full); n++;}}); if(n===0){dup++; if(dup>=2){end=true; break;}} else dup=0; p++; await sleep(220); } S.rankedUrls=S.rankedUrls.map(url=>{const m=url.match(new RegExp(`/${S.stateSlug}/districts/([^/]+)/`)); const slug=m?m[1]:null; return {url,district:(slug&&S.districtMap[slug])?S.districtMap[slug]:(slug?slug.replace(/-/g,' '):null)};}); return JSON.stringify({rankedCount:S.rankedUrls.length,pagesScanned:scanned,endReached:end}); };
S.getStats = () => { const r=S.results; const ranks=r.map(x=>x.state_rank).filter(x=>x!=null).sort((a,b)=>a-b); const present=new Set(ranks); const maxR=ranks.length?ranks[ranks.length-1]:0; const missing=[]; for(let i=1;i<=maxR;i++) if(!present.has(i)) missing.push(i); const urls=r.map(x=>x.source_url); const dupUrls=urls.length-new Set(urls).size; const pf=['ap_taken_pct','ap_passed_pct','math_proficiency','reading_proficiency','science_proficiency','graduation_rate']; let badPct=0; r.forEach(x=>pf.forEach(f=>{const v=x[f]; if(v!=null&&(!Number.isInteger(v)||v<0||v>100)) badPct++;})); return JSON.stringify({total:r.length, rankedStateRank:ranks.length, maxStateRank:maxR, missingRanksCount:missing.length, missingRanksSample:missing.slice(0,25), dupRanks:ranks.length-present.size, nationalRanked:r.filter(x=>x.national_rank!=null).length, withScore:r.filter(x=>x.overall_score!=null).length, dupUrls, badPct, noName:r.filter(x=>!x.school_name).length}); };
S.buildFile = () => { const lines=S.results.map(r=>'  '+JSON.stringify(r)); S.fileContent='[\n'+lines.join(',\n')+'\n]\n'; return JSON.stringify({count:S.results.length, fileLen:S.fileContent.length}); };
S.download = (filename) => { const blob=new Blob([S.fileContent],{type:'application/json'}); const a=document.createElement('a'); a.href=URL.createObjectURL(blob); a.download=filename; document.body.appendChild(a); a.click(); setTimeout(()=>{URL.revokeObjectURL(a.href); a.remove();},2000); return 'download '+filename; };
S.scrapeStateBg = async (slug,name) => {
  S.init(slug,name);
  const bg=S.bg={slug,phase:'init',done:false,err:null,districts:0,schoolUrls:0,results:0,failedSchools:0,zeroDistricts:0,failedDistricts:0,ranked:0,orphansAdded:0,cooldowns:0};
  try{
    await S.loadDistricts(); bg.districts=S.districts.length; bg.phase='districts';
    for(let i=0;i<S.districts.length;i+=DIS_BATCH){ const b=await S.fetchDistrictBatch(i,DIS_BATCH); bg.schoolUrls=S.schoolUrls.length; bg.phase='districts '+Math.min(i+DIS_BATCH,S.districts.length)+'/'+S.districts.length; if(b>=DIS_BLOCK){bg.cooldowns++; bg.phase='cooldown-d'; await sleep(COOL);} await sleep(DIS_SLEEP); }
    let dg=0; while(S.failedDistrictObjs.length && dg++<6){ const b=await S.retryDistricts(); if(b>=3){bg.cooldowns++; await sleep(COOL);} else await sleep(1000); }
    bg.failedDistricts=S.failedDistrictObjs.length; bg.zeroDistricts=S.zeroDistricts.length;
    bg.phase='ranked-list'; await S.enumerateRanked(); bg.ranked=S.rankedUrls.length;
    let add=0; S.rankedUrls.forEach(it=>{ if(!S.seenUrls.has(it.url)){ S.seenUrls.add(it.url); S.schoolUrls.push(it); add++; } });
    bg.orphansAdded=add; bg.schoolUrls=S.schoolUrls.length;
    bg.phase='schools';
    for(let i=0;i<S.schoolUrls.length;i+=SCH_BATCH){ const f=await S.fetchSchoolBatch(i,SCH_BATCH); bg.results=S.results.length; bg.failedSchools=S.failedSchools.length; bg.phase='schools '+S.results.length+'/'+S.schoolUrls.length; if(f>=SCH_BLOCK){bg.cooldowns++; bg.phase='cooldown-s '+S.results.length+'/'+S.schoolUrls.length; await sleep(COOL);} await sleep(SCH_SLEEP); }
    let sg=0; while(S.failedSchools.length && sg++<15){ const b=await S.retryFailed(); bg.results=S.results.length; bg.failedSchools=S.failedSchools.length; if(b>=3){bg.cooldowns++; await sleep(COOL);} else await sleep(1000); }
    S.buildFile(); bg.fileLen=S.fileContent.length; bg.stats=JSON.parse(S.getStats());
    S.download(slug+'_high_schools.json'); bg.phase='done'; bg.done=true;
  }catch(e){ bg.err=String(e)+' @'+bg.phase; bg.phase='error'; bg.done=true; }
  return 'done';
};
return 'harness v3 (XHR+gentle+district-pagination): '+Object.keys(S).filter(k=>typeof S[k]==='function').length+' fns';
})()
