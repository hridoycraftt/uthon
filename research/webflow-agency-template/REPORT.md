# রেফারেন্স অ্যানালাইসিস: quangdinh.im → Webflow ক্রিয়েটিভ এজেন্সি টেমপ্লেট

তারিখ: ১১ নভেম্বর ২০২৬ · রেফারেন্স: https://www.quangdinh.im/ ("Better Call Quang")

---

## ১. এক নজরে (TL;DR)

- **রেফারেন্স সাইটটা Webflow দিয়ে বানানো না।** এটা **Next.js (React)** অ্যাপ। পুরো অভিজ্ঞতাটা একটা **Three.js / WebGL ক্যানভাসে** চলে। এতে 3D মডেল (GLB + Draco), নিজস্ব GLSL শেডার, Houdini দিয়ে বানানো কাপড়ের (পর্দার) সিমুলেশন, সাউন্ড আর নিজস্ব স্ক্রল ইঞ্জিন আছে। GSAP আছে, কিন্তু মূলত টাইমলাইন চালানোর জন্য।
- **কনসেপ্ট:** "লেট-নাইট টিভি শো / ইনফোমার্শিয়াল"। একটা রেট্রো CRT টিভির পর্দায় শোরিল চলে, স্টেজের পর্দা খোলে, মেনুটা একটা 3D টিভি রিমোট। লেখাগুলো ক্রোম ঝকঝকে স্ক্রিপ্ট টাইপোগ্রাফি, ব্যাকগ্রাউন্ডে সানবার্স্ট রে, আর অ্যাওয়ার্ডগুলো ভিনটেজ পোস্টারের মতো। ফুটারে লেখা "1-800-DESIGN-NOW"।
- **এর হুবহু কপি Webflow মার্কেটপ্লেস টেমপ্লেটে করা যাবে না।** টেমপ্লেটে কাস্টম কোড চলে শুধু **GSAP** (আর SVG); Three.js, শেডার, Lenis বা অন্য কোনো থার্ড-পার্টি স্ক্রিপ্ট চলবে না।
- **তবে "ফিলটা" প্রায় ৮০–৯০% পর্যন্ত আনা যায়।** উপায় হলো Webflow-এর নেটিভ **Interactions with GSAP** (SplitText, স্ক্রল স্ক্রাব, স্ট্যাগার), CSS sticky, আর অল্প কিছু GSAP কাস্টম কোড (কার্সর, ম্যাগনেটিক বাটন, মার্কি)। 3D দরকার হলে Webflow-এর নেটিভ Spline এলিমেন্ট আছে (দেখুন §৫)।
- আপনার কথামতো **সাউন্ড বাদ।** এতে লোডার "ক্লিক করে ঢুকুন" স্টেপটাও বাদ যায়, আর টেমপ্লেটও হালকা হয়।
- সাথে দিলাম একটা **ওয়্যারফ্রেম** (প্লেসহোল্ডার দিয়ে, আসল GSAP মোশনসহ), আর প্রতিটা সেকশনের **ডেস্কটপ + মোবাইল স্ক্রিনশট**।

---

## ২. কীভাবে বিশ্লেষণ করেছি (আর কোথায় সীমা ছিল)

যা সরাসরি যাচাই করেছি:
- সাইটের HTML, সব JS বান্ডেল (~২ MB) আর CSS নামিয়ে লাইব্রেরি, শেডার আর ফিচারের নাম খুঁজেছি।
- পেজের ভেতরে থাকা CMS ডেটা (প্রজেক্ট, সার্ভিস, অ্যাওয়ার্ড, কপি) বের করেছি।
- হেডলেস Chromium-এ লোড করে **নেটওয়ার্ক রিকোয়েস্ট** রেকর্ড করেছি। তাতে কোন 3D মডেল, টেক্সচার, ভিডিও আর ফন্ট লোড হয় তা দেখা গেছে।
- মূল ইমেজ অ্যাসেটগুলো নামিয়ে আর্ট ডিরেকশন দেখেছি।

সীমাবদ্ধতা:
- আমার হেডলেস ব্রাউজারে (GPU ছাড়া) সাইটটা **"99%" লোডারে আটকে থাকে**, তাই লাইভ স্ক্রল-অ্যানিমেশন নিজের চোখে দেখতে পারিনি। শোরিলকে WebM বানিয়ে দেওয়ার পরও খোলেনি। তাই নিচের "কোন সেকশনে কী মুভ করে" অংশটা **কোড + অ্যাসেট থেকে অনুমান**। এগুলো "অনুমান" লিখে চিহ্নিত করেছি।
- Webflow-এর অফিশিয়াল submission-guidelines পেজটা জাভাস্ক্রিপ্ট দিয়ে লোড হয়, তাই সরাসরি পড়তে পারিনি। নিয়মগুলো সার্চ রেজাল্ট থেকে নেওয়া (সোর্স নিচে)। **সাবমিট করার আগে লাইভ পেজে একবার মিলিয়ে নেবেন।**

---

## ৩. রেফারেন্সের টেক স্ট্যাক (যাচাই করা)

| জিনিস | যা পেয়েছি |
|---|---|
| ফ্রেমওয়ার্ক | Next.js App Router (`/_next/static/...`, RSC payload), CSS Modules |
| 3D | Three.js + React Three Fiber, `GLTFLoader` + `DRACOLoader`, Raycaster (3D অবজেক্টে হোভার/ক্লিক), Matcap ও Physical ম্যাটেরিয়াল, Instanced মেশ |
| 3D অ্যাসেট | `tivi_clean.glb` (CRT টিভি), `FULL_ALPHABET.glb` / `FULL_ALPHABET_V2.glb` (3D অক্ষর), `Menu_v2.glb` (রিমোট কন্ট্রোল মেনু), `curtain_v3_q12.bin/.json` (Houdini **VAT** দিয়ে বানানো স্টেজ-পর্দার সিমুলেশন), `hd.webp` (এনভায়রনমেন্ট ম্যাপ), AO টেক্সচার |
| শেডার (GLSL) | Halftone (`uDotSize`, `uToneLevels`), scanline, glitch, noise, speed-lines (`u_phaseProgress`), bloom/vignette ধরনের পোস্ট-ইফেক্ট। টিভির পর্দায় শোরিল চলে **halftone শেডারের ভেতর দিয়ে** |
| ভিডিও | `showreel.mp4` (640×480, ২২ সেকেন্ড, H.264): টিভির পর্দার টেক্সচার হিসেবে চলে |
| মোশন | GSAP 3 (টাইমলাইন, stagger, `expo` easing অনেক বেশি), ScrollTrigger খুব অল্প জায়গায়; নিজস্ব wheel/touch স্ক্রল + `lerp` স্মুদিং (ভার্চুয়াল স্ক্রল, পেজ ~৩৩,০০০px উঁচু) |
| সাউন্ড | `AudioContext`, সাউন্ড অন/অফ বাটন |
| ফন্ট | **Fraunces 72pt Wonky Bold Italic** (সেরিফ ইটালিক), **Overused Grotesk** (সানস), "Visual" (ডিসপ্লে) |
| CMS | নিজস্ব JSON CMS (`/cms/uploads/...`): projects, playground, awards, services, howIWork, trusted, menu |
| অ্যাক্সেসিবিলিটি | `prefers-reduced-motion`-এর কোনো হ্যান্ডলিং পাইনি; viewport-এ `user-scalable=no` (জুম বন্ধ)। এই দুটো আমাদের টেমপ্লেটে **নকল করব না** |

---

## ৪. সেকশন ধরে ধরে ব্রেকডাউন

| # | সেকশন | রেফারেন্সে কী আছে | কীভাবে করেছে |
|---|---|---|---|
| 0 | লোডার | কাউন্টার 0→100% (সব 3D/ভিডিও লোড হওয়া পর্যন্ত) | React state, অ্যাসেট লোডিং প্রোগ্রেস |
| 1 | ইন্ট্রো / হিরো | "QUANG DINH — Present", "Scroll to the Program"। স্টেজের পর্দা খোলে, CRT টিভিতে শোরিল চলে, পেছনে সানবার্স্ট রে ঘোরে *(অনুমান: স্ক্রলে ক্যামেরা টিভির দিকে এগোয়)* | Three.js দৃশ্য + VAT পর্দা + halftone শেডার + ঘুরন্ত রে টেক্সচার |
| 2 | মেনু | একটা 3D টিভি রিমোট। বাটনে চাপ দিয়ে সেকশন বদলায়, সাউন্ড অন/অফ, prev/next | GLB মডেল + Raycaster ক্লিক |
| 3 | About | "ABOUT ME" (3D ক্রোম অক্ষর), "Quang Dinh" স্ক্রিপ্ট, পপ-আর্ট পোর্ট্রেট, কোট | 3D অক্ষর মডেল + ইমেজ প্লেন |
| 4 | Works | ৮টা প্রজেক্ট (CMS: title, sub, gallery ৭–১৪ ছবি, year, type, role, deliverables, awards); prev/next অ্যারো *(অনুমান: চ্যানেল বদলানোর মতো ট্রানজিশন, glitch/speed-line)*; আলাদা `/works` রুট | WebGL প্লেন + glitch শেডার |
| 5 | Service | নীল ডিম্বাকৃতি ব্যাজে ক্রোম "Service" লেখা। ৩টা বড় শব্দ BRANDING / WEBSITE / PRODUCT, প্রতিটার সাথে ছবি | DOM + ইমেজ |
| 6 | How I Work | ক্রোম স্ক্রিপ্টে "How I Work", ৪টা ধাপ (01–04), হোভারে ডিম্বাকৃতি আর তারা (sparkle) আইকন আসে | DOM + CSS হোভার (এই অংশটা সার্ভার থেকে HTML হিসেবেই আসে) |
| 7 | Playground | ৩২টা ছবি (1:1 আর 4:3) | WebGL গ্যালারি *(অনুমান)* |
| 8 | Awards | ৫টা রেট্রো পোস্টার কার্ড (সানবার্স্ট, 3D ক্রোম ব্যাজ, স্ক্যানলাইন টেক্সচার, "SOTD ×01") | ইমেজ (পোস্টারগুলো আগে থেকে রেন্ডার করা) |
| 9 | Trusted by | কোম্পানির নামের লিস্ট | DOM |
| 10 | কন্টাক্ট / ফুটার | "LET'S WORK TOGETHER", "1-800-DESIGN-NOW", টিভি ফ্রেমের ভেতর অ্যাভাটার, "NO TEMPLATES — CUSTOM DESIGN ONLY", ইমেইল | DOM (সার্ভার-রেন্ডারড) |

**কেন এটা প্রিমিয়াম লাগে:** একটা পরিষ্কার থিম (টিভি শো) পুরো সাইটে ধারাবাহিকভাবে চলে, আর শেডার, ফন্ট আর পোস্টার সবই সেই থিমের সাথে মেলে। টাইপোগ্রাফির কনট্রাস্টও জোরালো (ক্রোম স্ক্রিপ্ট বনাম মোটা গ্রোটেস্ক)। প্রতিটা ইন্টারঅ্যাকশন একটা "জিনিসের" মতো আচরণ করে (রিমোটের বাটন, টিভির চ্যানেল)। শুধু ফেড-ইন দিয়ে এই অনুভূতি আসে না।

---

## ৫. Webflow মার্কেটপ্লেস টেমপ্লেটের নিয়ম ও সীমাবদ্ধতা

সার্চ রেজাল্ট থেকে পাওয়া (লাইভ পেজে মিলিয়ে নেবেন):

1. **কাস্টম কোড নিষেধ।** ব্যতিক্রম শুধু **GSAP কাস্টম কোড**, **SVG** আর Webflow-এর validator স্নিপেট।
2. GSAP কোড ব্যবহার করলে **Instructions পেজে "How to Edit GSAP Animations"** নামে একটা সেকশন লাগবে। সেখানে কোন সিলেক্টরে কী অ্যানিমেশন আছে আর কীভাবে বন্ধ করা যায় তা লিখতে হবে। Webflow-এর নিজের GSAP Interactions-এর জন্য এটা লাগে না।
3. **১ মে ২০২৬ থেকে Webflow Interactions (GSAP-চালিত) টেমপ্লেটের ডিফল্ট।** পুরোনো (legacy/Classic) ইন্টারঅ্যাকশন এড়িয়ে চলতে হবে। এলিমেন্ট লুকাতে display/opacity না দিয়ে **Initial Appearance** ব্যবহার করতে হবে।
4. ফুটারে **"Powered by Webflow"** লিংক, SEO title-এর নির্দিষ্ট প্যাটার্ন, আর কোয়ালিটি রুব্রিকের প্রতিটা অংশে অন্তত "Good" স্কোর লাগবে। নতুন ক্রিয়েটর একবারে একটাই টেমপ্লেট জমা দিতে পারে।
5. ইউটিলিটি পেজ: Style Guide, Licenses, Instructions, Changelog, 404, Password।

**এর মানে কী:**

| চাওয়া | টেমপ্লেটে চলবে? | বিকল্প |
|---|---|---|
| Three.js / নিজস্ব শেডার | ❌ | Spline নেটিভ এলিমেন্ট, বা আগে থেকে রেন্ডার করা ভিডিও/ইমেজ |
| Lenis / Locomotive স্মুথ স্ক্রল | ❌ (থার্ড-পার্টি) | GSAP **ScrollSmoother** (GSAP প্লাগইন, এখন ফ্রি) চলবে। তবে স্ক্রল-জ্যাকিংয়ে UX আর পারফরম্যান্স খারাপ হয়, তাই **নেটিভ স্ক্রলই রাখার পরামর্শ** |
| Barba/Swup পেজ ট্রানজিশন | ❌ | পেজ লোড আর লিংক ক্লিকের Interactions দিয়ে "কার্টেন" ট্রানজিশন |
| সাউন্ড | — (আপনি বাদ দিয়েছেন) | — |
| লোডার শুধু প্রথম ভিজিটে (sessionStorage) | ⚠️ এটা GSAP না, সাধারণ JS | লোডার ছোট রাখুন (≤১.৬ সেকেন্ড), প্রতিবার চলুক; বা শুধু Home পেজে |
| লাইভ ঘড়ি / ইমেইল কপি / JS ফিল্টার | ⚠️ সাধারণ JS | স্ট্যাটিক টেক্সট, `mailto:`, CMS-এর Category পেজ |
| Finsweet (CMS Filter/Load more) | ⚠️ থার্ড-পার্টি, ঝুঁকি আছে | Webflow-এর নেটিভ pagination আর Category Collection পেজ |

---

## ৬. GSAP: Webflow নেটিভ নাকি কাস্টম কোড?

GSAP এখন **১০০% ফ্রি**, SplitText, ScrollTrigger, Flip, ScrollSmoother সহ সব প্লাগইন। Webflow নিজেই GSAP 3.15 হোস্ট করে।

**Webflow-এর নেটিভ Interactions (GSAP) দিয়েই যা হবে, কোড লাগবে না:**
- পেজ লোড ইন্ট্রো, **SplitText** (লাইন/শব্দ/অক্ষর ধরে রিভিল), stagger
- **Scroll scrub**: স্ক্রলের সাথে scale, x/y, rotate, opacity, clip-path, border-radius
- হোভার/ক্লিক ইন্টারঅ্যাকশন, অ্যাকর্ডিয়ন, মেনু খোলা/বন্ধ
- **CSS `position: sticky` + scrub** মিলিয়ে পিন করা সেকশন: স্ট্যাকড কার্ড, হরাইজন্টাল স্ক্রল, শোরিল বড় হওয়া। ScrollTrigger-এর pin না নিয়ে sticky ব্যবহার করলে Webflow-এ বেশি স্থিতিশীল থাকে
- ব্রেকপয়েন্ট ধরে আলাদা অ্যানিমেশন (মোবাইলে সহজ ভার্সন)

**GSAP কাস্টম কোড লাগবে (টেমপ্লেটে চলবে, Instructions পেজে ডকুমেন্ট করতে হবে):**
- কার্সর ফলোয়ার ("View" বাবল), হোভারে ছবি কার্সরের পেছনে চলা (`gsap.quickTo`)
- ম্যাগনেটিক বাটন
- স্ক্রলের গতি অনুযায়ী মার্কির স্পিড বদলানো (`ScrollTrigger.getVelocity`)
- নম্বর গোনা (counter)
- `gsap.matchMedia()` দিয়ে reduced-motion আর টাচ ডিভাইসে বন্ধ রাখা

**"রেডিমেড GSAP"-এর অবস্থা:** Webflow-এর Interactions প্যানেলে আগে থেকে বানানো preset/ease আছে, আর আপনি নিজের interaction সেভ করে আবার ব্যবহার করতে পারবেন। কিন্তু কার্সর, ম্যাগনেটিক বা ভেলোসিটি মার্কির মতো জিনিস রেডিমেড নেই। ওগুলো ছোট GSAP স্নিপেট হিসেবে আমি ওয়্যারফ্রেমে লিখে দিয়েছি (`wireframe/index.html`-এর নিচের `<script>`), Webflow-এ প্রায় হুবহু বসানো যাবে।

---

## ৭. ইফেক্ট ম্যাপ: রেফারেন্স → আমাদের টেমপ্লেট

| রেফারেন্সের ইফেক্ট | Webflow-এ সরাসরি? | আমাদের ভার্সন | পদ্ধতি |
|---|---|---|---|
| 3D CRT টিভিতে শোরিল (halftone শেডার) | ❌ | ছোট, গোল কোণার ফ্রেমে শোরিল; স্ক্রলে বড় হয়ে **ফুল-ব্লিড** হয় | sticky + IX scrub, নেটিভ BG ভিডিও |
| Halftone/scanline লুক | ❌ শেডার | ভিডিও/ছবিতেই লুকটা **বেক করে** দেওয়া (After Effects/Photoshop), বা একটা PNG স্ক্যানলাইন ওভারলে | ইমেজ/ভিডিও অ্যাসেট |
| স্টেজ-পর্দা (VAT সিমুলেশন) | ❌ | লোডার শেষে ৫টা কালো স্ট্রিপ উপরে সরে যায় ("কার্টেন ওয়াইপ") | IX পেজ লোড |
| 3D ক্রোম অক্ষর ("ABOUT ME") | ❌ (Spline দিয়ে সম্ভব, কিন্তু ভারী) | ক্রোম স্ক্রিপ্ট লেখা **SVG/WebP** হিসেবে (রেফারেন্সও How I Work-এ এটাই করেছে), বা বড় সেরিফ ইটালিক | ইমেজ / টাইপোগ্রাফি |
| 3D রিমোট মেনু | ❌ | ফুল-স্ক্রিন মেনু: বড় লিংক, হোভারে প্রিভিউ ছবি, ক্লিপ-পাথ দিয়ে খোলে | IX ক্লিক |
| ঘুরন্ত সানবার্স্ট রে | ✅ | SVG + ধীরে ঘোরা (CSS animation বা IX loop) | নেটিভ |
| চ্যানেল বদলানো (glitch ট্রানজিশন) | ❌ | প্রজেক্ট কার্ড sticky স্ট্যাক; নিচের কার্ড ছোট আর গাঢ় হয়ে যায় | sticky + IX scrub |
| স্পার্কল/তারার হোভার | ✅ | স্টার SVG স্ক্রলে ঘোরে, হোভারে স্কেল হয় | IX |
| পোস্টার অ্যাওয়ার্ড কার্ড | ✅ | ৫টা পোস্টার প্রথমে এক গাদায় থাকে, স্ক্রলে পাখার মতো ছড়িয়ে যায় | sticky + IX scrub |
| ক্রোম স্ক্রিপ্ট + গ্রোটেস্ক কনট্রাস্ট | ✅ | Inter Tight 800 + Instrument Serif ইটালিক (দুটোই Google Fonts, লাইসেন্স সহজ) | নেটিভ ফন্ট |
| সাউন্ড | — | বাদ | — |

---

## ৮. ওয়্যারফ্রেম: সেকশন প্ল্যান

**ডিরেকশন (একটাই):** *"Showtime Editorial"*। রেফারেন্সের রেট্রো-শো এনার্জি (সানবার্স্ট, স্পার্কল, পোস্টার, বড় সাহসী টাইপ) রাখছি, কিন্তু পুরোটা DOM + GSAP-এ বানাচ্ছি। এতে Webflow-এ বানানো যায়, ক্লায়েন্ট সহজে এডিট করতে পারে, আর পেজ দ্রুত লোড হয়। কোনো লোগো, কপি বা ছবি রেফারেন্স থেকে নেওয়া হয়নি।

| # | সেকশন | লেআউট | মোশন / মাইক্রো-ইন্টারঅ্যাকশন | Webflow পদ্ধতি |
|---|---|---|---|---|
| 00 | Preloader | ফুল-স্ক্রিন কালো, নিচে বড় কাউন্টার | 000→100 গোনে, তারপর ৫টা স্ট্রিপ উপরে সরে যায় | IX পেজ লোড (+ কাউন্টারের জন্য GSAP কোড) |
| 01 | Nav + Menu | লোগো, ৪টা লিংক, Menu বাটন; nav-এ `mix-blend-mode: difference` | লিংক হোভারে টেক্সট রোল করে; মেনু clip-path দিয়ে খোলে, লিংক stagger করে, হোভারে প্রিভিউ ছবি | IX হোভার/ক্লিক |
| 02 | Hero | ৩ লাইনের বিশাল হেডলাইন, মাঝে ভিডিও "পিল", সেরিফ ইটালিক অ্যাকসেন্ট, স্পার্কল; পেছনে সানবার্স্ট | লাইনগুলো নিচ থেকে উঠে আসে (SplitText), রে ধীরে ঘোরে | IX SplitText |
| 03 | Showreel | sticky ফ্রেম | ৪২% সাইজ থেকে স্ক্রলের সাথে ফুল-ব্লিড হয়, কোণ গোল থেকে সোজা হয়; প্লে বাটন ম্যাগনেটিক | sticky + scrub; GSAP কোড |
| 04 | Statement / About | ১২-কলাম গ্রিড, বড় প্যারাগ্রাফের ভেতরে ছবির চিপ, ৩টা স্ট্যাট | শব্দগুলো স্ক্রলে ১৫% থেকে ১০০% উজ্জ্বল হয়; নম্বর গোনে | IX SplitText words + scrub |
| 05 | Selected Work (CMS) | ডার্ক; ৪টা বড় কার্ড (তথ্য বাম দিকে, কভার ডানে) | কার্ডগুলো sticky স্ট্যাক হয়, আগের কার্ড ছোট আর গাঢ় হয়; "View" কার্সর বাবল; হোভারে কভার ১.০৩× জুম | sticky + scrub; GSAP কার্সর |
| 06 | Project Index (CMS) | টেবিলের মতো সারি (নাম, টাইপ, রোল, সাল) + ফিল্টার পিল | হোভারে সারি নিচ থেকে ভরে যায়, নাম ডানে সরে, কার্সরের সাথে ছবি চলে | CSS হোভার; GSAP quickTo |
| 07 | Services | ৩টা বিশাল শব্দ, অ্যাকর্ডিয়ন | হোভারে শব্দের **ভেতরে** একটা ছবির পিল খোলে; ক্লিকে ডেলিভারেবল লিস্ট খোলে, "+" ঘুরে "×" হয় | IX হোভার/ক্লিক |
| 08 | Process | ইন্ট্রো + ৪টা কার্ড, নিচে প্রোগ্রেস বার | সেকশন পিন থাকে, কার্ডগুলো পাশের দিকে সরে, তারা ঘোরে; ট্যাবলেট/মোবাইলে উপর-নিচের স্ট্যাক | sticky + scrub (x) |
| 09 | Playground | দুই সারি ছবি (1:1 আর 4:3) | দুই সারি উল্টো দিকে লুপ করে, স্ক্রলের গতিতে স্পিড বাড়ে, হোভারে থামে | GSAP কোড |
| 10 | Awards | ডার্ক, ৫টা পোস্টার | এক গাদা থেকে পাখার মতো ছড়ায়, হোভারে কার্ড উঠে আসে; মোবাইলে ২-কলাম গ্রিড | sticky + scrub; CMS |
| 11 | Testimonial | বড় সেরিফ কোট, অ্যাভাটার, prev/next | লাইন-বাই-লাইন মাস্ক রিভিল; বাটন চাপলে একটু ছোট হয় | Slider / IX |
| 12 | Client logos | লোগো স্ট্রিপ | ধীর মার্কি | GSAP / CSS |
| 13 | CTA | বিশাল "Let's make *something* loud", গোল কমলা বাটন | লাইন রিভিল, ম্যাগনেটিক বাটন | IX + GSAP কোড |
| 14 | Footer | কলাম + বিশাল ওয়ার্ডমার্ক + "Powered by Webflow" | পেজের নিচ থেকে "পর্দার মতো" বেরিয়ে আসে | CSS sticky |

**মোবাইল নিয়ম:** হরাইজন্টাল পিন বন্ধ করে উপর-নিচের স্ট্যাক; অ্যাওয়ার্ড ২-কলাম গ্রিডে; কার্সর আর ইমেজ-ফলো টাচ ডিভাইসে বন্ধ; বাটন আর লিংক অন্তত ৪৪px উঁচু।
**Reduced motion:** সব অ্যানিমেশন বন্ধ থাকে, কিন্তু কোনো কনটেন্ট লুকানো থাকে না (`gsap.matchMedia`)।

### টেমপ্লেটের পেজ ও CMS (প্রস্তাব)
- পেজ: Home, Work (CMS list + Category পেজ), Project (CMS template), About/Studio, Services, Contact, Playground (ঐচ্ছিক), Blog + Blog post (ঐচ্ছিক, মার্কেটপ্লেসে বিক্রির জন্য ভালো), আর ইউটিলিটি পেজ: Style Guide, Instructions (GSAP সেকশনসহ), Licenses, Changelog, 404, Password।
- CMS Collections: **Projects** (title, slug, summary, cover, cover video URL, gallery, year, category ref, role, deliverables, featured toggle, awards), **Categories**, **Awards** (poster, platform, count), **Testimonials**, (ঐচ্ছিক) **Team**, **Blog**।

---

## ৯. পরের ধাপ

1. ওয়্যারফ্রেম আর স্ক্রিনশট দেখে সেকশনের অর্ডার/লেআউট অনুমোদন দিন, বা কী বদলাতে হবে বলুন।
2. এরপর হাই-ফিডেলিটি ডিজাইন: রং, ব্র্যান্ড নাম, আসল ফটোগ্রাফি/শোরিল, ক্রোম স্ক্রিপ্ট অ্যাসেট।
3. Webflow বিল্ড: Variables (রং/স্পেসিং/টাইপ), Client-First বা নিজস্ব ক্লাস নেমিং, CMS সেটআপ, নেটিভ GSAP Interactions, তারপর অল্প GSAP কোড আর Instructions পেজ।
4. সাবমিশনের আগে: লাইভ guidelines পেজ মিলিয়ে নেওয়া, Lighthouse, মোবাইলে টেস্ট, আর reduced-motion চেক।

---

## ১০. কী টেস্ট করেছি, কী করিনি

**টেস্ট করেছি:**
- ওয়্যারফ্রেম 1440px আর 390px-এ খোলে, কোথাও আড়াআড়ি স্ক্রল নেই, কনসোলে কোনো এরর নেই।
- মোশন মোডে (লোডার, হিরো, রিল স্কেল, কার্ড স্ট্যাক, হরাইজন্টাল প্রসেস, অ্যাওয়ার্ড ফ্যান, ফুটার রিভিল) স্ক্রিনশট নিয়ে দেখেছি।
- Reduced-motion মোডে সব কনটেন্ট দেখা যায়।
- লেখার কনট্রাস্ট ঠিক আছে (কালির রং কাগজের রঙের উপর, কাগজের রং ডার্কের উপর)।

**টেস্ট করিনি:**
- আসল ফোন বা Safari।
- Lighthouse পারফরম্যান্স (প্লেসহোল্ডার পেজে এর মানে হয় না)।
- রেফারেন্স সাইটের লাইভ স্ক্রল-কোরিওগ্রাফি (GPU ছাড়া লোড হয়নি)।
- Webflow-এর লাইভ guidelines পেজ।

---

## সোর্স
- [Webflow — Submission Guidelines](https://webflow.com/templates/submission-guidelines)
- [Webflow Forum — Custom code in template submission](https://discourse.webflow.com/t/inquiry-about-custom-code-in-template-submission/278202)
- [Webflow Forum — Custom attributes in templates](https://discourse.webflow.com/t/submission-guidelines-custom-attributes-are-custom-attributes-in-template-submissions-allowed/260165)
- [Webflow Forum — Finsweet components in template submission](https://discourse.webflow.com/t/inquiry-about-finsweet-components-in-template-submission/318404)
- [GitHub PR — validator: GSAP without Instructions](https://github.com/createsomethingtoday/create-something-monorepo/pull/2209)
- [Bryn Taylor — How to Sell Webflow Templates in 2026](https://www.bryntaylor.co.uk/writing/selling-webflow-templates)
- [Webflow Template Submission Checklist (PDF)](https://cdn.prod.website-files.com/5e593fb060cf87bbaf75dd20/65df9aeae03d45d5a4194bc3_Webflow%20Template%20Submission%20Checklist.pdf)
- [Webflow Help — Interactions with GSAP vs Classic](https://help.webflow.com/hc/en-us/articles/46300264646803-Interactions-with-GSAP-vs-Classic-Interactions)
- [Webflow — Introducing Interactions powered by GSAP](https://webflow.com/updates/introducing-webflow-interactions-powered-by-gsap)
- [Webflow Blog — GSAP becomes free](https://webflow.com/blog/gsap-becomes-free)
- [Webflow Forum — ScrollTrigger doesn't play when visible on load](https://discourse.webflow.com/t/gsap-scroll-trigger-doesn-t-play-when-element-is-already-visible-on-page-load/331071)
- [Codrops — Combining GSAP and Webflow (2026)](https://tympanus.net/codrops/2026/01/14/a-site-for-sore-eyes-combining-gsap-and-webflow-to-showcase-flim/)
- [GSAP — Webflow resources](https://gsap.com/resources/Webflow/)
