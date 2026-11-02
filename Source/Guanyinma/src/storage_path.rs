//! Native file names for model and user-store I/O.

use std::io;
use std::path::{Path, PathBuf};

pub(crate) fn canonicalize(path: impl AsRef<Path>) -> io::Result<PathBuf> {
    let path = path.as_ref();
    let result = std::fs::canonicalize(path);
    #[cfg(windows)]
    if matches!(&result, Err(error) if error.kind() == io::ErrorKind::PermissionDenied) {
        return nt_file_name(path);
    }
    result
}

#[cfg(windows)]
fn nt_file_name(path: &Path) -> io::Result<PathBuf> {
    use std::ffi::{c_void, OsString};
    use std::fs::OpenOptions;
    use std::os::windows::ffi::OsStringExt;
    use std::os::windows::fs::OpenOptionsExt;
    use std::os::windows::io::AsRawHandle;

    #[link(name = "kernel32")]
    unsafe extern "system" {
        #[link_name = "GetFinalPathNameByHandleW"]
        fn final_file_name(handle: *mut c_void, name: *mut u16, size: u32, flags: u32) -> u32;
    }

    // Match std's metadata-only open, including directory support. Resolve
    // links through the handle without requiring the DOS mount-manager access
    // denied to AppContainer hosts. This is a native physical path, never a
    // lexical substitute; existing file-identity and model-alias checks remain.
    const FILE_FLAG_BACKUP_SEMANTICS: u32 = 0x0200_0000;
    const VOLUME_NAME_NT: u32 = 0x2;
    let file = OpenOptions::new()
        .access_mode(0)
        .custom_flags(FILE_FLAG_BACKUP_SEMANTICS)
        .open(path)?;
    let mut name = vec![0u16; 512];
    loop {
        // SAFETY: file owns a live handle, name is writable for the supplied
        // element count, and the API retains neither pointer after returning.
        let length = unsafe {
            final_file_name(
                file.as_raw_handle(),
                name.as_mut_ptr(),
                name.len() as u32,
                VOLUME_NAME_NT,
            )
        };
        if length == 0 {
            return Err(io::Error::last_os_error());
        }
        if length as usize >= name.len() {
            name.resize(length as usize + 1, 0);
            continue;
        }
        name.truncate(length as usize);
        let mut absolute = OsString::from(r"\\?\GLOBALROOT");
        absolute.push(OsString::from_wide(&name));
        return Ok(PathBuf::from(absolute));
    }
}
