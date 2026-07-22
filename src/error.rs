//! Plugin-local error type. Lightweight — no `anyhow`/`thiserror`.

use std::fmt;

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum ErrorCode {
    ParseError = -32700,
    InvalidRequest = -32600,
    MethodNotFound = -32601,
    InvalidParams = -32602,
    InternalError = -32603,
}

#[derive(Debug)]
pub struct PluginError {
    pub code: ErrorCode,
    pub message: String,
}

impl PluginError {
    pub fn internal(msg: impl Into<String>) -> Self {
        Self {
            code: ErrorCode::InternalError,
            message: msg.into(),
        }
    }

    pub fn invalid_params(msg: impl Into<String>) -> Self {
        Self {
            code: ErrorCode::InvalidParams,
            message: msg.into(),
        }
    }

    pub fn method_not_found(msg: impl Into<String>) -> Self {
        Self {
            code: ErrorCode::MethodNotFound,
            message: msg.into(),
        }
    }
}

impl fmt::Display for ErrorCode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{self:?}")
    }
}

impl fmt::Display for PluginError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "[{}] {}", self.code, self.message)
    }
}

impl std::error::Error for PluginError {}

impl ErrorCode {
    pub fn value(&self) -> i64 {
        *self as i64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn error_code_values_match_json_rpc_spec() {
        assert_eq!(ErrorCode::ParseError.value(), -32700);
        assert_eq!(ErrorCode::InvalidRequest.value(), -32600);
        assert_eq!(ErrorCode::MethodNotFound.value(), -32601);
        assert_eq!(ErrorCode::InvalidParams.value(), -32602);
        assert_eq!(ErrorCode::InternalError.value(), -32603);
    }

    #[test]
    fn plugin_error_internal_creates_correct_error() {
        let err = PluginError::internal("something broke");
        assert_eq!(err.code, ErrorCode::InternalError);
        assert_eq!(err.message, "something broke");
    }

    #[test]
    fn plugin_error_invalid_params_creates_correct_error() {
        let err = PluginError::invalid_params("bad input");
        assert_eq!(err.code, ErrorCode::InvalidParams);
        assert_eq!(err.message, "bad input");
    }

    #[test]
    fn plugin_error_method_not_found_creates_correct_error() {
        let err = PluginError::method_not_found("unknown_method");
        assert_eq!(err.code, ErrorCode::MethodNotFound);
        assert_eq!(err.message, "unknown_method");
    }

    #[test]
    fn plugin_error_display_format() {
        let err = PluginError::internal("test error");
        let display = format!("{err}");
        assert!(display.contains("InternalError"));
        assert!(display.contains("test error"));
    }
}
