use std::num::NonZeroU32;

use serde::Deserialize;

use crate::facebook::{ErrorCode, PostError};

#[derive(Debug, thiserror::Error)]
#[error("Facebook client code")]
pub enum Error {
    #[error(transparent)]
    GraphApi(#[from] GraphApiError),
    #[error("Network error: {0}")]
    Reqwest(#[from] reqwest::Error),
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("URL error: {0}")]
    Url(#[from] url::ParseError),
    #[error("The page ({page_id}) was not found in the pages the user ({user_id}) has access to")]
    PageNotFound { page_id: String, user_id: String },
    #[error(transparent)]
    PostError(#[from] PostError),
}

#[derive(Debug, Clone, thiserror::Error)]
#[error( "Graph API Error\n  Code: {code}\n  Type: {error_type}\n  Reason: {}\n  Details: {help_message}\n  Trace: {trace_id}", code.canonical_reason().unwrap_or("Unknown reason")
)]
pub struct GraphApiError {
    pub help_message: String,
    pub error_type: String,
    pub code: ErrorCode,
    pub user_title: Option<String>,
    pub user_message: Option<String>,
    pub trace_id: String,
}

impl GraphApiError {
    /// Parse a Graph API error from JSON response body
    pub fn from_response_body(body: &str) -> Result<Self, serde_json::Error> {
        let response: GraphApiErrorResponse = serde_json::from_str(body)?;
        let data = response.error;

        let code = ErrorCode {
            code: NonZeroU32::new(data.code)
                .unwrap_or(NonZeroU32::new(1).expect("Couldn't get a NonZeroU32 from 1")),
            subcode: data.error_subcode.and_then(NonZeroU32::new),
        };

        // Assert that Facebook's message matches our canonical representation
        let canonical = code.canonical_reason();
        if canonical != Some("Unknown error")
            && !data
                .message
                .contains(code.canonical_reason().unwrap_or_default())
        {
            tracing::warn!(
                code = %code,
                expected = canonical,
                actual = %data.message,
                "Facebook error message differs from canonical representation - API may have changed"
            );
        }

        Ok(GraphApiError {
            help_message: data.message,
            error_type: data.error_type,
            code,
            user_title: data.error_user_title,
            user_message: data.error_user_msg,
            trace_id: data.trace_id,
        })
    }
}

#[derive(Debug, Deserialize)]
struct GraphApiErrorResponse {
    error: GraphApiErrorData,
}

#[derive(Debug, Deserialize)]
struct GraphApiErrorData {
    message: String,
    #[serde(rename = "type")]
    error_type: String,
    code: u32,
    error_subcode: Option<u32>,
    error_user_title: Option<String>,
    error_user_msg: Option<String>,
    #[serde(rename = "fbtrace_id")]
    trace_id: String,
}
