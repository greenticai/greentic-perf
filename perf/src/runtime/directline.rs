use std::io;
use std::time::{Duration, Instant};

use reqwest::blocking::Client;
use reqwest::blocking::Response;
use reqwest::header::{AUTHORIZATION, CONTENT_TYPE, HeaderMap, HeaderValue};
use serde::{Deserialize, Serialize};
use serde_json::json;

#[derive(Debug, Clone)]
pub struct DirectLineClient {
    client: Client,
    base_url: String,
    tenant: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DirectLineConversation {
    pub conversation_id: String,
    pub token: String,
    pub stream_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DirectLineReply {
    pub conversation_id: String,
    pub text: String,
}

#[derive(Debug, Deserialize)]
struct TokenResponse {
    token: String,
}

#[derive(Debug, Deserialize)]
struct StartConversationResponse {
    #[serde(rename = "conversationId")]
    conversation_id: String,
    token: String,
    #[serde(rename = "streamUrl")]
    stream_url: Option<String>,
}

#[derive(Debug, Deserialize)]
struct ActivitiesResponse {
    activities: Vec<Activity>,
}

#[derive(Debug, Deserialize)]
struct Activity {
    #[serde(rename = "type")]
    activity_type: String,
    #[serde(default)]
    text: Option<String>,
    #[serde(default)]
    from: Option<ActivityFrom>,
}

#[derive(Debug, Deserialize)]
struct ActivityFrom {
    #[serde(default)]
    id: Option<String>,
}

impl DirectLineClient {
    pub fn new(base_url: impl Into<String>, tenant: impl Into<String>) -> io::Result<Self> {
        let client = Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .map_err(io::Error::other)?;
        Ok(Self {
            client,
            base_url: base_url.into().trim_end_matches('/').to_owned(),
            tenant: tenant.into(),
        })
    }

    pub fn create_conversation(&self) -> io::Result<DirectLineConversation> {
        let token = self.issue_token()?;
        let response = self
            .post_with_fallbacks(
                &[
                    format!("{}/v3/directline/conversations", self.base_url),
                    format!(
                        "{}/{}/v3/directline/conversations",
                        self.base_url, self.tenant
                    ),
                    format!(
                        "{}/v1/messaging/webchat/{}/v3/directline/conversations",
                        self.base_url, self.tenant
                    ),
                ],
                auth_headers(&token)?,
                None,
            )?
            .error_for_status()
            .map_err(io::Error::other)?;
        let payload: StartConversationResponse = response.json().map_err(io::Error::other)?;
        Ok(DirectLineConversation {
            conversation_id: payload.conversation_id,
            token: payload.token,
            stream_url: payload.stream_url,
        })
    }

    pub fn send_message(
        &self,
        conversation: &DirectLineConversation,
        text: &str,
    ) -> io::Result<()> {
        self.post_with_fallbacks(
            &[
                format!(
                    "{}/v3/directline/conversations/{}/activities",
                    self.base_url, conversation.conversation_id
                ),
                format!(
                    "{}/{}/v3/directline/conversations/{}/activities",
                    self.base_url, self.tenant, conversation.conversation_id
                ),
                format!(
                    "{}/v1/messaging/webchat/{}/v3/directline/conversations/{}/activities",
                    self.base_url, self.tenant, conversation.conversation_id
                ),
            ],
            auth_headers(&conversation.token)?,
            Some(json!({
                "type": "message",
                "from": { "id": "perf-user" },
                "text": text,
            })),
        )?
        .error_for_status()
        .map_err(io::Error::other)?;
        Ok(())
    }

    pub fn poll_for_reply(
        &self,
        conversation: &DirectLineConversation,
        expected_substring: &str,
        timeout: Duration,
    ) -> io::Result<DirectLineReply> {
        let started = Instant::now();
        loop {
            let response = self
                .get_with_fallbacks(
                    &[
                        format!(
                            "{}/v3/directline/conversations/{}/activities",
                            self.base_url, conversation.conversation_id
                        ),
                        format!(
                            "{}/{}/v3/directline/conversations/{}/activities",
                            self.base_url, self.tenant, conversation.conversation_id
                        ),
                        format!(
                            "{}/v1/messaging/webchat/{}/v3/directline/conversations/{}/activities",
                            self.base_url, self.tenant, conversation.conversation_id
                        ),
                    ],
                    auth_headers(&conversation.token)?,
                )?
                .error_for_status()
                .map_err(io::Error::other)?;
            let payload: ActivitiesResponse = response.json().map_err(io::Error::other)?;
            if let Some(activity) = payload.activities.into_iter().find(|activity| {
                activity.activity_type == "message"
                    && activity
                        .from
                        .as_ref()
                        .and_then(|source| source.id.as_ref())
                        .map(|id| id != "perf-user")
                        .unwrap_or(true)
                    && activity
                        .text
                        .as_ref()
                        .map(|text| text.contains(expected_substring))
                        .unwrap_or(false)
            }) {
                return Ok(DirectLineReply {
                    conversation_id: conversation.conversation_id.clone(),
                    text: activity.text.unwrap_or_default(),
                });
            }

            if started.elapsed() >= timeout {
                return Err(io::Error::new(
                    io::ErrorKind::TimedOut,
                    format!(
                        "no direct line reply containing {:?} within {} ms",
                        expected_substring,
                        timeout.as_millis()
                    ),
                ));
            }

            std::thread::sleep(Duration::from_millis(100));
        }
    }

    fn issue_token(&self) -> io::Result<String> {
        let response = self
            .post_with_fallbacks(
                &[
                    format!("{}/v3/directline/tokens/generate", self.base_url),
                    format!(
                        "{}/{}/v3/directline/tokens/generate",
                        self.base_url, self.tenant
                    ),
                    format!(
                        "{}/v1/messaging/webchat/{}/token",
                        self.base_url, self.tenant
                    ),
                ],
                HeaderMap::new(),
                None,
            )?
            .error_for_status()
            .map_err(io::Error::other)?;
        let payload: TokenResponse = response.json().map_err(io::Error::other)?;
        Ok(payload.token)
    }

    fn post_with_fallbacks(
        &self,
        urls: &[String],
        headers: HeaderMap,
        body: Option<serde_json::Value>,
    ) -> io::Result<Response> {
        let mut last_error = None;

        for url in urls {
            let mut request = self.client.post(url).headers(headers.clone());
            if let Some(body) = body.clone() {
                request = request.header(CONTENT_TYPE, "application/json").json(&body);
            }

            match request.send() {
                Ok(response) if response.status().is_success() => return Ok(response),
                Ok(response) => {
                    last_error = Some(io::Error::other(format!(
                        "direct line POST {} returned {}",
                        url,
                        response.status()
                    )));
                }
                Err(error) => last_error = Some(io::Error::other(error)),
            }
        }

        Err(last_error.unwrap_or_else(|| io::Error::other("no direct line POST route candidates")))
    }

    fn get_with_fallbacks(&self, urls: &[String], headers: HeaderMap) -> io::Result<Response> {
        let mut last_error = None;

        for url in urls {
            match self.client.get(url).headers(headers.clone()).send() {
                Ok(response) if response.status().is_success() => return Ok(response),
                Ok(response) => {
                    last_error = Some(io::Error::other(format!(
                        "direct line GET {} returned {}",
                        url,
                        response.status()
                    )));
                }
                Err(error) => last_error = Some(io::Error::other(error)),
            }
        }

        Err(last_error.unwrap_or_else(|| io::Error::other("no direct line GET route candidates")))
    }
}

fn auth_headers(token: &str) -> io::Result<HeaderMap> {
    let mut headers = HeaderMap::new();
    let value = HeaderValue::from_str(&format!("Bearer {token}")).map_err(io::Error::other)?;
    headers.insert(AUTHORIZATION, value);
    Ok(headers)
}
