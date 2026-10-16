// craftcore.h — UPDF Craft engine'ining yagona ommaviy C API'si.
//
// Qoidalar (APPKIT_NATIVE_PLAN.md §3.2):
//  - Faqat opaque handle'lar va POD struct'lar; C++ turlari chegaradan o'tmaydi.
//  - Istisnolar chegaradan o'tmaydi: xato bo'lsa funksiya NULL / 0 / CC_ERR_* qaytaradi,
//    tafsilot CC_GetLastError() va CC_GetLastErrorMessage() orqali olinadi.
//  - Engine thread-safe emas (PDFium global holatli). Barcha chaqiruvlar bitta serial
//    executor'dan bo'lishi kerak (Swift tomonda EngineActor).
//  - Keyingi bosqichlarda har bir o'zgartiruvchi amal CC_UNDO qaytaradi
//    (NULL = hech narsa o'zgarmadi). M0'da o'zgartiruvchi amallar yo'q.

#ifndef CRAFTCORE_H_
#define CRAFTCORE_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__GNUC__) || defined(__clang__)
#define CC_EXPORT __attribute__((visibility("default")))
#else
#define CC_EXPORT
#endif

#define CC_API_VERSION 1

// ---------------------------------------------------------------------------
// Handle'lar
// ---------------------------------------------------------------------------

typedef struct CC_DOC_* CC_DOC;    // ochilgan hujjat
typedef struct CC_UNDO_* CC_UNDO;  // bitta qaytariladigan amal (M2 dan boshlab)

// ---------------------------------------------------------------------------
// Xatolar
// ---------------------------------------------------------------------------

typedef enum CC_Error {
  CC_OK = 0,
  CC_ERR_UNKNOWN = 1,
  CC_ERR_NOT_INITIALIZED = 2,  // CC_Init chaqirilmagan
  CC_ERR_ARGUMENT = 3,         // NULL handle, noto'g'ri o'lcham va h.k.
  CC_ERR_FILE = 4,             // fayl topilmadi yoki o'qib bo'lmadi
  CC_ERR_FORMAT = 5,           // PDF emas yoki buzilgan
  CC_ERR_PASSWORD = 6,         // parol kerak yoki noto'g'ri
  CC_ERR_SECURITY = 7,         // qo'llab-quvvatlanmagan xavfsizlik handler'i
  CC_ERR_PAGE = 8,             // sahifa topilmadi yoki yuklanmadi
  CC_ERR_MEMORY = 9,
} CC_Error;

// Joriy thread'dagi oxirgi xato kodi. Muvaffaqiyatli chaqiruv uni CC_OK ga qaytaradi.
CC_EXPORT CC_Error CC_GetLastError(void);

// Oxirgi xatoning inson o'qiydigan tavsifi (UTF-8). Keyingi chaqiruvgacha yaroqli.
// Hech qachon NULL emas.
CC_EXPORT const char* CC_GetLastErrorMessage(void);

// ---------------------------------------------------------------------------
// Kutubxona
// ---------------------------------------------------------------------------

// Engine'ni ishga tushiradi. Bir necha marta chaqirish xavfsiz (keyingilari hech narsa
// qilmaydi). Boshqa har qanday funksiyadan oldin chaqirilishi shart.
CC_EXPORT CC_Error CC_Init(void);

// Engine'ni to'xtatadi. Barcha hujjatlar avval yopilgan bo'lishi kerak.
CC_EXPORT void CC_Shutdown(void);

// Engine versiyasi, masalan "craftcore 0.1.0 (pdfium 7xxx)". Statik satr.
CC_EXPORT const char* CC_Version(void);

// ---------------------------------------------------------------------------
// Hujjat
// ---------------------------------------------------------------------------

// PDF faylni ochadi. `path` — UTF-8 fayl yo'li. `password` — NULL yoki UTF-8 parol.
// Xato bo'lsa NULL qaytaradi (CC_ERR_FILE / CC_ERR_FORMAT / CC_ERR_PASSWORD ...).
CC_EXPORT CC_DOC CC_Doc_Open(const char* path, const char* password);

// Hujjatni yopadi va xotirani bo'shatadi. NULL berish xavfsiz.
CC_EXPORT void CC_Doc_Close(CC_DOC doc);

// Sahifalar soni; xato bo'lsa -1.
CC_EXPORT int CC_Doc_PageCount(CC_DOC doc);

// ---------------------------------------------------------------------------
// Sahifa
// ---------------------------------------------------------------------------

typedef struct CC_Size {
  double width;   // PDF punktlarida (1/72 dyuym)
  double height;
} CC_Size;

// Sahifaning ko'rinadigan o'lchami (CropBox, /Rotate hisobga olingan) punktlarda.
// Muvaffaqiyatda CC_OK, aks holda xato kodi; `out_size` faqat CC_OK da yoziladi.
CC_EXPORT CC_Error CC_Page_Size(CC_DOC doc, int page_index, CC_Size* out_size);

// ---------------------------------------------------------------------------
// Render
// ---------------------------------------------------------------------------

typedef struct CC_PixelRect {
  int32_t x;       // to'liq sahifa bitmap'idagi chap chekka (piksel)
  int32_t y;       // yuqori chekka (piksel), y pastga o'sadi
  int32_t width;   // > 0
  int32_t height;  // > 0
} CC_PixelRect;

enum {
  CC_RENDER_DEFAULT = 0,
  CC_RENDER_ANNOTATIONS = 1 << 0,  // annotatsiyalarni ham chizish
  CC_RENDER_TRANSPARENT = 1 << 1,  // fonni oq bilan to'ldirmaslik
  CC_RENDER_GRAYSCALE = 1 << 2,
  CC_RENDER_NO_SMOOTH_TEXT = 1 << 3,
  CC_RENDER_PRINTING = 1 << 4,
};

// Sahifaning bir hududini BGRA bufferga chizadi.
//
// Sahifa `scale` (piksel/punkt) bilan to'liq bitmap sifatida tasavvur qilinadi:
//   full_w = round(page_width * scale), full_h = round(page_height * scale).
// `rect` shu to'liq bitmap ichidagi hudud; natija `buffer`ning (0,0) nuqtasidan yoziladi.
// Butun sahifa uchun rect = {0, 0, full_w, full_h}. Tile render uchun rect — tile.
//
// `buffer` kamida `stride * rect.height` bayt, `stride >= rect.width * 4`.
// Piksel formati: xotirada B, G, R, A (32-bit little-endian ARGB). Oq fon bilan
// alpha doim 255. CC_RENDER_TRANSPARENT bilan alpha premultiply qilinmagan.
CC_EXPORT CC_Error CC_Render_Rect(CC_DOC doc,
                                  int page_index,
                                  double scale,
                                  CC_PixelRect rect,
                                  void* buffer,
                                  int stride,
                                  uint32_t flags);

// ---------------------------------------------------------------------------
// Matn ajratish
// ---------------------------------------------------------------------------

// Sahifa matnini UTF-8 da `buffer`ga yozadi (oxirida NUL bilan). Har doim to'liq matn
// uzunligini baytlarda (NUL'siz) qaytaradi; buffer kichik bo'lsa matn qisqartiriladi.
// Avval `buffer = NULL, capacity = 0` bilan o'lchamni so'rash mumkin. Xato bo'lsa -1.
CC_EXPORT int64_t CC_TextExtract_PageUTF8(CC_DOC doc,
                                          int page_index,
                                          char* buffer,
                                          size_t capacity);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // CRAFTCORE_H_
