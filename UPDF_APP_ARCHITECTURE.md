# UPDF 2.5.6 (macOS) — butun ilova arxitekturasi

Statik tahlil, 2026-10-16. UPDF.app ishga tushirilmadi. Tahrir engine'i
(`CPDF_TextPage` va reflow) alohida va ancha chuqur o'rganilgan:
[UPDF_EDIT_ENGINE.md](../updf-reverse-engineering/UPDF_EDIT_ENGINE.md). Bu hujjat qolgan
hamma narsani qamraydi: bundle, modullar, UI tuzilmasi, engine API'si, plaginlar,
tarmoq va ilova qanday qatlamlarga bo'linganini.

Dalil belgilari (oldingi hujjat bilan bir xil):
**[S]** symbol, string yoki metadata · **[D]** disassembly yoki load command ·
**[P]** Hopper pseudo-code · **[X]** xulosa (bilvosita).

Dalil fayllari: [evidence/](evidence/)
- `app_source_tree.txt` — binarda qolgan 606 ta Swift manba fayl yo'li;
- `app_classes.txt` — 1 198 ta ObjC/Swift klass (1 133 tasi `UPDF` modulida);
- `app_uses_updfkit_api.txt` — ilova import qiladigan 772 ta UPDFKit funksiyasi;
- `updfkit_c_exports.txt` — UPDFKit'ning 11 825 ta C eksporti.

---

## 0. Nishon va usul

| | |
|---|---|
| Fayl | `~/Downloads/UPDF_2_5_6_EDiSO.iso` — aslida UDIF DMG |
| Ilova | `com.superace.updf.mac` 2.5.6 (build 1362), universal, `LSMinimumSystemVersion 11.0`, Xcode 26.5 / SDK macOS 26.5 bilan yig'ilgan [S] |
| Asosiy binar | `Contents/MacOS/UPDF`, arm64 slice 27.8 MB, sha256 `d735edeb…` [S] |
| Engine | `UPDFKit.framework`, arm64 slice 52.1 MB, sha256 `0ab15e38…` (edit engine hujjatidagi bilan bir xil) [S] |

**Ogohlantirish.** Bu crack qilingan reliz: asosiy binarga
`LC_LOAD_DYLIB @executable_path/../Frameworks/libUPDF.dylib` qo'shilgan [D]. Ilova
ishga tushirilmadi, crack va litsenziya tekshiruvi ko'rib chiqilmadi.

**Usul.**
- `rea`: `open_binary`, `inspect_macho` (77 dependency, 95 load command),
  `decode_interface_builder` (6 ta nib/storyboard), Hopper orqali dekompilatsiya (§11).
- `otool -oV` — ObjC metadata (Swift klasslar ham shu yerda: 1 677 ta klass).
- `dyld_info -imports`, `nm -gU`, `strings`, `swift-demangle`.
- **Manba daraxti**: Swift `#file` literallari binarda qolgan
  (`/Users/superace/Desktop/Code/updf-macos-v2-develop/UPDF/Sources/…`). Shu tufayli
  loyihaning papka tuzilmasi deyarli to'liq tiklandi (§3) [S].

---

## 1. Bir qarashda

```
┌────────────────────────────── UPDF.app — Swift/AppKit (SnapKit, kodda qurilgan UI) ─────────────────────────────┐
│ AppDelegate · WindowManager · EditorWindow (o'z TabBar'i)                                                        │
│  ├ HomeViewController     — fayllar (lokal + bulut), asboblar, so'nggilar                                        │
│  ├ EditorViewController   — UPDFDocument(NSDocument) → Document(Core)                                            │
│  │   Toolbar / ModeBar / ToolsPanel · Sidebar(Navigators) · PDFScrollView → PDFPageView(tile) + PageView(qatlam)  │
│  │   InspectorPane · FloatingInspector · ChatPane (AI)                                                            │
│  ├ BatchViewController · ComparisonViewController · InvoiceViewController · PortfolioViewController · Slide       │
│  └ Services: Chat/Cloud/Share/Signature/User/Feedback provider'lar (Alamofire → *.updf.com)                     │
├──────────────────────── Core (Swift) ────────────────────────┬──── ObjC++ ko'priklar ────────────────────────────┤
│ Document · Page · Annotation/FormField/Attachment/Bookmark   │ UPDFCore (UPDFKit C API)                           │
│ manager'lari · TextManager/TextBlock · ContentManager ·      │ ConversionEngine (SolidFramework, plagin)          │
│ UndoCommand → NSUndoManager · Graphic/Form · Comparator      │ OCREngine (ABBYY FREngine, plagin)                 │
├──────────────────────────────────────────────────────────────┴────────────────────────────────────────────────────┤
│ UPDFKit.framework — PDFium fork (+V8, XFA) · OpenSSL · HarfBuzz · FreeType · ICU · Hunspell · litehtml · OFD · HWP │
│ Apple: PDFKit (ba'zi render/print), Vision (tez OCR), AVSpeech (o'qib berish), WebKit (HTML→PDF, Web AI),          │
│        ImageCaptureCore (skaner), StoreKit (IAP), Metal (tungi rejim shader'i)                                     │
└───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Asosiy g'oya.** UPDF — ikki qavatli mahsulot:
1. **UPDFKit** — barcha PDF ishi (parse, render, annotatsiya, forma, tahrir, imzo, optimizatsiya,
   redaction, taqqoslash, eksport) bitta C API orqali beriladigan C++ framework.
2. **UPDF.app** — sof Swift/AppKit qobiq. U PDF'ni o'zi tushunmaydi: hamma narsa opaque
   handle'lar orqali UPDFKit'ga uzatiladi. UI esa sahifa ustida o'z "element" qatlamlarini
   quradi (§5).

---

## 2. Bundle tarkibi [S][D]

### 2.1 Frameworklar

| Komponent | Vazifasi | Izoh |
|---|---|---|
| `UPDFKit.framework` | PDF engine | 108 MB universal |
| `Sparkle.framework` | yangilanish | `SUPublicEDKey` Info.plist'da |
| `FirebaseAnalytics`, `GoogleAppMeasurement*` | analitika | + Crashlytics (Swift package) |
| `AliyunOSSOSX.framework` | bulutga yuklash | `oss-us-east-1.aliyuncs.com`, `v1/file/ossCredentials` |
| `libswift_Concurrency.dylib` | back-deploy | macOS 11 uchun |
| `SolidFrameworkNative.framework` | PDF → Office konvertatsiya | **`LC_LOAD_WEAK_DYLIB`**, bundle'da **yo'q** — plagin sifatida yuklab olinadi [D] |
| `FREngine.framework` (ABBYY) | professional OCR | bundle'da yo'q, plagin; `UPDF.ABBYY.LocalLicense` resursda [S] |
| `libUPDF.dylib` | **begona** (crack) | ko'rib chiqilmadi |

Plagin tizimi: `Settings/Plugin/{Plugin,PluginManager}.swift`, holatlar
`PluginStatusDownload / Installed / Upgrade / Relaunch`, "Auto Delete Plugin Archives"
sozlamasi. Arxivlar bundle ichidagi `7zz` (7-Zip) bilan ochiladi [S][X].
`com.apple.security.cs.disable-library-validation` entitlement'i ham shuning uchun
kerak — begona imzoli plagin framework'larini yuklash [S][X].

### 2.2 Swift package'lar (`*_*.bundle` va klass nomlaridan)

Alamofire (HTTP) · Kingfisher (rasm keshi) · SnapKit (Auto Layout DSL) · Down (cmark Markdown)
· MathJaxSwift (LaTeX → SVG, AI javoblari uchun) · SwiftyStoreKit (IAP) · SwiftyBeaver (log)
· SwiftDate · FileKit · ASN1Decoder (X.509 sertifikatlarni ko'rsatish) · Firebase
(Core/Crashlytics/Installations) · Promises · nanopb · GoogleUtilities.

### 2.3 Resurslar

| Resurs | Nima |
|---|---|
| `Assets.car` (80 MB) | ikonalar, stiker va shtamp rasmlari, illyustratsiyalar |
| `Base.lproj/Main.storyboardc` | faqat `MainMenu` sahnasi (332 obyekt, 3 ta action). **Butun UI kodda quriladi** [S] |
| 12 til `*.lproj` | en, de, fr, es, it, pt, nl, ru, ja, ko, zh-Hans, zh-Hant |
| `UPDF-PDFX.dat` (12 MB) | PDF/X eksporti uchun ICC/profil ma'lumotlari (`PDFX_SetDataFilePath`) [X] |
| `MindMap/` (js, html) | AI "mind map" — WebView'da chiziladi |
| `default.metallib` | bitta funksiya: `adaptiveDarkMode` — tungi rejim sahifa filtri [S] |
| `Watermark*.pdf` | watermark shablonlari |
| `UserGuide*.mp4` | onboarding videolari |

### 2.4 Info.plist va entitlement'lar

- `NSDocumentClass = UPDFDocument` (PDF uchun **Editor** roli). Word, Excel, PowerPoint,
  matn va rasm fayllari ham "Alternate" sifatida e'lon qilingan: ochilganda PDF'ga aylantiriladi.
- URL sxemalari: `updf://`, `updfv2://` (login callback, `Services/WebCallback.swift`).
- `NSUserActivityTypes`: `com.superace.updf.handoff.openDocument` — Handoff
  (`EditorViewController+Handoff`, `HandoffReceiver`).
- `NSAppTransportSecurity.NSAllowsArbitraryLoads = true`.
- Entitlement'lar: **App Sandbox yo'q**; Apple Events (Word/Excel/PowerPoint, Pages/Keynote/Numbers —
  Office faylni PDF'ga aylantirish uchun skript orqali), `screencapture.interactive`
  (ekran rasmidan PDF), security-scoped bookmark'lar.

---

## 3. Manba daraxti — ilova modullari [S]

606 ta Swift fayl yo'li tiklandi (ObjC++ fayllar `#file` qoldirmagan, ular faqat klass nomidan
ma'lum: `UPDFCore`, `ConversionEngine`, `OCREngine`).

| Papka | Fayl | Nima qiladi |
|---|---|---|
| `Editor/` | 302 | asosiy muharrir: PDF view, elementlar, inspector'lar, toolbar'lar, navigator'lar, sahifa asboblari |
| `Chat/` | 47 | AI: chat, Ask PDF, tarjima, xulosa, mind map, rasm generatsiya, Web AI |
| `Components/` | 40 | o'z UI kit'i: dropdown, popover, slider, toast, date picker, checkbox… |
| `Batch/` | 34 | ommaviy amallar: convert, OCR, compress, merge, encrypt, print, watermark, Bates |
| `Home/` | 32 | bosh oyna: lokal va bulut fayllar, papkalar, share, transfer |
| `Settings/` | 23 | sozlamalar, plaginlar, onboarding, feedback |
| `User/` | 22 | akkaunt, qurilmalar, IAP/obuna, trial |
| `Core/` | 20 | `Document`, `UPDFCore`, manager'lar, `TextBlock`, `Comparator`, `Replacer` |
| `Invoice/` | 15 | hisob-faktura (Xitoy e-fapiao) aniqlash va eksport |
| `Comparison/` | 13 | ikki PDF'ni taqqoslash |
| `Portfolio/` | 12 | PDF Portfolio (collection) |
| `Creator/` | 11 | PDF yaratish: bo'sh, clipboard, rasm, skaner, ekran, veb |
| `Services/` | 9 | backend provider'lari |
| `Slide/` | 7 | taqdimot rejimi (presenter view bilan) |
| `Converter/` | 4 | PDF → Office/rasm dialoglari |
| `OCR/` | 2 | OCR sozlamalari, matnni aniqlash view'i |

`Editor/` ichida:

```
Editor/
├ EditorViewController(+Pane,+Handoff) · UPDFDocument · FileMark · CoreExtensions
├ Window/       EditorWindow · WindowManager
├ TabBar/       Tab · TabBar · QuickAccessPanel
├ Toolbars/     Toolbar · ToolbarContainer · ToolButton · ComboButton · QuickAccessBar · ToolsAccessBar
│   ├ ToolsPanel/   ToolsPanel · PDFToolButton
│   ├ ElementBars/  ModeBar · ElementBar · CommentBar · EditingBar(+ElementFilterPanel) · FormFieldBar · RedactionBar(+SanitizeDialog)
│   └ AITools/      AIToolsPanel · AIToolsResultView · ChatField
├ PDFView/
│   ├ PDFScrollView(+Action,+Page,+Scale,+Scroll,+Speech)
│   ├ PageView/     PDFPageView · PageView(+AreaCapture,+Event,+Highlight)
│   ├ Containers/   AnnotationContainer(+Event) · ElementContainer(+Event) · FormFieldContainer
│   └ Elements/     Annotations/{Measure,NotableElement,Pencil,Texts} · Contents/{Text,Image} · FormFields
├ Inspectors/   InspectorPane · DocumentInspector · ElementsInspector(OptionsViews) · FloatingInspectors/{Signature,Stamp,Sticker,Redaction,Link} · FormFieldInspector/{DigitalSignature,ExtensionViews,PropertiesViews}
├ Navigators/   Sidebar · NavigatorPane · Thumbnail · Bookmark(+Generation,+Summary) · Comment · FormField · Search(+Find,+Replace) · Attachment
├ Organizer/    OrganizePagesPanel · PageCell · Insert/ · Split/ · Page{Exchange,Extract,Label,Replace,Resize}Dialog
├ PageTools/    CropPages/ · SplitPages/ · ScalePageView
├ Decorations/  Watermark/ · Background/ · HeaderFooter/ · Templates/
└ Accessories/  PageBar · SaveAsPanel/{Encrypt,Flatten,Optimizer,PDF/A,PDF/X,Scan} · UnlockDialog · TipViews
```

To'liq ro'yxat: [evidence/app_source_tree.txt](evidence/app_source_tree.txt).

---

## 4. Hujjat va oyna modeli [S]

| Klass | Vazifa | Muhim maydonlar |
|---|---|---|
| `UPDFDocument : NSDocument` | macOS hujjat tizimi bilan bog'lanish | `coreDocument`, `fileURL`, `fileHash`, `fileID`, `cloudFile`, `isCloud/isLocal/isAttachment`, `snapshot`, `isRestoredFromSnapshot`, `chatID`, `analyzedState`, `displayState` |
| `Document` (Core) | UPDFKit hujjati ustidagi model | `handle`, `pdfDocument` (Apple `PDFDocument`!), `unannotatedDocument`, `undoManager`, `annotationManager`, `formFieldManager`, `attachmentManager`, `bookmarkManager`, `pageLabelManager`, `decorationManagers`, `pageMap`, `removedPages`, `isPageIndexChanged`, `password`, `hasOpenPassword`, `hasSecurityChanges`, `hasNonUndoableChanges`, `snapshotURL`, `isEligibleForAutosave`, `canRenderByPDFKit`, `lock` |
| `WindowManager` | oynalar va tab'lar | `windowControllers`, `toolTabs`, `_restoredTabPaths`, `_restoredSelectedIndexes` — sessiya tiklash |
| `EditorWindow : NSWindow` | bitta oynada bir nechta tab | `tabBar`, `home`, `cloud`, `userBar`; `closeTab:`, `mergeWindows:`, `moveToNewWindow:`, `showNext/PreviousTab:` |

Kuzatishlar:
- **Tab'lar native `NSWindow` tabbing emas**: o'z `TabBar`i bor (Home tab + hujjat tab'lari +
  asbob tab'lari), "Merge windows" / "Move to new window" qo'lda yozilgan.
- **Ikki hujjat obyekti.** `Document` UPDFKit handle'idan tashqari Apple `PDFDocument`ni ham
  saqlaydi (`pdfDocument`, `unannotatedDocument`). Bu render va bosib chiqarishda PDFKit'dan
  foydalanish uchun (§6.2).
- **Snapshot va autosave.** `snapshotURL`, `isRestoredFromSnapshot`, `isEligibleForAutosave` —
  saqlanmagan o'zgarishlar alohida faylga yoziladi va keyingi ochilishda tiklanadi [X].
- **Sahifa xaritasi.** `pageMap`, `removedPages`, `isPageIndexChanged` — sahifa tartibi
  o'zgarganda element/izoh indekslarini qayta bog'lash uchun [X].

---

## 5. PDF ko'rinishi: scroll → sahifa → qatlamlar → elementlar [S]

```
PDFScrollView (NSScrollView)
 ├ displayMode: single / continuous / dual / dualContinuous / showCover; fitWidth/fitPage/fitHeight/actualSize
 ├ pageCache (PageCache), cachedIndexes, centerIndex, anchors (o'qish joyi)
 ├ autoScroll (timer, tezlik darajasi), speech (AVSpeechSynthesizer — "o'qib berish")
 ├ live magnify / live scroll / live resize hodisalari
 └ PDFPageView ─── render: tileSize, tileRects, renderQueue, renderedRect, pendingRect,
      │              reusableLayers (CALayer qayta ishlatish), isRenderByPDFKit, canRenderWithPDFPage
      └ PageView ── mode, state, displayMode, backdrop (tungi fon), gap
           ├ containers: contentContainer · annotationContainer · formFieldContainer · redactionContainer
           │             (activatedContainer — joriy rejimdagi qatlam hodisalarni oladi)
           ├ layers: blendLayer · highlightLayer · selectionLayer · gapLayer · dragAndDropLayer
           └ handlesView (resize/rotate tutqichlari)
```

### 5.1 Render [S][X]

- **Tile'lar.** `PDFPageView` sahifani kvadrat tile'larga bo'lib chizadi (`tileSize`,
  `tileRects`). Har bir tile alohida `CALayer` (`reusableLayers` havzasi). Ko'rinadigan
  hududdan tashqaridagi tile'lar qayta ishlatiladi.
- **Fon navbati.** Har sahifa view'ida serial `renderQueue` (`com.updf.render.<n>`); har
  render `Document.lock` ostida (§11.1–11.2) [P]. `pendingRect` / `renderedRect` zoom paytida
  eski bitmap'ni ko'rsatib turib, aniq versiyani keyin almashtirish uchun [X].
- **Engine.** Ilova import qiladigan render API: `PDF_RenderPageHDC` (Mac'da "HDC" — `CGContext`),
  `PDF_RenderPageRectToBitmap`, `PDF_RenderFormBitmap`, `PDF_RenderPageIgnoreCropBox` [S].
  UPDFKit'da progressive render (`RenderPageBitmap_Start/Continue`), GPU/Skia rejimi
  (`SetGPURenderStatus`, `PDFSkia_*`) ham bor, lekin ilova ularni import qilmaydi [S].
- **PDFKit yo'li.** Tahrirlanmagan sahifa (`Page.isEdited == false`) sozlama yoqilgan
  bo'lsa Apple PDFKit bilan chiziladi; tahrirdan keyin UPDFKit'ga o'tadi (§11.3) [P].
- **Tungi rejim.** `NightFilter` + Metal `adaptiveDarkMode` shader'i, `PageView.backdrop`,
  `isNightBackdrop`.

### 5.2 Qatlamlar (containers) va elementlar

Har bir rejimning o'z container'i bor. Hodisalar (`leftMouseDown/Dragged/Up`,
`keyDown`, `pressureChanged` — Force Touch, `touchesChanged` — trackpad) faqat
`activatedContainer`ga uzatiladi.

| Container | Elementlar | Asosiy amallar |
|---|---|---|
| `ContentContainer` (Edit rejimi) | `TextElement` (NSTextInputClient), `ImageElement`, `PathElement`, `ShadingElement` | tahrir, surish, aylantirish, align/distribute, `SnapHelper` (yopishish) |
| `AnnotationContainer` (Comment rejimi) | 30+ annotatsiya elementi (§7) | matn tanlash → highlight/underline/strike/squiggly, nusxa, AI menyusi (explain/summarize/translate), "speak", bookmark qo'shish |
| `FormFieldContainer` (Form rejimi) | `TextField/CheckBox/Radio/Dropdown/ListBox/Button/SignatureElement` | yaratish, to'ldirish, "multiple copies", aligns |
| `RedactionContainer` | `RedactionElement` | belgilash, "apply", sahifani redact qilish |

Elementlar ierarxiyasi: `Element` → `MovableElement` → `RotatableElement` → aniq
elementlar; `NotableElement` — izohi (note popup) bor annotatsiyalar; `VisibleSizeElement`,
`CompatibleShapeElement`, `UnsupportedElement` (tahrirlab bo'lmaydiganlar). Har bir element
juftligi `XxxElement` + `XxxAttributes` (rang, qalinlik, shrift, uslub) — inspector shu
attributes'ni o'zgartiradi.

---

## 6. UPDFKit — engine [S]

### 6.1 Tarkibi (eksport qilingan symbol'lar bo'yicha)

| Kutubxona | Belgi | Vazifa |
|---|---|---|
| **PDFium** (fork) | `CPDF_*`, `CPWL_*`, `fxcrt`, `fxcodec`, `pdfium::` | parse, render, annotatsiya va forma appearance |
| V8 + PDFium JS | `v8::` (23k), `CJS_*` | AcroForm JavaScript |
| XFA | `CXFA_*`, `CJX_*`, `CFXJSE_FormCalcContext` | XFA formalar |
| OpenSSL 3 | `X509`, `EVP`, `CMS`, `PKCS7/12`, `OCSP`, `SM2/3/4` | raqamli imzo, shifrlash, LTV |
| HarfBuzz, FreeType | `hb_*`, `FT_*` | shaping, subset, fontlar |
| ICU | `u*`, `ucnv*`, `ubidi` | bidi, kodlashlar |
| Hunspell | `Hunspell`, `AffixMgr` | imlo tekshiruvi |
| libpng, libjpeg-turbo, OpenJPEG, FreeImage, CxImage | `png_`, `jsimd`, `opj_`, `FreeImage_` | rasm kodeklari |
| leptonica, quirc | `lept`, `quirc` | rasm tozalash, QR o'qish |
| gumbo + litehtml | `gumbo`, `litehtml::` | HTML → PDF |
| pugixml, miniz/minizip | `pugi::`, `mz_`, `zip*` | XML (XFDF, DOCX), zip |
| Skia | `PDFSkia_*` | GPU/Skia render yo'li |
| OFD, HWP | `ofd::`, `hwp` | Xitoy OFD va Koreya Hangul fayllarini ochish |
| `convertor::`, `importer::` | UPDF'ning o'zi | PDF → Word/HTML (paragraf/ustun importer) |

### 6.2 C API oilalari (11 825 eksportdan UPDF'niki)

| Oila | Soni | Nima |
|---|---|---|
| `PDF_*` | 209 | hujjat: load/save (linearized, FD, cert bilan), render, sahifa o'lchamlari, label'lar, named dest, FDF/XFDF/XML import-export, XFA, struct tree, OFD/CAJ/HTML → PDF, sahifalarni bo'lish |
| `PDFAnnot_*` | 142 | annotatsiyalarning barcha xossalari: ink, callout, measure, redaction overlay, IRT (javoblar), review state, appearance (`GetAP/SetAP`) |
| `PDFPageField_*` | 118 | forma maydonlari: tur, qiymat, format/keystroke/validate/calculate action'lari, appearance, comb, rich text, barcode |
| `PDFText_*` | 99 | tahrir engine'i (alohida hujjat) |
| `PDFPage_*` | 66 | annotatsiya CRUD, flatten, boxes, rotation, obyektlar, thumbnail, serializatsiya |
| `PDFTaggedElement_*`, `PDFTagged_*` | 79 | **watermark, background, header/footer, Bates** — keyin tahrirlanadigan "tagged" elementlar |
| `PDFSignature_*` | 35 | imzolash, tekshirish, LTV, o'zgarishlar ro'yxati, ByteRange |
| `PDFDoc_*` | 36 | attachment, JS action, bookmark generatsiya, bo'sh/rasmli/burilgan sahifalarni topish, so'z sanash |
| `PDFPageObj/Path/Image/Shading/Graphic/Form` | ~130 | content obyektlari va chizish |
| `PDFBookmark/Action/Link/Dest/Attachment` | ~80 | navigatsiya |
| `PDFOptimizer_*` | 14 | siqish: rasm, font, tozalash, metadata olib tashlash |
| `PDFOCR_*` | 11 | `CreateByABBYY`, sahifa/hudud, dual-layer, PDF/UA |
| `PDFExport_*` | 20 | PDF/A, PDF/E, PDF/X, rasm, matn, "scan PDF", AI uchun matn |
| `PDFMerge_*`, `PDFComparator_*`, `PDFRedact_*`, `PDFTextSearcher_*`, `PDFTextSpellCheck_*`, `PDFTranslator_*`, `PDFInvoice_*`, `PDFFieldSigLock_*`, `PDFUndoCommand_*`, `PDFSerialize_*` | — | nomidan ma'lum |

Ilova bularning **772 tasini** import qiladi.

### 6.3 Ko'prik: `UPDFCore`

`Core/UPDFCore.swift` + ObjC++ qism. Ilova C handle'larni Swift klasslariga o'raydi:
`Document.handle`, `TextManager.handle`, `UndoCommand.handle`. Har bir tahrir amali
`PDFUndoCommand` handle'ini qaytaradi; `UndoCommand{handle, callback, undoManager}` uni
`NSUndoManager`ga ro'yxatdan o'tkazadi (`registerUndo(withTarget:handler:)` importi) [S].

---

## 7. Funksiyalar xaritasi [S]

### 7.1 O'qish
Single/continuous/dual/cover rejimlari, zoom, auto-scroll, slide-show (presenter view,
taymer), tungi rejim, o'qib berish (AVSpeech), tab'lar, Handoff, so'nggi fayllar, qidiruv
(tarix bilan; find & replace), lupa (`Magnifier`), ekran hududini olish (`AreaCapture`).

### 7.2 Izohlar (Comment rejimi)
Highlight · Underline · Strikethrough · Squiggly · Sticky note · Text box · Text comment ·
Callout · Pencil (ink, bosim bilan) · Eraser · Highlighter · Line · Arrow · Rectangle · Oval ·
Polygon · Polyline · Cloud · Stamp (tayyor + custom: matn, sana, rasm) · Sticker · Signature
(sichqoncha, trackpad, klaviatura, foto) · Attachment · Link · Insert/Replace text (markup) ·
**Measure** (Distance, Perimeter, Area; kalibrlash — `CalibrateBar`).
Izohlar ro'yxati (filtr, javoblar, holat), XFDF/FDF eksport-import, izohlarni PDF sifatida
eksport, flatten.

### 7.3 Tahrir (Edit rejimi)
Matn (to'liq reflow engine — alohida hujjat), rasm (crop, rotate, flip, replace, extract,
**vektorlashtirish** — `ImageTracing`), path, shading; link'lar; align/distribute; snap.

### 7.4 Sahifalar
Thumbnail, organize (drag-drop, ko'chirish), insert (bo'sh, fayl, clipboard, rasm,
**interleave**), extract, split (sahifa soni, o'lcham, bookmark, chiziq bilan, shablonlar),
replace, exchange, rotate, delete, crop, resize/scale, page labels.

### 7.5 Formalar
Yaratish (7 tur), avtomatik aniqlash (`RecognizeFields`), properties (general, appearance,
position, options, actions, format, calculate), JavaScript, tab tartibi, "multiple copies",
import/export (FDF/XFDF/XML/TXT), reset, flatten.

### 7.6 Himoya va imzo
Ochish paroli va ruxsat paroli (`EncryptionView`, `PermissionPasswordDialog`), unlock,
**redaction** (matn, hudud, sahifa, kod to'plamlari bo'yicha qidirib), **sanitize**
(yashirin ma'lumot, metadata), raqamli imzo (sertifikat yaratish/import, ko'rinish shablonlari,
tekshirish, `SFCertificatePanel`), maydonni imzo bilan qulflash.

### 7.7 Bezaklar (Decorations)
Watermark (matn/rasm/PDF, joylashuv, tile), Background, Header & Footer, Bates raqamlash;
shablonlar va "yulduzcha" qo'yilganlar. Hammasi `PDFTagged*` orqali, shuning uchun keyin
tahrirlanadi yoki olib tashlanadi.

### 7.8 Konvertatsiya, OCR, yaratish
- PDF → Word (RTF ham), Excel/CSV, PowerPoint, HTML, Text, rasm, PDF/A, tagged PDF —
  **SolidFramework** plagini (`ConversionEngine`, ObjC++) [S].
- OCR: **ABBYY FREngine** plagini (dual-layer "searchable/editable", MRC siqish, tillar) va
  Apple **Vision** (`VNRecognizeTextRequest`) — tez, plagin talab qilmaydigan holatlar uchun [S].
- Yaratish: bo'sh sahifa, clipboard, rasm(lar), skaner (`ImageCaptureCore`, `IKScannerDeviceView`),
  ekran rasmi, veb-sahifa (`WKWebView` + `WKPDFConfiguration`), Office fayl (Apple Events
  orqali Word/Pages, yoki UPDFKit `HTML2PDF`).
- Save As: PDF/A, PDF/X, flatten, optimize, "scan PDF", sertifikat bilan.

### 7.9 Ommaviy (Batch)
Convert, Create, OCR, Compress, Merge, Insert, Remove, Encrypt, Print, Watermark/Background/
Header-Footer, Bates.

### 7.10 Boshqa rejimlar
Compare (matn/rasm o'zgarishlari, filtr, sinxron scroll), Portfolio, Invoice (Xitoy
e-fapiao: aniqlash, jadval, eksport), Slide show.

### 7.11 AI (`Chat/`, `Services/Chat/ChatProvider`)
Ask PDF (fayl xulosasi, tavsiya savollar), chat (stream), sahifa tanlash, tarjima (matn va
butun PDF — `file/translate/*`), tushuntirish, xulosa, bookmark'larni xulosalash, **mind map**
(WebView), rasm generatsiya, "Web AI". Javoblar Markdown + LaTeX (Down + MathJax).
Endpoint'lar [S]: `chat/talk-stream`, `chat/talk-completion`, `chat/single-chat`,
`chat/instruction`, `chat/generate-image`, `chat/public/usage`.

### 7.12 Bulut, akkaunt, to'lov
`*.updf.com` (api, apis, ai, accounts, checkout, sign), Aliyun OSS'ga yuklash, share link
(parol, muddat, email), qurilma bog'lash (shaxsiy/korporativ), obuna rejalari, StoreKit IAP
va kvitansiya tekshiruvi, Sparkle yangilanish, Firebase analitika va Crashlytics.

---

## 8. UI qurilishi [S]

- **Storyboard yo'q** (faqat MainMenu); hamma view kodda, SnapKit bilan. Asosiy menyu
  ham kodda (`AppDelegate.FileMenuItem`, `TabMenuItem`, `ThemeMenuItem`, `BatchMenuItem`).
- **O'z komponent kutubxonasi** (`Components/`, `UIFactory`): `BaseDropdown`, `AutoPopover`,
  `SecondaryPopover`, `ThickSlider`, `StepperTextField`, `Toast`, `CircularProgressIndicator`,
  `SegmentedControl`, `SplitView`, `ColorPicker`, `FontPicker`. Ya'ni stock AppKit kontrollari
  deyarli ishlatilmaydi — o'z dizayn tizimi.
- **Inspector'lar**: o'ngdagi `InspectorPane` (hujjat va element xossalari) va sahifa ustida
  suzuvchi `FloatingInspector` (imzo, shtamp, stiker, redaction, link).
- **Rejimlar**: `ModeBar` + `ElementBar` (rejimga xos asboblar qatori: Comment/Editing/FormField/
  Redaction bar) + `ToolsPanel` (barcha asboblar katalogi) + `QuickAccessBar`.
- SwiftUI framework link qilingan, lekin klass ro'yxatida SwiftUI view'lar deyarli yo'q
  (`ContentHostingView` — bitta host) [S][X].

---

## 9. Undo va saqlash [S][X]

- Engine darajasida: har bir amal → `PDFUndoCommand` (snapshot + sub-command'lar; matn
  uchun edit engine hujjati §7).
- Ilova darajasida: `NSUndoManager` (`Document.undoManager`); container'lar
  `documentWillUndoChange` / `documentDidUndoChange` bilan elementlarni qayta yuklaydi.
- `hasNonUndoableChanges` — sahifa tartibini o'zgartirish kabi qaytarib bo'lmaydigan
  amallardan keyin undo stack tozalanadi [X].
- Saqlash: `PDF_Save` / `PDF_LinearizedSave` / `PDF_SaveAsCopy`. Content stream faqat
  saqlashda, `needsGenerateContent` bayrog'i bor sahifalar uchun qayta yoziladi; saqlash
  0.5 s dan uzoq bo'lsa autosave o'chadi (§11.4) [P].

---

## 10. UPDF'dan saboqlar — o'z ilovangiz uchun

1. **Engine va qobiqni qat'iy ajrating.** Barcha PDF mantiqi bitta C/C++ kutubxonada,
   UI faqat handle'lar bilan ishlaydi. Shunda engine'ni alohida sinash (harness) mumkin.
2. **Sahifa = tile'langan bitmap + interaktiv qatlamlar.** PDF tarkibi bitmap sifatida
   chiziladi, tahrirlanayotgan narsalar esa ustida alohida view/layer.
3. **Rejimga qarab container.** Har bir rejim (comment, edit, form, redact) o'z hodisa
   ishlovchisi va elementlariga ega — bitta katta `mouseDown` emas.
4. **Element + Attributes juftligi** — inspector umumiy bo'ladi.
5. **Har bir engine amali undo handle qaytaradi**, UI uni `NSUndoManager`ga beradi.
6. **Og'ir funksiyalar plagin** (OCR, Office konvertatsiya) — bundle kichik qoladi.
7. **Bezaklar tagged** — watermark/header-footer keyin ham tahrirlanadi.
8. **Snapshot autosave** — crash'dan keyin tiklash va faol bo'lmagan tab'larni xotiradan
   bo'shatish.
9. **Ikki renderer**: tahrirlanmagan sahifa — tizim rendereri (tez, xotirasi kam),
   tahrirlangan — o'z engine (§11.3).
10. **Content stream'ni dangasa generatsiya qilish** — faqat saqlashda va faqat o'zgargan
    sahifalar (§11.4).
11. **Eskirgan render vazifalarini bekor qilish** — navbatdan chiqqanda zoom va ko'rinish
    qayta tekshiriladi (§11.2).

---

## 11. Dekompilatsiya natijalari (Hopper, REA) [P]

**Usul.** REA'ning standart Hopper limiti (120 s) bu binar uchun yetmadi, shuning uchun alohida
REA MCP sessiyasi `REA_HOPPER_STARTUP_TIMEOUT_MS=3600000` bilan ochildi. Hopper 6.x thin arm64
slice'ni (`UPDF.arm64`) **~7 daqiqada** tahlil qildi (`search_strings` birinchi javobi
430 669 ms). Swift funksiyalari nomsiz (`sub_…`), shuning uchun yo'l string va ivar offset
symbol'laridan (`objc_ivar_offset__TtC4UPDF…`) xref orqali topildi. Pseudo-code fayllari:
[evidence/pseudo/](evidence/pseudo/).

### 11.1 Sahifani bitmap'ga chizish — `Page.image(rect:scale:…)` (`sub_1000592a8`)

```
lock(document.lock)                         // os_unfair_lock, har bir render shu ostida
size = ceil(rect.size · scale)              // FloatingPointRoundingRule.up
bmp  = Bitmap(size)                         // PDFBitmap_Create
bmp.fill(NSColor.white)
page.render(bmp, rect, …)                   // sub_1009ca618 → PDF_RenderPageRectToBitmap
image = bmp.makeImage(); PDFBitmap_Destroy
unlock(document.lock)
```

- Ichki `sub_1009ca618` (2 667 satr) `Page.handle`ni oladi, yashiriladigan annotatsiyalar
  massivini (`[Int8] → [Int32]`) quradi va `PDF_RenderPageRectToBitmap`ni chaqiradi. Bu
  tahrirlanayotgan element bitmap'da ko'rinmasligi uchun [P][X].
- Thumbnail'lar (`ThumbnailButton`, `AnchorThumbnailsView`), lupa (`PageView` area capture)
  va annotatsiya preview'lari ham shu funksiyadan foydalanadi (4 ta chaqiruvchi).

### 11.2 Tile render — `PDFPageView` (`sub_100171c8c`, `sub_10017002c`)

- **Navbat.** Har bir `PDFPageView` o'zining **serial** `DispatchQueue`siga ega:
  `label: "com.updf.render.<n>"`, `qos: .unspecified`, attributes bo'sh (`sub_10016d5a0`).
  Bir hujjatdagi sahifalar baribir `Document.lock` bilan ketma-ket chiziladi (§11.1).
- **Tile vazifasi.** Navbatda bajarilishidan oldin tekshiradi: `Page.isOpened`,
  `Document.isOpened`, **zoom so'rov paytidagidek** (`scale == d9`) va tile hali ham
  `visibleRect ∩ bounds` bilan kesishadi. Shundagina `Page.image` chiziladi va layer'ga
  beriladi. Aks holda `renderedRect` nolga tushiriladi va barcha `ReusableLayer`lar
  (`isUsed = false`, `tilePosition`, `renderingScale` tozalanadi) `removeFromSuperlayer`
  bilan havzaga qaytadi.
- **Tile kaliti.** `tileRects` — tile pozitsiyasi → rect lug'ati; rect =
  `CGRectIntegral(CGRectInset(…)) ∩ bounds` (`sub_1001723bc`). `_renderedPositions` —
  `os_unfair_lock` bilan himoyalangan to'plam (qaysi tile'lar chizilgani).
- **Zoom o'zgarganda** (`sub_1000a93ec`, `sub_100a3d008`): `tileSize = .zero`,
  `tileRects = [:]`, `renderedPositions = []`, `renderedRect = .zero` — hammasi qayta
  hisoblanadi.
- **Tile o'lchami** lazy getter ichida hisoblanadi; aniq qiymat topilmadi (ochiq savol).

### 11.3 PDFKit tezkor yo'li (`sub_10016f9e0`)

```
if page.isEdited                    → nil      // tahrirlangan sahifa — faqat UPDFKit
if !document.canRenderByPDFKit      → nil
if !UserDefaults["CanRenderByPDFKit"]-ga o'xshash global bayroq → nil
if !canRenderWithPDFPage            → nil      // Apple PDFPage mavjud
return document.pdfDocument.page(at: index)    // Apple PDFKit sahifasi
```

Natija bo'lsa, `isRenderByPDFKit = 1` va sahifa layer'i Apple PDFKit bilan chiziladi; aks
holda UPDFKit tile'lari. Ya'ni **tahrirlanmagan sahifalar macOS'ning o'z rendereri bilan,
tahrirlanganlari o'z engine bilan** chiziladi. `CanRenderByPDFKit`, `CanPrintWithPDFKit` —
UserDefaults kalitlari (sozlamalar blokida `AutoFreesUpMemoryFromInactiveTabs`,
`SuspendedTabInterval`, `InactiveTabInterval` bilan yonma-yon) [S][P].

### 11.4 Saqlash — `Document.save(to:linearized:)` (`sub_100695490`, `sub_100693590`)

```
if fayl mavjud:
    for page in pageMap where page.needsGenerateContent:
        page.needsGenerateContent = false
        PDFPage_GenerateContent(page.handle)     // content stream faqat shu yerda yoziladi
    linearized ? PDF_LinearizedSave : PDF_Save
else:
    … xuddi shu, keyin PDF_SaveAsCopy(…)
saveDuration = Date() − start
isEligibleForAutosave = saveDuration < 0.5 s
```

- **Content stream'lar dangasa qayta yoziladi**: tahrirlar sahifa obyektlarida turadi,
  stream faqat saqlashda va faqat o'zgargan sahifalar uchun generatsiya qilinadi.
- **Autosave faqat tez saqlanadigan hujjatlar uchun**: oxirgi saqlash 0.5 s dan uzoq
  bo'lsa, autosave o'chadi (katta fayllarda yozuv paytida UI qotmasligi uchun) [P][X].

### 11.5 Undo — `UndoCommand` (`sub_1005ef78c`)

```
undoHandler(target: UndoCommand):
    guard let um = weak undoManager, um.isUndoing
    PDFUndoCommand_Undo(handle)
    callback?(…)                                  // UI'ni yangilash (element/sahifa)
    um.registerUndo(withTarget: …) { redoHandler } // NSUndoManager.registerUndo<A>
```

Engine handle bitta, ilova faqat yo'nalishni almashtirib qayta ro'yxatdan o'tkazadi.

### 11.6 Snapshot (`sub_100e30d9c`, `UPDFDocument.snapshot`)

Hujjat ochiq va o'zgargan bo'lsa (va `hasNonUndoableChanges` bo'lmasa), `.pdf` snapshot
fayli `Document.password` bilan birga yoziladi; `UPDFDocument.isRestoredFromSnapshot` keyin
undan tiklanganini bildiradi. Sozlamalardagi `AutoFreesUpMemoryFromInactiveTabs` /
`SuspendedTabInterval` / `InactiveTabInterval` bilan birga bu **faol bo'lmagan tab'larni
"uxlatish"** mexanizmiga o'xshaydi: hujjat snapshot'ga yoziladi, yopiladi va tab qayta
ochilganda tiklanadi [P][X] (ulanish to'liq kuzatilmadi).

---

## 12. Ochiq qolganlar

- UI ishga tushirilmadi: animatsiyalar va real render tezligi runtime'da kuzatilmadi.
- Tile o'lchamining aniq qiymati topilmadi (lazy getter Hopper'da alohida funksiya bo'lib
  chiqmadi); PDFKit bayrog'i aynan qaysi UserDefaults kalitiga bog'langani bilvosita.
- Tab "uxlatish" (§11.6) snapshot yozilishi tasdiqlandi, lekin taymer va qayta ochish zanjiri
  dekompilyatsiya qilinmadi.
- Faqat Swift fayl yo'llari tiklandi; ObjC++ qism (`UPDFCore`, `ConversionEngine`,
  `OCREngine`) faqat klass va metod nomlaridan ma'lum.
- AI va bulut endpoint'larining so'rov formati ko'rib chiqilmadi (tarmoq ushlanmadi).
- SolidFramework va ABBYY plaginlari bundle'da yo'q, shuning uchun ularning ichki ishi
  tahlil qilinmadi.
