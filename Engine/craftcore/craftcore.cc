// CraftCore M0: PDFium ustidagi yupqa C qatlam.
//
// M0'da faqat PDFium'ning ommaviy API'si (public/*.h) ishlatiladi. Tahrir engine'i
// (M5) bu target'ga PDFium ichki C++ sinflari bilan ishlaydigan kodni qo'shadi —
// shuning uchun craftcore PDFium gn daraxti ichida, bir xil flag'lar bilan yig'iladi.

// C chegarasi tabiatan xom pointer va buffer bilan ishlaydi.
#ifdef UNSAFE_BUFFERS_BUILD
#pragma allow_unsafe_buffers
#pragma allow_unsafe_libc_calls
#endif

#include "craftcore.h"

#include <cmath>
#include <cstdio>
#include <cstring>
#include <limits>
#include <new>
#include <string>
#include <vector>

#include "public/fpdf_text.h"
#include "public/fpdfview.h"

#ifndef CRAFTCORE_VERSION_STRING
#define CRAFTCORE_VERSION_STRING "craftcore 0.1.0 (pdfium)"
#endif

struct CC_DOC_ {
  FPDF_DOCUMENT document = nullptr;
};

namespace {

bool g_initialized = false;

// Exit-time destructor bo'lmasligi uchun oddiy massiv (std::string emas).
constexpr size_t kMaxMessage = 512;
thread_local CC_Error t_last_error = CC_OK;
thread_local char t_last_message[kMaxMessage] = {};

void SetError(CC_Error code, const char* message) {
  t_last_error = code;
  std::snprintf(t_last_message, kMaxMessage, "%s", message ? message : "");
}

void ClearError() {
  t_last_error = CC_OK;
  t_last_message[0] = '\0';
}

// PDFium'ning FPDF_GetLastError() kodini CraftCore xatosiga aylantiradi.
CC_Error SetErrorFromPdfium(const char* context) {
  CC_Error code = CC_ERR_UNKNOWN;
  const char* reason = "noma'lum xato";
  switch (FPDF_GetLastError()) {
    case FPDF_ERR_FILE:
      code = CC_ERR_FILE;
      reason = "fayl topilmadi yoki o'qib bo'lmadi";
      break;
    case FPDF_ERR_FORMAT:
      code = CC_ERR_FORMAT;
      reason = "fayl PDF emas yoki buzilgan";
      break;
    case FPDF_ERR_PASSWORD:
      code = CC_ERR_PASSWORD;
      reason = "parol kerak yoki noto'g'ri";
      break;
    case FPDF_ERR_SECURITY:
      code = CC_ERR_SECURITY;
      reason = "qo'llab-quvvatlanmagan xavfsizlik handler'i";
      break;
    case FPDF_ERR_PAGE:
      code = CC_ERR_PAGE;
      reason = "sahifa topilmadi yoki buzilgan";
      break;
    default:
      break;
  }
  t_last_error = code;
  std::snprintf(t_last_message, kMaxMessage, "%s: %s", context, reason);
  return code;
}

bool CheckReady(CC_DOC doc) {
  if (!g_initialized) {
    SetError(CC_ERR_NOT_INITIALIZED, "CC_Init chaqirilmagan");
    return false;
  }
  if (!doc || !doc->document) {
    SetError(CC_ERR_ARGUMENT, "hujjat handle'i NULL");
    return false;
  }
  return true;
}

bool CheckPageIndex(CC_DOC doc, int page_index) {
  if (page_index < 0 || page_index >= FPDF_GetPageCount(doc->document)) {
    SetError(CC_ERR_PAGE, "sahifa indeksi chegaradan tashqarida");
    return false;
  }
  return true;
}

// FPDF_PAGE uchun RAII.
class ScopedPage {
 public:
  ScopedPage(FPDF_DOCUMENT doc, int index) : page_(FPDF_LoadPage(doc, index)) {}
  ~ScopedPage() {
    if (page_) {
      FPDF_ClosePage(page_);
    }
  }
  ScopedPage(const ScopedPage&) = delete;
  ScopedPage& operator=(const ScopedPage&) = delete;
  FPDF_PAGE get() const { return page_; }

 private:
  FPDF_PAGE page_;
};

// UTF-16LE (surrogate juftliklari bilan) -> UTF-8.
std::string Utf16ToUtf8(const unsigned short* data, size_t length) {
  std::string out;
  out.reserve(length);
  for (size_t i = 0; i < length; ++i) {
    uint32_t cp = data[i];
    if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < length && data[i + 1] >= 0xDC00 &&
        data[i + 1] <= 0xDFFF) {
      cp = 0x10000 + ((cp - 0xD800) << 10) + (data[i + 1] - 0xDC00);
      ++i;
    } else if (cp >= 0xD800 && cp <= 0xDFFF) {
      cp = 0xFFFD;  // juftsiz surrogate
    }
    if (cp < 0x80) {
      out.push_back(static_cast<char>(cp));
    } else if (cp < 0x800) {
      out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
      out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else if (cp < 0x10000) {
      out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
      out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
      out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else {
      out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
      out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
      out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
      out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    }
  }
  return out;
}

}  // namespace

extern "C" {

CC_Error CC_GetLastError(void) {
  return t_last_error;
}

const char* CC_GetLastErrorMessage(void) {
  return t_last_message;
}

CC_Error CC_Init(void) {
  if (!g_initialized) {
    FPDF_LIBRARY_CONFIG config;
    std::memset(&config, 0, sizeof(config));
    config.version = 2;  // V8 yo'q: m_pIsolate = NULL, m_v8EmbedderSlot = 0
    FPDF_InitLibraryWithConfig(&config);
    g_initialized = true;
  }
  ClearError();
  return CC_OK;
}

void CC_Shutdown(void) {
  if (g_initialized) {
    FPDF_DestroyLibrary();
    g_initialized = false;
  }
  ClearError();
}

const char* CC_Version(void) {
  return CRAFTCORE_VERSION_STRING;
}

CC_DOC CC_Doc_Open(const char* path, const char* password) {
  if (!g_initialized) {
    SetError(CC_ERR_NOT_INITIALIZED, "CC_Init chaqirilmagan");
    return nullptr;
  }
  if (!path || !*path) {
    SetError(CC_ERR_ARGUMENT, "fayl yo'li bo'sh");
    return nullptr;
  }
  FPDF_DOCUMENT document = FPDF_LoadDocument(path, password);
  if (!document) {
    SetErrorFromPdfium("CC_Doc_Open");
    return nullptr;
  }
  CC_DOC doc = new (std::nothrow) CC_DOC_;
  if (!doc) {
    FPDF_CloseDocument(document);
    SetError(CC_ERR_MEMORY, "xotira yetmadi");
    return nullptr;
  }
  doc->document = document;
  ClearError();
  return doc;
}

void CC_Doc_Close(CC_DOC doc) {
  if (!doc) {
    return;
  }
  if (doc->document) {
    FPDF_CloseDocument(doc->document);
  }
  delete doc;
  ClearError();
}

int CC_Doc_PageCount(CC_DOC doc) {
  if (!CheckReady(doc)) {
    return -1;
  }
  ClearError();
  return FPDF_GetPageCount(doc->document);
}

CC_Error CC_Page_Size(CC_DOC doc, int page_index, CC_Size* out_size) {
  if (!CheckReady(doc)) {
    return t_last_error;
  }
  if (!out_size) {
    SetError(CC_ERR_ARGUMENT, "out_size NULL");
    return t_last_error;
  }
  if (!CheckPageIndex(doc, page_index)) {
    return t_last_error;
  }
  FS_SIZEF size;
  if (!FPDF_GetPageSizeByIndexF(doc->document, page_index, &size)) {
    return SetErrorFromPdfium("CC_Page_Size");
  }
  out_size->width = size.width;
  out_size->height = size.height;
  ClearError();
  return CC_OK;
}

CC_Error CC_Render_Rect(CC_DOC doc,
                        int page_index,
                        double scale,
                        CC_PixelRect rect,
                        void* buffer,
                        int stride,
                        uint32_t flags) {
  if (!CheckReady(doc)) {
    return t_last_error;
  }
  if (!buffer || rect.width <= 0 || rect.height <= 0 || stride < rect.width * 4 ||
      !(scale > 0.0) || !std::isfinite(scale)) {
    SetError(CC_ERR_ARGUMENT, "noto'g'ri buffer, rect, stride yoki scale");
    return t_last_error;
  }
  if (!CheckPageIndex(doc, page_index)) {
    return t_last_error;
  }

  ScopedPage page(doc->document, page_index);
  if (!page.get()) {
    return SetErrorFromPdfium("CC_Render_Rect");
  }

  const double full_w = std::round(FPDF_GetPageWidthF(page.get()) * scale);
  const double full_h = std::round(FPDF_GetPageHeightF(page.get()) * scale);
  constexpr double kMaxDim = std::numeric_limits<int>::max() / 4;
  if (full_w < 1 || full_h < 1 || full_w > kMaxDim || full_h > kMaxDim) {
    SetError(CC_ERR_ARGUMENT, "scale juda katta yoki juda kichik");
    return t_last_error;
  }

  FPDF_BITMAP bitmap =
      FPDFBitmap_CreateEx(rect.width, rect.height, FPDFBitmap_BGRA, buffer, stride);
  if (!bitmap) {
    SetError(CC_ERR_MEMORY, "bitmap yaratib bo'lmadi");
    return t_last_error;
  }
  const FPDF_DWORD fill = (flags & CC_RENDER_TRANSPARENT) ? 0x00000000 : 0xFFFFFFFF;
  FPDFBitmap_FillRect(bitmap, 0, 0, rect.width, rect.height, fill);

  int render_flags = 0;
  if (flags & CC_RENDER_ANNOTATIONS) {
    render_flags |= FPDF_ANNOT;
  }
  if (flags & CC_RENDER_GRAYSCALE) {
    render_flags |= FPDF_GRAYSCALE;
  }
  if (flags & CC_RENDER_NO_SMOOTH_TEXT) {
    render_flags |= FPDF_RENDER_NO_SMOOTHTEXT;
  }
  if (flags & CC_RENDER_PRINTING) {
    render_flags |= FPDF_PRINTING;
  }

  // Butun sahifa (full_w x full_h) bitmap'ga -rect.x, -rect.y siljish bilan joylanadi;
  // PDFium bitmap chegarasidan tashqarini kesib tashlaydi.
  FPDF_RenderPageBitmap(bitmap, page.get(), -rect.x, -rect.y, static_cast<int>(full_w),
                        static_cast<int>(full_h), /*rotate=*/0, render_flags);
  FPDFBitmap_Destroy(bitmap);
  ClearError();
  return CC_OK;
}

int64_t CC_TextExtract_PageUTF8(CC_DOC doc, int page_index, char* buffer, size_t capacity) {
  if (!CheckReady(doc)) {
    return -1;
  }
  if (!buffer && capacity != 0) {
    SetError(CC_ERR_ARGUMENT, "buffer NULL, capacity esa 0 emas");
    return -1;
  }
  if (!CheckPageIndex(doc, page_index)) {
    return -1;
  }
  ScopedPage page(doc->document, page_index);
  if (!page.get()) {
    SetErrorFromPdfium("CC_TextExtract_PageUTF8");
    return -1;
  }
  FPDF_TEXTPAGE text_page = FPDFText_LoadPage(page.get());
  if (!text_page) {
    SetError(CC_ERR_PAGE, "matn sahifasini yuklab bo'lmadi");
    return -1;
  }
  const int count = FPDFText_CountChars(text_page);
  std::string utf8;
  if (count > 0) {
    std::vector<unsigned short> utf16(static_cast<size_t>(count) + 1, 0);
    const int written = FPDFText_GetText(text_page, 0, count, utf16.data());
    // `written` NUL'ni ham o'z ichiga oladi.
    const size_t length = written > 0 ? static_cast<size_t>(written - 1) : 0;
    utf8 = Utf16ToUtf8(utf16.data(), length);
  }
  FPDFText_ClosePage(text_page);

  if (capacity > 0) {
    size_t n = utf8.size() < capacity - 1 ? utf8.size() : capacity - 1;
    // Ko'p baytli belgini o'rtasidan kesmaslik.
    while (n > 0 && n < utf8.size() && (static_cast<unsigned char>(utf8[n]) & 0xC0) == 0x80) {
      --n;
    }
    std::memcpy(buffer, utf8.data(), n);
    buffer[n] = '\0';
  }
  ClearError();
  return static_cast<int64_t>(utf8.size());
}

}  // extern "C"
