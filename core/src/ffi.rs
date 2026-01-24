//! C FFI exports for cross-platform integration
//!
//! This module provides a C-compatible API that can be called from:
//! - Android via JNI
//! - iOS via Swift/Objective-C FFI
//! - WASM (with wasm-bindgen, future)
//!
//! All functions use C-compatible types and return error codes where appropriate.

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_longlong};

use std::sync::Mutex;

use crate::{get_definition, init, search_with_offset, DictHandle};

/// Global handle storage for FFI
///
/// This is a simple approach - for a more robust solution, consider
/// using a handle map with integer keys.
static HANDLE: Mutex<Option<DictHandle>> = Mutex::new(None);

/// Error codes returned by FFI functions
#[repr(C)]
pub enum FfiError {
    /// Operation succeeded
    Success = 0,
    /// Null pointer passed as argument
    NullPointer = 1,
    /// Invalid UTF-8 string
    InvalidUtf8 = 2,
    /// Database initialization failed
    InitFailed = 3,
    /// Database not initialized
    NotInitialized = 4,
    /// Search failed
    SearchFailed = 5,
    /// JSON serialization failed
    JsonFailed = 6,
}

/// Initialize the dictionary database
///
/// # Safety
///
/// `db_path` must be a valid null-terminated C string.
///
/// # Returns
///
/// 0 on success, non-zero error code on failure.
#[no_mangle]
pub unsafe extern "C" fn dict_init(db_path: *const c_char) -> c_int {
    if db_path.is_null() {
        return FfiError::NullPointer as c_int;
    }

    let path = match CStr::from_ptr(db_path).to_str() {
        Ok(s) => s,
        Err(_) => return FfiError::InvalidUtf8 as c_int,
    };

    match init(path) {
        Ok(handle) => {
            let mut guard = HANDLE.lock().unwrap();
            *guard = Some(handle);
            FfiError::Success as c_int
        }
        Err(e) => {
            log::error!("Failed to initialize database: {}", e);
            FfiError::InitFailed as c_int
        }
    }
}

/// Search for words matching a query
///
/// # Safety
///
/// - `query` must be a valid null-terminated C string
/// - `out_json` must be a valid pointer to store the result
/// - The caller is responsible for freeing the returned string with `dict_free_string`
///
/// # Returns
///
/// 0 on success, non-zero error code on failure.
/// On success, `*out_json` will be set to a JSON array of search results.
#[no_mangle]
pub unsafe extern "C" fn dict_search(
    query: *const c_char,
    limit: c_int,
    offset: c_int,
    out_json: *mut *mut c_char,
) -> c_int {
    if query.is_null() || out_json.is_null() {
        return FfiError::NullPointer as c_int;
    }

    let query_str = match CStr::from_ptr(query).to_str() {
        Ok(s) => s,
        Err(_) => return FfiError::InvalidUtf8 as c_int,
    };

    let guard = HANDLE.lock().unwrap();
    let handle = match guard.as_ref() {
        Some(h) => h,
        None => return FfiError::NotInitialized as c_int,
    };

    let results = search_with_offset(handle, query_str, limit as u32, offset as u32);

    // Serialize results to JSON
    let json = match serde_json::to_string(&results) {
        Ok(j) => j,
        Err(_) => return FfiError::JsonFailed as c_int,
    };

    // Convert to C string
    let c_string = match CString::new(json) {
        Ok(s) => s,
        Err(_) => return FfiError::JsonFailed as c_int,
    };

    *out_json = c_string.into_raw();
    FfiError::Success as c_int
}

/// Get the full definition for a word by ID
///
/// # Safety
///
/// - `out_json` must be a valid pointer to store the result
/// - The caller is responsible for freeing the returned string with `dict_free_string`
///
/// # Returns
///
/// 0 on success (definition found), non-zero error code on failure.
/// On success, `*out_json` will be set to a JSON object with the full definition.
/// If the word is not found, returns success with `*out_json` set to "null".
#[no_mangle]
pub unsafe extern "C" fn dict_get_definition(
    word_id: c_longlong,
    out_json: *mut *mut c_char,
) -> c_int {
    if out_json.is_null() {
        return FfiError::NullPointer as c_int;
    }

    let guard = HANDLE.lock().unwrap();
    let handle = match guard.as_ref() {
        Some(h) => h,
        None => return FfiError::NotInitialized as c_int,
    };

    let definition = get_definition(handle, word_id);

    // Serialize to JSON (will be "null" if None)
    let json = match serde_json::to_string(&definition) {
        Ok(j) => j,
        Err(_) => return FfiError::JsonFailed as c_int,
    };

    let c_string = match CString::new(json) {
        Ok(s) => s,
        Err(_) => return FfiError::JsonFailed as c_int,
    };

    *out_json = c_string.into_raw();
    FfiError::Success as c_int
}

/// Free a string returned by dict_search or dict_get_definition
///
/// # Safety
///
/// `ptr` must be a pointer returned by a dict_* function, or null.
#[no_mangle]
pub unsafe extern "C" fn dict_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

/// Close the dictionary and free resources
///
/// # Returns
///
/// 0 on success.
#[no_mangle]
pub extern "C" fn dict_close() -> c_int {
    let mut guard = HANDLE.lock().unwrap();
    *guard = None;
    FfiError::Success as c_int
}

/// Get the library version
///
/// # Safety
///
/// Returns a pointer to a static string. Do not free this pointer.
#[no_mangle]
pub extern "C" fn dict_version() -> *const c_char {
    // Include version from Cargo.toml at compile time
    static VERSION: &[u8] = concat!(env!("CARGO_PKG_VERSION"), "\0").as_bytes();
    VERSION.as_ptr() as *const c_char
}

// ============================================================================
// JNI bindings for Android
// ============================================================================

#[cfg(target_os = "android")]
mod android {
    use std::ptr;

    use jni::objects::{JClass, JString};
    use jni::sys::{jint, jlong, jstring};
    use jni::JNIEnv;

    use super::*;

    // Re-export android_logger for use in this module
    use android_logger;

    /// JNI: Initialize the dictionary
    ///
    /// Kotlin signature: external fun init(dbPath: String): Int
    #[no_mangle]
    pub extern "system" fn Java_org_example_dictapp_DictCore_init(
        mut env: JNIEnv,
        _class: JClass,
        db_path: JString,
    ) -> jint {
        let path: String = match env.get_string(&db_path) {
            Ok(s) => s.into(),
            Err(_) => return FfiError::InvalidUtf8 as jint,
        };

        match init(&path) {
            Ok(handle) => {
                let mut guard = HANDLE.lock().unwrap();
                *guard = Some(handle);
                FfiError::Success as jint
            }
            Err(e) => {
                log::error!("Failed to initialize database: {}", e);
                FfiError::InitFailed as jint
            }
        }
    }

    /// JNI: Search for words
    ///
    /// Kotlin signature: external fun search(query: String, limit: Int, offset: Int): String
    #[no_mangle]
    pub extern "system" fn Java_org_example_dictapp_DictCore_search(
        mut env: JNIEnv,
        _class: JClass,
        query: JString,
        limit: jint,
        offset: jint,
    ) -> jstring {
        let query_str: String = match env.get_string(&query) {
            Ok(s) => s.into(),
            Err(_) => return ptr::null_mut(),
        };

        let guard = HANDLE.lock().unwrap();
        let handle = match guard.as_ref() {
            Some(h) => h,
            None => return ptr::null_mut(),
        };

        let results = search_with_offset(handle, &query_str, limit as u32, offset as u32);

        let json = match serde_json::to_string(&results) {
            Ok(j) => j,
            Err(_) => return ptr::null_mut(),
        };

        match env.new_string(&json) {
            Ok(s) => s.into_raw(),
            Err(_) => ptr::null_mut(),
        }
    }

    /// JNI: Get full definition
    ///
    /// Kotlin signature: external fun getDefinition(wordId: Long): String?
    #[no_mangle]
    pub extern "system" fn Java_org_example_dictapp_DictCore_getDefinition(
        env: JNIEnv,
        _class: JClass,
        word_id: jlong,
    ) -> jstring {
        let guard = HANDLE.lock().unwrap();
        let handle = match guard.as_ref() {
            Some(h) => h,
            None => return ptr::null_mut(),
        };

        let definition = get_definition(handle, word_id);

        let json = match serde_json::to_string(&definition) {
            Ok(j) => j,
            Err(_) => return ptr::null_mut(),
        };

        match env.new_string(&json) {
            Ok(s) => s.into_raw(),
            Err(_) => ptr::null_mut(),
        }
    }

    /// JNI: Close the dictionary
    ///
    /// Kotlin signature: external fun close()
    #[no_mangle]
    pub extern "system" fn Java_org_example_dictapp_DictCore_close(_env: JNIEnv, _class: JClass) {
        let mut guard = HANDLE.lock().unwrap();
        *guard = None;
    }

    /// Called when the native library is loaded by System.loadLibrary()
    ///
    /// This sets up:
    /// - Android logging (so log::* macros appear in logcat)
    /// - Panic hook (to log panics before they crash the app)
    #[no_mangle]
    pub extern "system" fn JNI_OnLoad(_vm: jni::JavaVM, _reserved: *mut std::ffi::c_void) -> jint {
        // Initialize Android logger
        android_logger::init_once(
            android_logger::Config::default()
                .with_max_level(log::LevelFilter::Debug)
                .with_tag("DictCore"),
        );

        // Set panic hook to log panics before they crash
        std::panic::set_hook(Box::new(|info| {
            let msg = if let Some(s) = info.payload().downcast_ref::<&str>() {
                s.to_string()
            } else if let Some(s) = info.payload().downcast_ref::<String>() {
                s.clone()
            } else {
                "Unknown panic".to_string()
            };

            let location = info
                .location()
                .map(|l| format!("{}:{}:{}", l.file(), l.line(), l.column()))
                .unwrap_or_else(|| "unknown".to_string());

            log::error!("PANIC at {}: {}", location, msg);
        }));

        log::info!("DictCore native library loaded");

        jni::sys::JNI_VERSION_1_6
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;
    use std::ptr;

    #[test]
    fn test_dict_version() {
        let version = dict_version();
        let version_str = unsafe { CStr::from_ptr(version) }.to_str().unwrap();
        assert!(!version_str.is_empty());
    }

    #[test]
    fn test_null_pointer_checks() {
        unsafe {
            assert_eq!(dict_init(ptr::null()), FfiError::NullPointer as c_int);
            assert_eq!(
                dict_search(ptr::null(), 10, 0, ptr::null_mut()),
                FfiError::NullPointer as c_int
            );
        }
    }

    #[test]
    fn test_not_initialized() {
        let query = CString::new("test").unwrap();
        let mut out: *mut c_char = ptr::null_mut();

        unsafe {
            // Ensure handle is cleared
            dict_close();

            let result = dict_search(query.as_ptr(), 10, 0, &mut out);
            assert_eq!(result, FfiError::NotInitialized as c_int);
        }
    }
}
