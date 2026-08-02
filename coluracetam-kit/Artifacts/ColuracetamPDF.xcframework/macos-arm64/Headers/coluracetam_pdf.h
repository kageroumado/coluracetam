#ifndef COLURACETAM_PDF_H
#define COLURACETAM_PDF_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Convert a PDF (raw bytes) to Markdown plus classification metadata.
/// Returns a NUL-terminated UTF-8 JSON string; release with clr_string_free.
/// Returns NULL only on allocation failure.
char *_Nullable clr_pdf_convert(const uint8_t *_Nullable bytes, size_t len);

/// Point CID/CJK CMap lookup at the app's bundled bcmaps resource directory.
void clr_pdf_set_bcmaps_dir(const char *_Nullable path);

/// Release a string returned by this library.
void clr_string_free(char *_Nullable ptr);

#ifdef __cplusplus
}
#endif

#endif /* COLURACETAM_PDF_H */
