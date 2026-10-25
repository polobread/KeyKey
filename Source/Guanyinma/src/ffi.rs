//! Versioned C boundary for model queries, input sessions and managed user data.
//!
//! Handles own Rust allocations. Callers own all copied output buffers; no
//! SQLite pointers or Rust collection layouts cross the boundary.

use crate::database::{DatabaseError, ModelDatabase, Table};
use crate::engine::{EngineError, InputOperation, InputSession, SessionConfig, SessionSnapshot};
use crate::user_archive::UserArchive;
use crate::user_store::UserSnapshot;
use crate::CandidateFilter;
use serde::Serialize;
use std::cell::RefCell;
use std::ffi::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::slice;
use std::str;
use std::sync::Mutex;

pub const GUANYINMA_OK: i32 = 0;
pub const GUANYINMA_INVALID_ARGUMENT: i32 = 1;
pub const GUANYINMA_INVALID_UTF8: i32 = 2;
pub const GUANYINMA_DATABASE_ERROR: i32 = 3;
pub const GUANYINMA_SCHEMA_ERROR: i32 = 4;
pub const GUANYINMA_BUFFER_TOO_SMALL: i32 = 5;
pub const GUANYINMA_PANIC: i32 = 6;

pub const GUANYINMA_QUERY_TRADITIONAL: u32 = 1;
pub const GUANYINMA_QUERY_CANGJIE: u32 = 2;
pub const GUANYINMA_QUERY_SIMPLEX: u32 = 3;
pub const GUANYINMA_QUERY_UNIGRAMS: u32 = 4;
pub const GUANYINMA_QUERY_BIGRAMS: u32 = 5;

const ABI_VERSION: u32 = 1;

thread_local! {
    static LAST_ERROR: RefCell<String> = const { RefCell::new(String::new()) };
}

/// Opaque in C. Queries share this immutable handle and synchronize internally.
pub struct GuanyinmaDatabase {
    database: Mutex<ModelDatabase>,
}

/// Synchronous caller-owned candidate capability callback; absent means accept all.
pub type GuanyinmaCandidateFilter =
    Option<unsafe extern "C" fn(*mut c_void, *const u8, usize) -> i32>;

struct NativeCandidateFilter {
    callback: unsafe extern "C" fn(*mut c_void, *const u8, usize) -> i32,
    context: *mut c_void,
}

// SAFETY: The C caller must keep callback/context valid until session_close,
// including when session calls move between threads. Session operations are
// serialized; sharing context with other sessions requires caller synchronization.
unsafe impl Send for NativeCandidateFilter {}
// SAFETY: The same caller contract covers concurrent access through other
// sessions. The core never dereferences context or calls outside a session call.
unsafe impl Sync for NativeCandidateFilter {}

impl NativeCandidateFilter {
    fn accepts(&self, text: &str) -> bool {
        // SAFETY: The callback and context are retained by the caller for the
        // session lifetime. This borrowed UTF-8 span stays live for this call.
        // The callback must not unwind or reenter the same session.
        unsafe { (self.callback)(self.context, text.as_ptr(), text.len()) != 0 }
    }
}

/// Opaque in C. Each input session owns its engine and synchronizes operations.
pub struct GuanyinmaSession {
    session: Mutex<InputSession>,
}

/// Opaque in C. The snapshot is immutable and independent of its source handle.
pub struct GuanyinmaResult {
    json: Vec<u8>,
    row_count: usize,
}

#[derive(Debug)]
struct FfiError {
    code: i32,
    message: String,
}

impl FfiError {
    fn invalid(message: impl Into<String>) -> Self {
        Self {
            code: GUANYINMA_INVALID_ARGUMENT,
            message: message.into(),
        }
    }
}

impl From<DatabaseError> for FfiError {
    fn from(error: DatabaseError) -> Self {
        let code = match &error {
            DatabaseError::InvalidInput(_) => GUANYINMA_INVALID_ARGUMENT,
            DatabaseError::Open(_) | DatabaseError::Query(_) => GUANYINMA_DATABASE_ERROR,
            DatabaseError::Schema(_) | DatabaseError::InvalidData(_) => GUANYINMA_SCHEMA_ERROR,
        };
        Self {
            code,
            message: error.to_string(),
        }
    }
}

impl From<EngineError> for FfiError {
    fn from(error: EngineError) -> Self {
        match error {
            EngineError::InvalidInput(message) => Self::invalid(message),
            EngineError::Database(error) => error.into(),
        }
    }
}

// Diagnostics must never turn an otherwise-contained failure into another
// unwind. TLS may be unavailable during thread teardown or already borrowed.
fn diagnostic(message: Option<String>) {
    let _ = LAST_ERROR.try_with(|last| {
        if let Ok(mut last) = last.try_borrow_mut() {
            match message {
                Some(message) => *last = message,
                None => last.clear(),
            }
        }
    });
}

fn boundary(action: impl FnOnce() -> Result<(), FfiError>) -> i32 {
    match catch_unwind(AssertUnwindSafe(action)) {
        Ok(Ok(())) => {
            diagnostic(None);
            GUANYINMA_OK
        }
        Ok(Err(error)) => {
            diagnostic(Some(error.message));
            error.code
        }
        Err(_) => {
            diagnostic(Some("Guanyinma caught an internal panic".to_owned()));
            GUANYINMA_PANIC
        }
    }
}

/// The caller guarantees a readable span if length is nonzero.
unsafe fn input<'a>(
    data: *const u8,
    length: usize,
    description: &str,
) -> Result<&'a str, FfiError> {
    if length > isize::MAX as usize {
        return Err(FfiError::invalid(format!("{description} is too long")));
    }
    let bytes = if length == 0 {
        &[]
    } else {
        if data.is_null() {
            return Err(FfiError::invalid(format!("{description} pointer is null")));
        }
        // SAFETY: Nonempty spans are bounded above and their readability is a
        // documented caller obligation. No slice is formed from null + zero.
        unsafe { slice::from_raw_parts(data, length) }
    };
    let text = str::from_utf8(bytes).map_err(|_| FfiError {
        code: GUANYINMA_INVALID_UTF8,
        message: format!("{description} is not valid UTF-8"),
    })?;
    if text.contains('\0') {
        return Err(FfiError::invalid(format!(
            "{description} contains an embedded NUL"
        )));
    }
    Ok(text)
}

/// Copies only when the whole NUL-terminated output fits.
unsafe fn copy_output(
    bytes: &[u8],
    destination: *mut u8,
    capacity: usize,
    required: *mut usize,
) -> Result<(), FfiError> {
    if required.is_null() {
        return Err(FfiError::invalid("required-length pointer is null"));
    }
    // SAFETY: The caller provides a writable, aligned size_t output.
    unsafe { required.write(0) };
    if capacity > isize::MAX as usize {
        return Err(FfiError::invalid("output capacity is too large"));
    }
    if destination.is_null() && capacity != 0 {
        return Err(FfiError::invalid("output pointer is null"));
    }
    let needed = bytes
        .len()
        .checked_add(1)
        .filter(|needed| *needed <= isize::MAX as usize)
        .ok_or_else(|| FfiError::invalid("output is too large"))?;
    // SAFETY: The same required-length output remains writable.
    unsafe { required.write(needed) };
    if capacity < needed {
        return Err(FfiError {
            code: GUANYINMA_BUFFER_TOO_SMALL,
            message: format!("output needs {needed} bytes including the trailing NUL"),
        });
    }
    // A null pointer with zero capacity has already returned BUFFER_TOO_SMALL.
    // SAFETY: Callers supply a writable, nonoverlapping destination of capacity
    // bytes. We write only needed bytes after checking the complete capacity.
    unsafe {
        ptr::copy_nonoverlapping(bytes.as_ptr(), destination, bytes.len());
        destination.add(bytes.len()).write(0);
    }
    Ok(())
}

#[derive(Serialize)]
struct QuerySnapshot<'a, T> {
    schema_version: u32,
    kind: &'static str,
    key: &'a str,
    rows: &'a [T],
}

fn snapshot<T: Serialize>(
    kind: &'static str,
    key: &str,
    rows: &[T],
) -> Result<GuanyinmaResult, FfiError> {
    let json = serde_json::to_vec(&QuerySnapshot {
        schema_version: ABI_VERSION,
        kind,
        key,
        rows,
    })
    .map_err(|error| FfiError {
        code: GUANYINMA_DATABASE_ERROR,
        message: format!("could not serialize model rows: {error}"),
    })?;
    Ok(GuanyinmaResult {
        json,
        row_count: rows.len(),
    })
}

fn session_result(snapshot: &SessionSnapshot) -> Result<GuanyinmaResult, FfiError> {
    let json = serde_json::to_vec(snapshot).map_err(|error| FfiError {
        code: GUANYINMA_DATABASE_ERROR,
        message: format!("could not serialize input snapshot: {error}"),
    })?;
    Ok(GuanyinmaResult {
        json,
        row_count: snapshot.candidates.len(),
    })
}

/// Opens an independently owned input session over the shared read-only model.
///
/// An empty configuration span uses SessionConfig::default; nonempty JSON is
/// decoded strictly before the session is opened.
///
/// # Safety
/// Nonempty path/config spans must be readable for their lengths. output must
/// point to a writable, aligned unused handle slot and not overlap the inputs.
/// The returned handle must later be consumed by session_close.
#[no_mangle]
pub unsafe extern "C" fn guanyinma_session_open(
    path: *const u8,
    path_length: usize,
    config: *const u8,
    config_length: usize,
    output: *mut *mut GuanyinmaSession,
) -> i32 {
    // SAFETY: The same input/output obligations apply; no callback is retained.
    unsafe {
        guanyinma_session_open_with_candidate_filter(
            path,
            path_length,
            config,
            config_length,
            None,
            ptr::null_mut(),
            output,
        )
    }
}

/// Opens an input session with a frontend-supplied candidate capability check.
///
/// A missing callback has exactly the legacy open behavior. The callback is
/// runtime-only and is never serialized in configuration, snapshots or backups.
///
/// # Safety
/// The path/config/output contract is identical to session_open. callback and
/// filter_context must remain valid until close, including on whichever thread
/// performs a serialized session call. The callback receives a borrowed UTF-8
/// span, must return synchronously, and must not unwind or reenter this session.
/// Shared contexts require caller synchronization across different sessions.
#[no_mangle]
pub unsafe extern "C" fn guanyinma_session_open_with_candidate_filter(
    path: *const u8,
    path_length: usize,
    config: *const u8,
    config_length: usize,
    filter: GuanyinmaCandidateFilter,
    filter_context: *mut c_void,
    output: *mut *mut GuanyinmaSession,
) -> i32 {
    boundary(|| {
        if output.is_null() {
            return Err(FfiError::invalid("session output pointer is null"));
        }
        // SAFETY: output is a writable unused handle slot by caller contract.
        unsafe { output.write(ptr::null_mut()) };
        // SAFETY: input validates span shape/UTF-8; readability is caller-owned.
        let path = unsafe { input(path, path_length, "database path") }?;
        if path.is_empty() {
            return Err(FfiError::invalid("database path is empty"));
        }
        // SAFETY: The same span contract applies to the configuration.
        let config = unsafe { input(config, config_length, "session configuration") }?;
        let config = if config.is_empty() {
            SessionConfig::default()
        } else {
            serde_json::from_str::<SessionConfig>(config).map_err(|error| {
                FfiError::invalid(format!("invalid session configuration: {error}"))
            })?
        };
        let filter = match filter {
            Some(callback) => {
                let native = NativeCandidateFilter {
                    callback,
                    context: filter_context,
                };
                // Calling a method captures the whole wrapper, preserving its
                // documented Send/Sync contract rather than capturing raw fields.
                CandidateFilter::new(move |text| native.accepts(text))
            }
            None => CandidateFilter::new(|_| true),
        };
        let session = InputSession::open_with_candidate_filter(path, config, filter)?;
        let handle = Box::new(GuanyinmaSession {
            session: Mutex::new(session),
        });
        // SAFETY: The unused output slot receives unique ownership.
        unsafe { output.write(Box::into_raw(handle)) };
        Ok(())
    })
}

/// Applies one strictly decoded operation and returns its owned snapshot.
///
/// # Safety
/// session is a live handle; it may be used concurrently but not closed during
/// this call. A nonempty JSON span must be readable for operation_length bytes.
/// output must be a writable, aligned unused result slot, separate from inputs.
#[no_mangle]
pub unsafe extern "C" fn guanyinma_session_apply(
    session: *const GuanyinmaSession,
    operation: *const u8,
    operation_length: usize,
    output: *mut *mut GuanyinmaResult,
) -> i32 {
    boundary(|| {
        if output.is_null() {
            return Err(FfiError::invalid("result output pointer is null"));
        }
        // SAFETY: output is a writable unused slot by caller contract.
        unsafe { output.write(ptr::null_mut()) };
        if session.is_null() {
            return Err(FfiError::invalid("session handle is null"));
        }
        // Decode before locking/mutating the input state.
        // SAFETY: input validates the representation of the caller-owned span.
        let operation = unsafe { input(operation, operation_length, "input operation") }?;
        let operation = serde_json::from_str::<InputOperation>(operation)
            .map_err(|error| FfiError::invalid(format!("invalid input operation: {error}")))?;
        // SAFETY: The caller retains this allocation throughout the call.
        let handle = unsafe { &*session };
        let mut session = handle.session.lock().map_err(|_| FfiError {
            code: GUANYINMA_PANIC,
            message: "input session was invalidated by an internal panic".to_owned(),
        })?;
        let snapshot = session.apply(operation)?;
        let result = session_result(&snapshot)?;
        drop(session);
        // SAFETY: The result owns its bytes independently of the engine.
        unsafe { output.write(Box::into_raw(Box::new(result))) };
        Ok(())
    })
}

/// Validate a portable user-data archive without opening a model or user store.
///
/// # Safety
/// A nonempty archive span must remain readable for archive_length bytes.
/// The UTF-8/NUL/span contract matches the other string-taking entry points.
#[no_mangle]
pub unsafe extern "C" fn guanyinma_user_archive_validate(
    archive: *const u8,
    archive_length: usize,
) -> i32 {
    boundary(|| {
        // SAFETY: input validates the caller-owned span representation.
        let archive = unsafe { input(archive, archive_length, "user archive") }?;
        let archive = serde_json::from_str::<UserArchive>(archive)
            .map_err(|error| FfiError::invalid(format!("invalid user archive: {error}")))?;
        archive.validate()?;
        Ok(())
    })
}

/// Copies the current state without emitting any new host effects.
///
/// # Safety
/// session is live and not closed concurrently. output is a writable, aligned
/// unused result slot and does not overlap the session.
#[no_mangle]
pub unsafe extern "C" fn guanyinma_session_snapshot(
    session: *const GuanyinmaSession,
    output: *mut *mut GuanyinmaResult,
) -> i32 {
    boundary(|| {
        if output.is_null() {
            return Err(FfiError::invalid("result output pointer is null"));
        }
        // SAFETY: output is a writable unused slot by caller contract.
        unsafe { output.write(ptr::null_mut()) };
        if session.is_null() {
            return Err(FfiError::invalid("session handle is null"));
        }
        // SAFETY: The caller keeps the shared allocation live.
        let handle = unsafe { &*session };
        let session = handle.session.lock().map_err(|_| FfiError {
            code: GUANYINMA_PANIC,
            message: "input session was invalidated by an internal panic".to_owned(),
        })?;
        let result = session_result(&session.snapshot())?;
        drop(session);
        // SAFETY: This freshly allocated result transfers unique ownership.
        unsafe { output.write(Box::into_raw(Box::new(result))) };
        Ok(())
    })
}

/// Read a consistent user-data snapshot for an editor/export without host effects.
///
/// # Safety
/// session is live and not closed concurrently. output is an aligned writable
/// unused result slot, distinct from the session allocation.
#[no_mangle]
pub unsafe extern "C" fn guanyinma_session_user_data(
    session: *const GuanyinmaSession,
    output: *mut *mut GuanyinmaResult,
) -> i32 {
    boundary(|| {
        if output.is_null() {
            return Err(FfiError::invalid("result output pointer is null"));
        }
        // SAFETY: output is a writable unused slot by caller contract.
        unsafe { output.write(ptr::null_mut()) };
        if session.is_null() {
            return Err(FfiError::invalid("session handle is null"));
        }
        // SAFETY: The caller keeps this session allocation live for the call.
        let handle = unsafe { &*session };
        let session = handle.session.lock().map_err(|_| FfiError {
            code: GUANYINMA_PANIC,
            message: "input session was invalidated by an internal panic".to_owned(),
        })?;
        let data = session.user_data()?;
        #[derive(Serialize)]
        struct UserDataResult<'a> {
            schema_version: u32,
            kind: &'static str,
            data: &'a UserSnapshot,
        }
        let json = serde_json::to_vec(&UserDataResult {
            schema_version: ABI_VERSION,
            kind: "user_data",
            data: &data,
        })
        .map_err(|error| FfiError {
            code: GUANYINMA_DATABASE_ERROR,
            message: format!("could not serialize user data: {error}"),
        })?;
        let result = GuanyinmaResult {
            json,
            row_count: data.phrases.len(),
        };
        drop(session);
        // SAFETY: The fresh immutable result transfers ownership to this slot.
        unsafe { output.write(Box::into_raw(Box::new(result))) };
        Ok(())
    })
}

/// Consumes a session and clears its slot; an already-null slot is OK.
///
/// # Safety
/// handle is a writable, aligned slot containing null or the unique live
/// session pointer. No operation/close may race with this close. Copies become
/// stale and must not be used or closed afterward.
#[no_mangle]
pub unsafe extern "C" fn guanyinma_session_close(handle: *mut *mut GuanyinmaSession) -> i32 {
    boundary(|| {
        if handle.is_null() {
            return Err(FfiError::invalid("session handle slot is null"));
        }
        // SAFETY: The caller uniquely owns this writable slot/allocation.
        let session = unsafe { ptr::replace(handle, ptr::null_mut()) };
        if !session.is_null() {
            // SAFETY: The pointer came from Box::into_raw in session_open.
            unsafe { drop(Box::from_raw(session)) };
        }
        Ok(())
    })
}

/// Returns the C ABI version, independently of the product version.
#[no_mangle]
pub extern "C" fn guanyinma_abi_version() -> u32 {
    ABI_VERSION
}

/// Opens an existing KeyKey.db read-only.
///
/// # Safety
/// A nonempty path must be readable for path_length bytes. output must be a
/// writable, aligned pointer to an unused handle slot and must not alias the
/// path. The caller must later close a successful handle exactly once.
#[no_mangle]
pub unsafe extern "C" fn guanyinma_database_open(
    path: *const u8,
    path_length: usize,
    output: *mut *mut GuanyinmaDatabase,
) -> i32 {
    boundary(|| {
        if output.is_null() {
            return Err(FfiError::invalid("database output pointer is null"));
        }
        // SAFETY: output is a writable handle slot under the caller contract.
        unsafe { output.write(ptr::null_mut()) };
        // SAFETY: The input helper checks null/length/UTF-8/NUL; span
        // readability remains the caller's obligation.
        let path = unsafe { input(path, path_length, "database path") }?;
        if path.is_empty() {
            return Err(FfiError::invalid("database path is empty"));
        }
        let database = ModelDatabase::open(path)?;
        let handle = Box::new(GuanyinmaDatabase {
            database: Mutex::new(database),
        });
        // SAFETY: The successful output owns this new allocation.
        unsafe { output.write(Box::into_raw(handle)) };
        Ok(())
    })
}

/// Consumes a database handle and clears its slot; an already-null slot is OK.
///
/// # Safety
/// handle must point to a writable, aligned slot containing null or the unique
/// live pointer returned by database_open. No call may race with closing it,
/// and no copied alias may be used or closed after this call.
#[no_mangle]
pub unsafe extern "C" fn guanyinma_database_close(handle: *mut *mut GuanyinmaDatabase) -> i32 {
    boundary(|| {
        if handle.is_null() {
            return Err(FfiError::invalid("database handle slot is null"));
        }
        // SAFETY: The caller owns the writable handle slot and uniquely owns
        // its allocation. Clear the slot before dropping it.
        let database = unsafe { ptr::replace(handle, ptr::null_mut()) };
        if !database.is_null() {
            // SAFETY: This is the unique allocation from Box::into_raw above.
            unsafe { drop(Box::from_raw(database)) };
        }
        Ok(())
    })
}

/// Copies all matching model rows into an owned immutable result.
///
/// # Safety
/// database must be a live handle from database_open; it may be shared for
/// synchronized queries but cannot be destroyed concurrently. A nonempty key
/// must be readable for key_length bytes. output is a writable unused handle
/// slot and must not alias inputs or other active outputs.
#[no_mangle]
pub unsafe extern "C" fn guanyinma_database_query(
    database: *const GuanyinmaDatabase,
    kind: u32,
    key: *const u8,
    key_length: usize,
    output: *mut *mut GuanyinmaResult,
) -> i32 {
    boundary(|| {
        if output.is_null() {
            return Err(FfiError::invalid("result output pointer is null"));
        }
        // SAFETY: output is a writable slot under the caller contract.
        unsafe { output.write(ptr::null_mut()) };
        if database.is_null() {
            return Err(FfiError::invalid("database handle is null"));
        }
        // SAFETY: The input helper validates the span representation.
        let key = unsafe { input(key, key_length, "query key") }?;
        // SAFETY: The caller keeps the database allocation live. A shared
        // reference, not &mut, is used; the mutex serializes SQLite access.
        let handle = unsafe { &*database };
        let model = handle.database.lock().map_err(|_| FfiError {
            code: GUANYINMA_PANIC,
            message: "database handle was invalidated by an internal panic".to_owned(),
        })?;
        let result = match kind {
            GUANYINMA_QUERY_TRADITIONAL => snapshot(
                "traditional",
                key,
                &model.lookup_table(Table::Traditional, key)?,
            )?,
            GUANYINMA_QUERY_CANGJIE => {
                snapshot("cangjie", key, &model.lookup_table(Table::Cangjie, key)?)?
            }
            GUANYINMA_QUERY_SIMPLEX => {
                snapshot("simplex", key, &model.lookup_table(Table::Simplex, key)?)?
            }
            GUANYINMA_QUERY_UNIGRAMS => snapshot("unigrams", key, &model.unigrams(key)?)?,
            GUANYINMA_QUERY_BIGRAMS => snapshot("bigrams", key, &model.bigrams(key)?)?,
            _ => return Err(FfiError::invalid("unknown query kind")),
        };
        drop(model);
        // SAFETY: This new result owns every returned byte independently of
        // the database, and output is writable under the caller contract.
        unsafe { output.write(Box::into_raw(Box::new(result))) };
        Ok(())
    })
}

/// Returns raw query rows, or full candidate count in an input snapshot.
///
/// # Safety
/// result must be a live result handle. count must be writable and aligned,
/// and must not alias memory inside result.
#[no_mangle]
pub unsafe extern "C" fn guanyinma_result_row_count(
    result: *const GuanyinmaResult,
    count: *mut usize,
) -> i32 {
    boundary(|| {
        if count.is_null() {
            return Err(FfiError::invalid("row-count output pointer is null"));
        }
        // SAFETY: count is writable by caller contract.
        unsafe { count.write(0) };
        if result.is_null() {
            return Err(FfiError::invalid("result handle is null"));
        }
        // SAFETY: The result remains live and immutable during the call.
        unsafe { count.write((*result).row_count) };
        Ok(())
    })
}

/// Copies a result's JSON as UTF-8 with a trailing NUL.
///
/// # Safety
/// result must remain live. required points to writable, aligned size_t memory.
/// destination is null with capacity zero for a probe, or writable for capacity
/// bytes. The output regions must not overlap each other or result memory.
#[no_mangle]
pub unsafe extern "C" fn guanyinma_result_json(
    result: *const GuanyinmaResult,
    destination: *mut u8,
    capacity: usize,
    required: *mut usize,
) -> i32 {
    boundary(|| {
        if !required.is_null() {
            // SAFETY: A nonnull required output is writable by contract.
            unsafe { required.write(0) };
        }
        if result.is_null() {
            return Err(FfiError::invalid("result handle is null"));
        }
        // SAFETY: The result remains live; copy_output checks representation
        // and complete capacity before touching caller buffer bytes.
        unsafe { copy_output(&(*result).json, destination, capacity, required) }
    })
}

/// Consumes a result and clears its slot; an already-null slot is OK.
///
/// # Safety
/// handle is a writable, aligned slot containing null or the unique live result
/// from a database/session operation. No reader/closer may race; copied
/// aliases become invalid.
#[no_mangle]
pub unsafe extern "C" fn guanyinma_result_close(handle: *mut *mut GuanyinmaResult) -> i32 {
    boundary(|| {
        if handle.is_null() {
            return Err(FfiError::invalid("result handle slot is null"));
        }
        // SAFETY: The caller uniquely owns the slot/allocation.
        let result = unsafe { ptr::replace(handle, ptr::null_mut()) };
        if !result.is_null() {
            // SAFETY: The result came from Box::into_raw and is closed once.
            unsafe { drop(Box::from_raw(result)) };
        }
        Ok(())
    })
}

/// Copies the calling thread's last error without clearing or replacing it.
///
/// # Safety
/// required is writable and aligned. destination is null with zero capacity for
/// a probe or writable for capacity bytes; output regions must not overlap.
#[no_mangle]
pub unsafe extern "C" fn guanyinma_last_error(
    destination: *mut u8,
    capacity: usize,
    required: *mut usize,
) -> i32 {
    // Unlike normal API calls, this getter preserves the original diagnostic
    // even when its own caller-buffer probe returns BUFFER_TOO_SMALL.
    match catch_unwind(AssertUnwindSafe(|| {
        if !required.is_null() {
            // SAFETY: A nonnull required output is writable by contract.
            unsafe { required.write(0) };
        }
        let message = LAST_ERROR.with(|error| error.borrow().clone());
        // SAFETY: The caller meets the same buffer contract as result_json.
        unsafe { copy_output(message.as_bytes(), destination, capacity, required) }
    })) {
        Ok(Ok(())) => GUANYINMA_OK,
        Ok(Err(error)) => error.code,
        Err(_) => GUANYINMA_PANIC,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn input_rejects_bad_spans_without_forming_null_slices() {
        // SAFETY: Only the nonempty, valid byte arrays below are read.
        unsafe {
            assert_eq!(input(ptr::null(), 0, "key").unwrap(), "");
            assert_eq!(
                input(ptr::null(), 1, "key").unwrap_err().code,
                GUANYINMA_INVALID_ARGUMENT
            );
            assert_eq!(
                input([0xff].as_ptr(), 1, "key").unwrap_err().code,
                GUANYINMA_INVALID_UTF8
            );
            assert_eq!(
                input(b"a\0b".as_ptr(), 3, "key").unwrap_err().code,
                GUANYINMA_INVALID_ARGUMENT
            );
            assert_eq!(
                input(ptr::null(), usize::MAX, "key").unwrap_err().code,
                GUANYINMA_INVALID_ARGUMENT
            );
        }
    }

    #[test]
    fn output_probe_and_small_buffer_never_write_partial_text() {
        let mut required = usize::MAX;
        let mut buffer = [0xa5; 8];
        // SAFETY: All nonnull output pointers refer to the local allocations.
        unsafe {
            assert_eq!(
                copy_output("妳".as_bytes(), ptr::null_mut(), 0, &mut required)
                    .unwrap_err()
                    .code,
                GUANYINMA_BUFFER_TOO_SMALL
            );
            assert_eq!(required, 4);
            assert_eq!(
                copy_output("妳".as_bytes(), buffer.as_mut_ptr(), 3, &mut required)
                    .unwrap_err()
                    .code,
                GUANYINMA_BUFFER_TOO_SMALL
            );
            assert_eq!(buffer, [0xa5; 8]);
            copy_output("妳".as_bytes(), buffer.as_mut_ptr(), 4, &mut required).unwrap();
        }
        assert_eq!(&buffer[..4], &[0xe5, 0xa6, 0xb3, 0]);
        assert_eq!(&buffer[4..], &[0xa5; 4]);
    }

    #[test]
    fn failures_clear_result_and_count_outputs() {
        let mut result = ptr::dangling_mut::<GuanyinmaResult>();
        let mut count = usize::MAX;
        // SAFETY: Only null handles are passed and outputs are local valid slots.
        unsafe {
            assert_eq!(
                guanyinma_database_query(
                    ptr::null(),
                    GUANYINMA_QUERY_UNIGRAMS,
                    ptr::null(),
                    0,
                    &mut result
                ),
                GUANYINMA_INVALID_ARGUMENT
            );
            assert_eq!(
                guanyinma_result_row_count(ptr::null(), &mut count),
                GUANYINMA_INVALID_ARGUMENT
            );
        }
        assert!(result.is_null());
        assert_eq!(count, 0);
    }

    #[test]
    fn last_error_probe_preserves_diagnostic_and_is_thread_local() {
        boundary(|| Err(FfiError::invalid("outer diagnostic")));
        std::thread::spawn(|| {
            boundary(|| Err(FfiError::invalid("other thread")));
            LAST_ERROR.with(|last| assert_eq!(*last.borrow(), "other thread"));
        })
        .join()
        .unwrap();
        let mut required = 0;
        let mut buffer = [0; 64];
        // SAFETY: Local output regions are valid and do not overlap.
        unsafe {
            assert_eq!(
                guanyinma_last_error(ptr::null_mut(), 0, &mut required),
                GUANYINMA_BUFFER_TOO_SMALL
            );
            assert_eq!(required, "outer diagnostic".len() + 1);
            assert_eq!(
                guanyinma_last_error(buffer.as_mut_ptr(), buffer.len(), &mut required),
                GUANYINMA_OK
            );
        }
        assert_eq!(&buffer[..required - 1], b"outer diagnostic");
        LAST_ERROR.with(|last| assert_eq!(*last.borrow(), "outer diagnostic"));
    }

    #[test]
    fn panic_is_contained_at_the_boundary() {
        assert_eq!(boundary(|| panic!("test panic")), GUANYINMA_PANIC);
        LAST_ERROR.with(|last| assert!(last.borrow().contains("internal panic")));
    }

    #[test]
    fn diagnostic_borrow_cannot_escape_the_boundary() {
        diagnostic(Some("keep borrowed diagnostic".to_owned()));
        LAST_ERROR.with(|last| {
            let borrowed = last.borrow();
            assert_eq!(boundary(|| Ok(())), GUANYINMA_OK);
            assert_eq!(
                boundary(|| Err(FfiError::invalid("new error"))),
                GUANYINMA_INVALID_ARGUMENT
            );
            assert_eq!(boundary(|| panic!("contained panic")), GUANYINMA_PANIC);
            assert_eq!(*borrowed, "keep borrowed diagnostic");
        });
    }

    #[test]
    fn invalid_session_calls_clear_outputs_before_returning() {
        let mut session = ptr::dangling_mut::<GuanyinmaSession>();
        let mut result = ptr::dangling_mut::<GuanyinmaResult>();
        // SAFETY: Null handles/spans are rejected without dereferencing. Slots
        // below are valid writable locals and contain no live allocation.
        unsafe {
            assert_eq!(
                guanyinma_session_open(ptr::null(), 0, ptr::null(), 0, &mut session),
                GUANYINMA_INVALID_ARGUMENT
            );
            assert!(session.is_null());
            assert_eq!(
                guanyinma_session_apply(ptr::null(), ptr::null(), 0, &mut result),
                GUANYINMA_INVALID_ARGUMENT
            );
            assert!(result.is_null());
            result = ptr::dangling_mut::<GuanyinmaResult>();
            assert_eq!(
                guanyinma_session_snapshot(ptr::null(), &mut result),
                GUANYINMA_INVALID_ARGUMENT
            );
            assert!(result.is_null());
            assert_eq!(guanyinma_session_close(&mut session), GUANYINMA_OK);
            assert_eq!(guanyinma_session_close(&mut session), GUANYINMA_OK);
        }
    }

    #[test]
    fn closing_empty_slots_is_idempotent() {
        let mut database = ptr::null_mut();
        let mut result = ptr::null_mut();
        // SAFETY: The handle slots are valid and empty.
        unsafe {
            assert_eq!(guanyinma_database_close(&mut database), GUANYINMA_OK);
            assert_eq!(guanyinma_database_close(&mut database), GUANYINMA_OK);
            assert_eq!(guanyinma_result_close(&mut result), GUANYINMA_OK);
            assert_eq!(guanyinma_result_close(&mut result), GUANYINMA_OK);
        }
    }
}
