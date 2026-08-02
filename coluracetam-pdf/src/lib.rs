//! C-ABI shim over `pdf_inspector` for the Coluracetam app.
//!
//! One conversion entry point returning a JSON blob, so the Swift side
//! decodes a single `Codable` struct instead of holding a dozen FFI
//! accessors. Strings returned by this library are owned by Rust and must
//! be released with [`clr_string_free`].

use std::ffi::{c_char, CStr, CString};
use std::panic::{self, AssertUnwindSafe};
use std::slice;

use pdf_inspector::{process_pdf_mem, PdfType};
use serde_json::json;

fn convert(bytes: &[u8]) -> String {
    let value = match process_pdf_mem(bytes) {
        Ok(result) => json!({
            "ok": true,
            "markdown": result.markdown,
            "pdfType": match result.pdf_type {
                PdfType::TextBased => "textBased",
                PdfType::Scanned => "scanned",
                PdfType::ImageBased => "imageBased",
                PdfType::Mixed => "mixed",
            },
            "pageCount": result.page_count,
            "pagesNeedingOCR": result.pages_needing_ocr,
            "title": result.title,
            "confidence": result.confidence,
            "hasEncodingIssues": result.has_encoding_issues,
            "processingTimeMS": result.processing_time_ms,
        }),
        Err(error) => json!({ "ok": false, "error": error.to_string() }),
    };
    value.to_string()
}

fn into_c_string(mut s: String) -> *mut c_char {
    // Extracted text can legally contain NUL; CString::new would reject it.
    if s.contains('\0') {
        s = s.replace('\0', "");
    }
    match CString::new(s) {
        Ok(c) => c.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Convert a PDF (raw bytes) to Markdown plus classification metadata.
///
/// Returns a NUL-terminated UTF-8 JSON string:
/// `{"ok":true,"markdown":…,"pdfType":…,…}` or `{"ok":false,"error":…}`.
/// Release the result with [`clr_string_free`]. Returns NULL only on
/// allocation failure.
///
/// # Safety
/// `bytes` must point to `len` readable bytes (or be NULL, which yields an
/// `ok:false` result).
#[no_mangle]
pub unsafe extern "C" fn clr_pdf_convert(bytes: *const u8, len: usize) -> *mut c_char {
    if bytes.is_null() {
        return into_c_string(json!({ "ok": false, "error": "null input" }).to_string());
    }
    let data = unsafe { slice::from_raw_parts(bytes, len) };
    // A Rust panic must not unwind across the FFI boundary.
    let result = panic::catch_unwind(AssertUnwindSafe(|| convert(data)))
        .unwrap_or_else(|_| json!({ "ok": false, "error": "internal panic" }).to_string());
    into_c_string(result)
}

/// Point the CID/CJK CMap lookup at a directory (the app bundles
/// pdf-inspector's `external/bcmaps` as a resource). Without this, CJK
/// text extraction silently degrades on end-user machines.
///
/// # Safety
/// `path` must be a NUL-terminated UTF-8 string or NULL (ignored).
#[no_mangle]
pub unsafe extern "C" fn clr_pdf_set_bcmaps_dir(path: *const c_char) {
    if path.is_null() {
        return;
    }
    if let Ok(dir) = unsafe { CStr::from_ptr(path) }.to_str() {
        std::env::set_var("PDF_INSPECTOR_BCMAPS_DIR", dir);
    }
}

/// Release a string returned by this library.
///
/// # Safety
/// `ptr` must be a pointer previously returned by this library, or NULL.
#[no_mangle]
pub unsafe extern "C" fn clr_string_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(unsafe { CString::from_raw(ptr) });
    }
}
