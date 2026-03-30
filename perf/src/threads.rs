use std::io;

pub const THREAD_ENV_VAR: &str = "GTC_THREADS";

pub fn normalize_thread_count(threads: usize) -> io::Result<usize> {
    if threads == 0 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "thread count must be greater than zero",
        ));
    }

    Ok(threads)
}
