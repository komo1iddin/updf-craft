# UPDF Craft — AppKit'da native PDF muharriri: reja

Asos: [UPDF_APP_ARCHITECTURE.md](UPDF_APP_ARCHITECTURE.md) (butun ilova) va
[UPDF_EDIT_ENGINE.md](../updf-reverse-engineering/UPDF_EDIT_ENGINE.md) (matn tahriri engine'i).
Sana: 2026-10-16.

---

## 0. Avval: chegaralar

- **UPDF'dan hech narsa ko'chirilmaydi**: kod, binar, resurs (`Assets.car`, shtamplar,
  shablonlar), matnlar, ikonalar, nomlar va brend. UPDFKit, ABBYY va SolidFramework yopiq
  kommersiya kutubxonalari — ularni ishlatish yoki link qilish mumkin emas.
- Tahlildan olinadigan narsa — **arxitektura g'oyalari va foydalanuvchiga ko'rinadigan
  xatti-harakat** (masalan: "engine undo handle qaytaradi", "sahifa tile'lab chiziladi",
  "paragraf tahrirda qayta oqadi"). Algoritmlar ISO 32000, Unicode standartlari va o'z
  sinovlarimiz asosida qayta yoziladi. Disassembly'dan olingan aniq konstantalar va
  formulalar to'g'ridan-to'g'ri ko'chirilmaydi.
- Agar loyiha PdfCraft engine'idan foydalansa, uning clean-room qoidasi
  ([PDFCRAFT_REVIEW.md §0](../updf-reverse-engineering/PDFCRAFT_REVIEW.md)) ham amal qiladi.

---

## 1. Maqsad

macOS uchun to'liq native PDF muharriri: AppKit qobiq + o'z PDF engine qatlami.
Funksiyalar doirasi UPDF'ning asosiy qismi: o'qish, izohlar, sahifalarni tartiblash, formalar,
**matnni haqiqiy tahrirlash (reflow bilan)**, himoya va imzo, OCR, siqish, bezaklar,
konvertatsiya va AI.

UPDF'dan ustun bo'lish mumkin bo'lgan joylar (edit engine hujjati §1.2 va retsept §11):
virtual bo'shliq va defis, UAX #14 satr bo'lish, justify'ni `Tw`/`TJ` bilan yozish,
burilgan blok chegarasi, bold variantda kenglikni yangilash, font subset'ni qayta ishlatish,
vertikal yozuvni undo'da saqlash.

---

## 2. Asosiy qarorlar

| Savol | Qaror | Sabab |
|---|---|---|
| PDF engine | **PDFium**'ni manbadan yig'ish (fork) + o'z C++ qatlami `CraftCore` | BSD/Apache litsenziya; render, annotatsiya, forma, matn ajratish tayyor; ichki C++ (`CPDF_PageObject`, `CPDF_TextObject`, `CPDF_PageContentGenerator`) tahrir engine'i uchun ochiq. UPDF ham aynan shu yo'ldan borgan |
| Shifrlash, linearize, optimize | **qpdf** (Apache-2.0) | PDFium saqlashda yangi shifrlash qo'ya olmaydi |
| Raqamli imzo | Apple **Security** (`SecIdentity`, `CMSEncoder`) + o'z ByteRange/incremental save | qo'shimcha kriptografik kutubxonasiz; kerak bo'lsa keyin OpenSSL |
| Shaping, font subset | **HarfBuzz** (`hb-subset`) + CoreText | PDFium FreeType'ni allaqachon olib keladi |
| OCR | Apple **Vision** (`VNRecognizeTextRequest`) | bepul, oflayn, 20+ til; ko'rinmas matn qatlami (`3 Tr`) |
| Office → PDF | `NSAttributedString` (docx/rtf/html o'qiydi) + `NSPrintOperation` → PDF; Pages/Word bo'lsa Apple Events | qo'shimcha engine'siz |
| PDF → Office | kech bosqich; avval rasm/matn/HTML, keyin o'z DOCX yozuvchisi | og'ir va ixtiyoriy |
| UI | **AppKit** (qobiq, PDF view, inspector'lar), SwiftUI faqat Settings kabi oddiy oynalarda | PDF canvas va matn kiritish (`NSTextInputClient`) faqat AppKit'da to'liq nazorat qilinadi |
| Til | Swift 6 (strict concurrency), engine C++20, ko'prik ObjC++ yoki Swift C++ interop | |
| Minimal macOS | **14 Sonoma** | `@Observable`, zamonaviy AppKit API'lari |
| Tarqatish | Developer ID + notarization + Sparkle (UPDF kabi). Keyinchalik App Store uchun sandbox varianti | |
| Engine bo'lmagan muqobillar | PDFKit — faqat zaxira/print uchun; MuPDF — AGPL, yopiq ilovaga mos emas; PdfCraft (Rust) — litsenziya va clean-room tekshirilgandan keyin variant | |

---

## 3. Arxitektura

```
┌───────────────────────────── UPDFCraft.app (AppKit) ─────────────────────────────┐
│ AppDelegate · DocumentController · WindowController(Tabs) · Menus/Commands        │
│ EditorViewController                                                              │
│   Toolbar + ModeBar + ToolPalette │ Sidebar(Navigators) │ CanvasView │ Inspector  │
│   CanvasView (NSScrollView) → PageView (tile layers) → Overlays(per mode)          │
│     ReadOverlay · AnnotateOverlay · EditOverlay · FormOverlay · RedactOverlay      │
├──────────────────────────── CraftKit (Swift package) ────────────────────────────┤
│ PDFDocumentModel · PageModel · Annotation/FormField/TextBlock/ImageObject modellar│
│ EngineActor (barcha engine chaqiruvlari bitta serial executor'da) · RenderService │
│ UndoBridge (engine undo handle → NSUndoManager) · Services: OCR, Convert, AI      │
├──────────────────────────── CraftCore (C++ → C API) ─────────────────────────────┤
│ craftcore.h: CC_Document*, CC_Page*, CC_Annot*, CC_Field*, CC_Text*, CC_Undo*     │
│ Tahrir engine'i: TextPage → Block → Paragraph → Line → Char (o'z dizayni)         │
│ PDFium (fork) · HarfBuzz · FreeType · qpdf · (ixtiyoriy V8 — keyin)               │
└───────────────────────────────────────────────────────────────────────────────────┘
```

### 3.1 Repozitoriy tuzilmasi

```
updf-craft/
├ Engine/
│  ├ pdfium/                 # fork (git submodule), gn bilan yig'iladi
│  │  └ craftcore/           # o'z C++ kodimiz, pdfium gn daraxtidagi target
│  ├ include/craftcore.h     # yagona ommaviy C API
│  ├ scripts/build_xcframework.sh   # arm64 + x86_64 → CraftCore.xcframework
│  └ harness/                # CLI: PDF'ni ochish, amal bajarish, PNG/PDF chiqarish
├ Packages/CraftKit/         # Swift package: wrapper'lar, modellar, servislar
├ App/UPDFCraft.xcodeproj    # AppKit ilova
├ Tests/
│  ├ corpus/                 # test PDF'lar (sintetik + real)
│  └ golden/                 # kutilgan render PNG va content stream'lar
└ docs/
```

### 3.2 Engine qatlami — `CraftCore` C API

Qoidalar (UPDFKit'dagi yaxshi tomonlar):
- Faqat opaque handle'lar va POD struct'lar: `CC_DOC`, `CC_PAGE`, `CC_ANNOT`, `CC_TEXTPAGE`,
  `CC_UNDO`. Swift C++ ichki tuzilmalarni ko'rmaydi.
- Har bir o'zgartiruvchi amal `CC_UNDO` qaytaradi (yoki `NULL` = hech narsa o'zgarmadi).
  `CC_Undo_Undo / Redo / Release`.
- Xatolar `CC_GetLastError()` orqali, istisno chegaradan o'tmaydi.
- Engine thread-safe emas (PDFium global holatli) — barcha chaqiruvlar bitta serial
  executor'dan. Swift tomonda `actor EngineActor` maxsus `SerialExecutor` bilan.

API oilalari va bosqichlari:

| Oila | Ichida | Bosqich |
|---|---|---|
| `CC_Doc_*` | open (parol), save (to'liq/incremental), metadata, outline, page labels, attachments | M1 |
| `CC_Render_*` | sahifa yoki hududni BGRA bufferga, annotatsiyalar bilan/siz, forma qatlami | M1 |
| `CC_TextExtract_*` | belgi, quad, so'z/qator chegaralari, qidiruv | M1 |
| `CC_Annot_*` | yaratish, xossalar, appearance stream generatsiyasi, flatten | M2 |
| `CC_Page_*` | insert, delete, move, rotate, crop, import from doc, split, merge | M3 |
| `CC_Field_*`, `CC_Form_*` | to'ldirish (FORMFILLINFO), yaratish, xossalar, FDF/XFDF | M4 |
| `CC_Text_*` | tahrir engine'i: load, insertion point, insert/remove, style, reflow, block geometry | M5 |
| `CC_Object_*` | rasm/path: transform, crop (clip), replace, extract | M5 |
| `CC_Security_*`, `CC_Sign_*` | qpdf orqali shifrlash; imzo maydoni, ByteRange, CMS joylash, tekshirish | M6 |
| `CC_Redact_*` | matn/rasm/path'larni haqiqatan olib tashlash, overlay | M6 |
| `CC_Optimize_*`, `CC_Decor_*`, `CC_OCRLayer_*` | siqish, watermark/header/footer/Bates (marked content bilan), ko'rinmas OCR matni | M7 |

### 3.3 Ilova qatlami — asosiy klasslar

| Klass | Vazifa | UPDF'dagi o'xshashi |
|---|---|---|
| `CraftDocument : NSDocument` | fayl, autosave, versiyalar, `undoManager` | `UPDFDocument` |
| `DocumentModel` (`@Observable`) | engine handle, sahifalar, manager'lar | `Document` |
| `AnnotationStore`, `FormStore`, `OutlineStore`, `AttachmentStore` | modelning bo'laklari | `*Manager` |
| `MainWindowController` | tab'lar: avval **native `NSWindow` tabbing**, keyin kerak bo'lsa o'z tab bar | `EditorWindow` + `TabBar` |
| `EditorViewController` | toolbar, sidebar, canvas, inspector joylashuvi (`NSSplitViewController`) | `EditorViewController` |
| `CanvasScrollView : NSScrollView` | layout rejimlari, zoom, ko'rinadigan sahifalar, prefetch | `PDFScrollView` |
| `PageView : NSView` (layer-backed) | tile layer'lar + overlay'lar | `PDFPageView` + `PageView` |
| `TileRenderer` | tile kesh (LRU, xotira chegarasi), prioritetli navbat, bekor qilish | `renderQueue`, `reusableLayers` |
| `ModeController` | joriy rejim va uning overlay'i hodisa oladi | `activatedContainer` |
| `Element` protokoli + `ElementAttributes` | tanlash, surish, resize, rotate, hit-test | `Element`/`*Attributes` |
| `TextEditView : NSView, NSTextInputClient` | tahrirlanayotgan blok: klaviatura, IME, kursor, tanlov | `TextElement` |
| `InspectorViewController` | tanlangan element xossalari (attributes'ga bog'langan) | `InspectorPane` |
| `UndoBridge` | `CC_UNDO` → `NSUndoManager.registerUndo` | `UndoCommand` |

### 3.4 Render konveyeri

1. `CanvasScrollView` ko'rinadigan rect va zoom'ni beradi.
2. Har bir ko'rinadigan sahifa uchun zoom darajasi (2 ning darajalari: 0.5×, 1×, 2×, 4×…)
   va 512×512 px tile'lar hisoblanadi.
3. Avval past aniqlikdagi butun sahifa bitmap'i (tez), keyin kerakli tile'lar —
   ko'rinadigan markazdan boshlab.
4. `EngineActor` tile'ni `CC_Render_Rect` bilan BGRA bufferga chizadi → `CGImage` →
   `CALayer.contents`. Layer'lar havzadan qayta ishlatiladi.
5. **Eskirgan vazifani tashlab yuborish**: vazifa navbatdan chiqqanda zoom so'rov paytidagidek
   ekanini va tile hali ko'rinishini tekshiradi (UPDF ham shunday qiladi — arxitektura §11.2).
   Zoom o'zgarsa tile jadvali, chizilgan pozitsiyalar to'plami va layer'lar tozalanadi.
6. Tahrir paytida faqat o'zgargan sahifa/hudud yaroqsiz qilinadi; tahrirlanayotgan element
   overlay'da chiziladi, tagidagi bitmap'da u yashiriladi (render'ga "yashirin
   annotatsiyalar/obyektlar" ro'yxati beriladi).
7. **Ixtiyoriy tezkor yo'l**: tahrirlanmagan sahifani Apple PDFKit (`PDFPage.draw`) bilan
   chizish, tahrirlangandan keyin o'z engine'iga o'tish (UPDF'da sozlama bilan yoqiladi —
   §11.3). M1'da A/B o'lchab qaror qilinadi: tezlik va xotira vs ikki renderer orasidagi
   vizual farq.
8. Tungi rejim — Core Image yoki Metal filtri tile'ga (UPDF'da `adaptiveDarkMode`).

### 3.5 Concurrency

- `EngineActor` — yagona serial executor (PDFium global holati uchun). Render ham shu yerda,
  lekin kichik bo'laklarda; keyinchalik o'qish uchun alohida hujjat nusxasi bilan ikkinchi
  executor (faqat render) sinab ko'riladi.
- UI `@MainActor`. Engine'dan qaytgan qiymatlar `Sendable` struct'lar.
- Uzoq amallar (OCR, siqish, konvertatsiya, batch) — `Task` + progress + bekor qilish.
- UPDF'da har sahifa view'ining o'z serial navbati bor, lekin hammasi bitta
  `Document.lock` (`os_unfair_lock`) ostida — amalda hujjat bo'yicha ketma-ket. Bizda bu
  `EngineActor` bilan bir xil, faqat prioritetli (ko'rinadigan tile birinchi).

### 3.6 Saqlash, autosave va xotira

- Tahrirlar engine'ning sahifa obyektlarida turadi; content stream **faqat saqlashda** va
  faqat "iflos" sahifalar uchun generatsiya qilinadi (`needsGenerateContent` g'oyasi).
- `NSDocument` autosave (`autosavesInPlace` yoki versiyalar). Saqlash vaqtini o'lchab,
  sekin hujjatlarda autosave'ni siyrakroq qilish (UPDF 0.5 s chegarasida o'chiradi).
- Crash'dan tiklash uchun snapshot (alohida fayl, asl faylga tegmasdan).
- Ko'p tab'da xotira: faol bo'lmagan tab hujjatini snapshot'ga yozib yopish va qaytganda
  tiklash (UPDF'dagi `AutoFreesUpMemoryFromInactiveTabs`, `InactiveTabInterval`) — M9'da.

### 3.7 Undo

- Engine har amal uchun bitta `CC_UNDO` handle qaytaradi. `UndoBridge` uni
  `NSUndoManager.registerUndo(withTarget:)` bilan ro'yxatdan o'tkazadi; handler
  `CC_Undo_Undo` → UI callback (element/sahifani qayta yuklash) → qarama-qarshi yo'nalishni
  qayta ro'yxatdan o'tkazadi. UPDF'da xuddi shu sxema (arxitektura §11.5).
- Sahifa tartibini o'zgartirish kabi qaytarib bo'lmaydigan amallar avval undo'ga
  qo'shilmaydi; keyin ular uchun ham engine darajasida snapshot-undo qilinadi.

---

## 4. Bosqichlar

Har bosqich oxirida ishlaydigan ilova va testlar bo'ladi. Muddatlar — bitta dasturchi uchun
taxmin.

### M0 — Poydevor (2 hafta)
- PDFium fork'ini yig'ish: `gn` argumentlari — `pdf_is_standalone=true`,
  `is_component_build=false`, `pdf_enable_v8=false`, `pdf_enable_xfa=false`,
  `use_custom_libcxx=false` (Apple libc++ bilan link uchun), `target_cpu` arm64 va x64.
- `craftcore` gn target'i, `craftcore.h`, `build_xcframework.sh`.
- `harness` CLI: `open`, `render --page N --scale S out.png`, `text`.
- Xcode loyiha: AppKit app, CraftKit package, CI (GitHub Actions: build + test).
- **Tayyor bo'lishi:** ilova PDF'ni ochib, birinchi sahifani bitmap qilib ko'rsatadi.

### M1 — Viewer (4–6 hafta)
- `CraftDocument` (open/save as, recent, autosave), native tab'lar, oyna holatini tiklash.
- Canvas: single/continuous/two-up/cover, fit width/page, zoom (pinch, ⌘+/−), tile render,
  prefetch, smooth scroll.
- Sidebar: thumbnail'lar, outline (bookmark), qidiruv natijalari, attachment'lar.
- Matn tanlash (belgi quad'lari bilan), nusxa, qidiruv (highlight), link'lar bo'yicha o'tish.
- Print (`NSPrintOperation` + o'z `NSView` yoki PDFium render), tungi rejim, slide show.
- **Qabul:** 1 000 sahifali PDF'da 60 fps scroll, birinchi sahifa < 300 ms, xotira chegarada.

### M2 — Izohlar (4–6 hafta)
- Matn markup: highlight, underline, strikeout, squiggly (tanlovdan).
- Ink (bosim bilan), shakllar (line, arrow, rect, oval, polygon, polyline, cloud),
  free text / callout, sticky note, stamp (o'z shablonlari), rasm, imzo (chizish/rasm).
- Element tizimi: tanlash, ko'p tanlash, surish, resize, rotate, snap, align.
- Inspector: rang, qalinlik, shaffoflik, shrift. Izohlar ro'yxati (filtr, javoblar).
- Appearance stream'ni har doim yozish (boshqa viewer'larda ham ko'rinsin).
- Undo/redo hamma amal uchun. XFDF import/export, flatten.
- **Qabul:** saqlangan fayl Preview, Acrobat Reader va pdf.js'da bir xil ko'rinadi.

### M3 — Sahifalar (2–3 hafta)
- Organize grid: drag-drop, ko'p tanlash, rotate, delete, extract, insert (bo'sh, fayl,
  rasm, clipboard), replace, split (N sahifa, bookmark, o'lcham), merge, crop, resize,
  page labels.
- Bookmark/izoh/link'larni sahifa ko'chganda saqlab qolish.
- **Qabul:** 500 sahifalik faylni tartiblash va saqlash; outline va link'lar buzilmaydi.

### M4 — Formalar (3–4 hafta)
- To'ldirish: text, checkbox, radio, combo, list, Tab tartibi, format/validate (JS'siz
  asosiy formatlar: sana, raqam, foiz).
- Yaratish va tahrirlash: 7 tur, xossalar, tekislash, nusxalash, avtomatik aniqlash
  (keyin).
- FDF/XFDF import/export, reset, flatten.
- JavaScript: avval yo'q; kerak bo'lsa PDFium V8 bilan alohida yig'ma.

### M5 — Matn va obyekt tahriri (8–12 hafta) — eng murakkab
Dizayn edit engine hujjati §11 dagi tamoyillar asosida, lekin o'z algoritmlarimiz bilan:
- Page object modelini tahrirlash, saqlashda content stream'ni qayta generatsiya.
- Segmentatsiya: glyph → satr → blok → paragraf; alignment aniqlash.
- `TextEditView` (`NSTextInputClient`): yozish, IME (marked text sahifaning o'zida),
  o'chirish, Enter, kursor harakati, so'z/satr tanlash, copy/paste.
- Reflow: so'zlarga bo'lish (**UAX #14**), satrga terish, alignment, justify **`Tw`/`TJ` bilan**,
  auto-width (bitta satrli blok o'sadi, Enter'dan keyin qotadi).
- Uslub: font, o'lcham, rang, bold/italic (haqiqiy variant → sintetik), underline/strike
  (path atribut sifatida qayta chiziladi), alignment, oraliqlar.
- Fontlar: fallback zanjiri, HarfBuzz subset, mavjud subset'ni kengaytirish, `W` va
  `ToUnicode`.
- Bidi (UAX #9) va arab shaping yagona yo'ldan; vertikal yozuv keyin.
- Rasm va path: surish, resize, rotate, crop (clip), replace, extract — piksellarga tegmasdan.
- Har amal `CC_UNDO` qaytaradi; yozish ketma-ketligi bitta undo qadamiga birlashtiriladi.
- Blok chegarasini faylda saqlash: marked content (`/Span <</CraftEdit …>> BDC`) — qayta
  ochilganda paragraf bo'linib ketmasligi uchun.
- **Qabul:** test korpusida 3 marta tahrir → saqlash → ochish siklidan keyin bloklar soni va
  geometriya o'zgarmaydi; boshqa viewer'larda so'zlar yopishmaydi.

### M6 — Himoya, redaction, imzo (4–6 hafta)
- Parol (ochish/ruxsat), AES-256, ruxsatlar (qpdf).
- Redaction: belgilash → apply: matn glyph'lari, rasm piksellari va path'lar haqiqatan
  olib tashlanadi; qidirib redact qilish; metadata va yashirin ma'lumotni tozalash.
- Raqamli imzo: Keychain identity yoki `.p12`, imzo maydoni va ko'rinishi, incremental
  save + ByteRange + CMS (PAdES B-B), tekshirish va sertifikatni ko'rsatish
  (`SFCertificatePanel`). Timestamp/LTV — keyin.

### M7 — Asboblar (4–6 hafta)
- OCR (Vision): sahifa yoki butun hujjat, ko'rinmas matn qatlami, tillar, progress.
- Siqish: rasmlarni qayta kodlash (ImageIO/JPEG, JPEG2000 yo'q), font va obyekt tozalash,
  object streams (qpdf).
- Bezaklar: watermark, background, header/footer, Bates — marked content bilan, keyin
  tahrirlash/olib tashlash mumkin.
- Yaratish: rasmlardan, clipboard, skaner (`ImageCaptureCore`), ekran rasmi, veb-sahifa
  (`WKWebView.createPDF`), docx/rtf/html (`NSAttributedString`).
- Eksport: PNG/JPEG/TIFF, matn, HTML (oddiy).
- Taqqoslash: matn diff (sahifa bo'yicha) va rasm diff, yonma-yon sinxron scroll.
- Batch: shu amallarning ko'p faylli rejimi.

### M8 — AI (2–3 hafta, ixtiyoriy)
- Hujjat matnini bo'laklash, chat (stream), xulosa, tarjima, tushuntirish (tanlangan matn
  menyusidan). Javoblar Markdown.
- LLM provayder protokol orqali (masalan, Anthropic Claude API), kalit foydalanuvchida
  (Keychain) yoki o'z backend'ingizda.

### M9 — Sayqal va tarqatish (2–3 hafta)
- Lokalizatsiya (kamida en, uz, ru), accessibility (VoiceOver: sahifa, matn, izohlar),
  klaviatura yorliqlari, sozlamalar.
- Faol bo'lmagan tab'larni snapshot orqali xotiradan bo'shatish (§3.6).
- Crash/analitika (ixtiyoriy, rozilik bilan), Sparkle, notarization, DMG.

**Jami:** taxminan 9–12 oy (bitta dasturchi). MVP (M0–M3) — 2.5–3.5 oy.

---

## 5. Test strategiyasi

- **Engine harness** (UPDF'ni sinaganimiz kabi): har bir `CC_*` amali CLI orqali,
  natija — content stream dump + PNG.
- **Golden render testlari**: korpusdagi har sahifa PNG bilan solishtiriladi (piksel farq
  chegarasi bilan).
- **Round-trip**: tahrir → saqlash → poppler/pdf.js/Preview'da ochish → matn va geometriya
  tekshiruvi.
- **Korpus**: sintetik PDF'lar (ustunlar, justify, defis, RTL, CJK, burilgan matn, formalar,
  shifrlangan) + real hujjatlar (hisobotlar, kitoblar, skanlar). Edit engine hujjatidagi
  §1.2 ro'yxati — regression testlar uchun tayyor ssenariylar.
- **UI testlari**: XCUITest asosiy oqimlar uchun; render tezligi uchun Instruments
  (Time Profiler, Allocations) va `os_signpost`.
- **Fuzzing**: `libFuzzer` bilan `CC_Doc_Open` va content parser (PDFium'ning o'z fuzz
  target'lari ham bor).

---

## 6. Xavflar

| Xavf | Ta'sir | Choralar |
|---|---|---|
| PDFium'ni yig'ish va ichki C++ API'ning o'zgaruvchanligi | yuqori | fork'ni ma'lum commit'ga qotirish, yangilashni chorakda bir |
| Matn tahriri (M5) cho'zilishi | yuqori | M5'ni ichki bosqichlarga bo'lish: 1) bitta satr, 2) paragraf reflow, 3) uslublar, 4) fontlar, 5) bidi |
| PDFium thread-safe emas | o'rta | yagona `EngineActor`; render uchun keyin alohida hujjat nusxasi |
| Katta fayllarda xotira | o'rta | tile kesh chegarasi, sahifalarni yopish, `NSCache` |
| Raqamli imzo mosligi (Acrobat tekshiruvi) | o'rta | PAdES baseline, Acrobat Reader bilan qo'lda tekshiruv |
| PDF → Office sifati | o'rta | MVP'dan chiqarish; keyin alohida loyiha |
| Huquqiy | yuqori | §0 qoidalari; UPDF'dan resurs/kod yo'q |

---

## 7. Birinchi ikki hafta — aniq vazifalar

1. `depot_tools` o'rnatish, PDFium'ni checkout qilish, macOS arm64 standalone yig'ish.
2. `pdfium/craftcore` target'i: `CC_Init`, `CC_Doc_Open`, `CC_Doc_PageCount`,
   `CC_Page_Size`, `CC_Render_Rect`, `CC_Doc_Close`, `CC_GetLastError`.
3. x86_64 yig'ish va `CraftCore.xcframework`.
4. `harness`: `render` va `text` buyruqlari.
5. Xcode: `UPDFCraft` (AppKit, NSDocument-based), `CraftKit` package, `EngineActor`.
6. `PageView` — bitta sahifani `CALayer`da ko'rsatish, keyin `CanvasScrollView` bilan
   continuous rejim.
7. CI: build + harness smoke test.
