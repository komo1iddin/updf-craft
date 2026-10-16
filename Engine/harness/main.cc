// craft-harness — CraftCore C API'sini buyruq satridan sinash.
//
//   craft-harness open   <in.pdf> [--password P]
//   craft-harness render <in.pdf> --page N --scale S [--annots] [--tile X,Y,W,H]
//                        [--password P] <out.png>
//   craft-harness text   <in.pdf> [--page N] [--password P]
//
// Sahifa raqamlari 1 dan boshlanadi. Faqat craftcore.h ishlatiladi — bu ilova
// ko'radigan API bilan bir xil.

#ifdef UNSAFE_BUFFERS_BUILD
#pragma allow_unsafe_buffers
#pragma allow_unsafe_libc_calls
#endif

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "craftcore.h"

namespace {

struct Options {
  std::string command;
  std::vector<std::string> positional;
  int page = 0;  // 1 dan boshlanadi; 0 = berilmagan
  double scale = 1.0;
  bool annots = false;
  bool has_tile = false;
  CC_PixelRect tile = {0, 0, 0, 0};
  std::string password;
  bool has_password = false;
};

void PrintUsage() {
  std::fprintf(stderr,
               "Foydalanish:\n"
               "  craft-harness open   <in.pdf> [--password P]\n"
               "  craft-harness render <in.pdf> --page N --scale S [--annots]\n"
               "                       [--tile X,Y,W,H] [--password P] <out.png>\n"
               "  craft-harness text   <in.pdf> [--page N] [--password P]\n"
               "Sahifa raqamlari 1 dan boshlanadi.\n");
}

// Engine xabari odatda funksiya nomini o'z ichiga oladi; bo'sh bo'lsa `what` chiqariladi.
int Fail(const char* what) {
  const char* message = CC_GetLastErrorMessage();
  std::fprintf(stderr, "xato: %s (kod %d)\n", *message ? message : what,
               static_cast<int>(CC_GetLastError()));
  return 1;
}

bool ParseArgs(int argc, char** argv, Options* opt) {
  if (argc < 2) {
    return false;
  }
  opt->command = argv[1];
  for (int i = 2; i < argc; ++i) {
    std::string arg = argv[i];
    auto next = [&](const char* name) -> const char* {
      if (i + 1 >= argc) {
        std::fprintf(stderr, "%s qiymat talab qiladi\n", name);
        return nullptr;
      }
      return argv[++i];
    };
    if (arg == "--page") {
      const char* v = next("--page");
      if (!v) return false;
      opt->page = std::atoi(v);
      if (opt->page < 1) {
        std::fprintf(stderr, "--page 1 yoki undan katta bo'lishi kerak\n");
        return false;
      }
    } else if (arg == "--scale") {
      const char* v = next("--scale");
      if (!v) return false;
      opt->scale = std::atof(v);
      if (!(opt->scale > 0.0)) {
        std::fprintf(stderr, "--scale musbat son bo'lishi kerak\n");
        return false;
      }
    } else if (arg == "--annots") {
      opt->annots = true;
    } else if (arg == "--tile") {
      const char* v = next("--tile");
      if (!v) return false;
      CC_PixelRect r;
      if (std::sscanf(v, "%d,%d,%d,%d", &r.x, &r.y, &r.width, &r.height) != 4) {
        std::fprintf(stderr, "--tile formati: X,Y,W,H\n");
        return false;
      }
      opt->tile = r;
      opt->has_tile = true;
    } else if (arg == "--password") {
      const char* v = next("--password");
      if (!v) return false;
      opt->password = v;
      opt->has_password = true;
    } else if (arg.size() > 1 && arg[0] == '-') {
      std::fprintf(stderr, "noma'lum parametr: %s\n", arg.c_str());
      return false;
    } else {
      opt->positional.push_back(arg);
    }
  }
  return true;
}

bool WritePng(const char* path, const std::vector<unsigned char>& pixels, int width,
              int height, int stride, bool transparent) {
  CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGDataProviderRef provider =
      CGDataProviderCreateWithData(nullptr, pixels.data(), pixels.size(), nullptr);
  const CGBitmapInfo info =
      static_cast<CGBitmapInfo>(kCGBitmapByteOrder32Little) |
      static_cast<CGBitmapInfo>(transparent ? kCGImageAlphaFirst : kCGImageAlphaNoneSkipFirst);
  CGImageRef image = CGImageCreate(width, height, 8, 32, stride, space, info, provider,
                                   nullptr, false, kCGRenderingIntentDefault);
  bool ok = false;
  if (image) {
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(
        nullptr, reinterpret_cast<const UInt8*>(path), std::strlen(path), false);
    CGImageDestinationRef dest =
        CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, nullptr);
    if (dest) {
      CGImageDestinationAddImage(dest, image, nullptr);
      ok = CGImageDestinationFinalize(dest);
      CFRelease(dest);
    }
    CFRelease(url);
    CGImageRelease(image);
  }
  CGDataProviderRelease(provider);
  CGColorSpaceRelease(space);
  return ok;
}

int CommandOpen(CC_DOC doc) {
  const int count = CC_Doc_PageCount(doc);
  if (count < 0) {
    return Fail("CC_Doc_PageCount");
  }
  std::printf("engine: %s\n", CC_Version());
  std::printf("sahifalar: %d\n", count);
  for (int i = 0; i < count; ++i) {
    CC_Size size;
    if (CC_Page_Size(doc, i, &size) != CC_OK) {
      return Fail("CC_Page_Size");
    }
    std::printf("  %d: %.2f x %.2f pt\n", i + 1, size.width, size.height);
  }
  return 0;
}

int CommandRender(CC_DOC doc, const Options& opt) {
  if (opt.positional.size() != 2) {
    std::fprintf(stderr, "render: kirish PDF va chiqish PNG yo'li kerak\n");
    return 2;
  }
  const char* out_path = opt.positional[1].c_str();
  const int page_index = (opt.page > 0 ? opt.page : 1) - 1;

  CC_Size size;
  if (CC_Page_Size(doc, page_index, &size) != CC_OK) {
    return Fail("CC_Page_Size");
  }
  CC_PixelRect rect = {0, 0, static_cast<int32_t>(std::lround(size.width * opt.scale)),
                       static_cast<int32_t>(std::lround(size.height * opt.scale))};
  if (opt.has_tile) {
    rect = opt.tile;
  }
  if (rect.width <= 0 || rect.height <= 0) {
    std::fprintf(stderr, "render: bo'sh hudud\n");
    return 2;
  }
  const int stride = rect.width * 4;
  std::vector<unsigned char> pixels(static_cast<size_t>(stride) * rect.height);
  const uint32_t flags = opt.annots ? CC_RENDER_ANNOTATIONS : CC_RENDER_DEFAULT;

  const auto start = std::chrono::steady_clock::now();
  if (CC_Render_Rect(doc, page_index, opt.scale, rect, pixels.data(), stride, flags) !=
      CC_OK) {
    return Fail("CC_Render_Rect");
  }
  const double ms =
      std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start)
          .count();

  if (!WritePng(out_path, pixels, rect.width, rect.height, stride, /*transparent=*/false)) {
    std::fprintf(stderr, "xato: PNG yozib bo'lmadi: %s\n", out_path);
    return 1;
  }
  std::printf("sahifa %d, scale %.3g -> %dx%d px, %.1f ms -> %s\n", page_index + 1,
              opt.scale, rect.width, rect.height, ms, out_path);
  return 0;
}

int CommandText(CC_DOC doc, const Options& opt) {
  const int count = CC_Doc_PageCount(doc);
  if (count < 0) {
    return Fail("CC_Doc_PageCount");
  }
  int first = 0;
  int last = count - 1;
  if (opt.page > 0) {
    first = last = opt.page - 1;
  }
  for (int i = first; i <= last; ++i) {
    const int64_t length = CC_TextExtract_PageUTF8(doc, i, nullptr, 0);
    if (length < 0) {
      return Fail("CC_TextExtract_PageUTF8");
    }
    std::vector<char> text(static_cast<size_t>(length) + 1, '\0');
    if (CC_TextExtract_PageUTF8(doc, i, text.data(), text.size()) < 0) {
      return Fail("CC_TextExtract_PageUTF8");
    }
    if (opt.page == 0) {
      std::printf("--- sahifa %d ---\n", i + 1);
    }
    std::printf("%s\n", text.data());
  }
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  Options opt;
  if (!ParseArgs(argc, argv, &opt) || opt.positional.empty()) {
    PrintUsage();
    return 2;
  }
  if (opt.command != "open" && opt.command != "render" && opt.command != "text") {
    std::fprintf(stderr, "noma'lum buyruq: %s\n", opt.command.c_str());
    PrintUsage();
    return 2;
  }

  if (CC_Init() != CC_OK) {
    return Fail("CC_Init");
  }
  CC_DOC doc = CC_Doc_Open(opt.positional[0].c_str(),
                           opt.has_password ? opt.password.c_str() : nullptr);
  if (!doc) {
    const int rc = Fail("CC_Doc_Open");
    CC_Shutdown();
    return rc;
  }

  int rc = 0;
  if (opt.command == "open") {
    rc = CommandOpen(doc);
  } else if (opt.command == "render") {
    rc = CommandRender(doc, opt);
  } else {
    rc = CommandText(doc, opt);
  }

  CC_Doc_Close(doc);
  CC_Shutdown();
  return rc;
}
