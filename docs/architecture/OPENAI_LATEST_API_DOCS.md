# OpenAI Platform API Documentation (Latest)

## Overview

This document contains the latest OpenAI Platform API documentation, including support for GPT-5, the new `/v1/responses` endpoint, and various advanced features like multimodal support, streaming, functions, web search, file search, code interpreter, and conversation management.

## Table of Contents

1. [Authentication](#authentication)
2. [Error Handling](#error-handling)
3. [Rate Limiting](#rate-limiting)
4. [Backward Compatibility](#backward-compatibility)
5. [Responses API](#responses-api)
6. [Chat Completions API](#chat-completions-api)
7. [Audio API](#audio-api)
8. [Images API](#images-api)
9. [Embeddings API](#embeddings-api)
10. [Evaluations API](#evaluations-api)
11. [Fine-tuning API](#fine-tuning-api)
12. [Batch API](#batch-api)
13. [Files API](#files-api)
14. [Vector Stores API](#vector-stores-api)
15. [Containers API](#containers-api)
16. [Realtime API](#realtime-api)
17. [Assistants API](#assistants-api)
18. [Threads API](#threads-api)
19. [Messages API](#messages-api)

## Authentication

All API requests require authentication via API key in the Authorization header:

```bash
curl https://api.openai.com/v1/responses \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json"
```

## Error Handling

The API returns structured error responses:

```json
{
  "error": {
    "message": "Invalid API key provided",
    "type": "invalid_request_error",
    "param": null,
    "code": "invalid_api_key"
  }
}
```

Common error codes:
- `invalid_api_key`: Invalid authentication
- `model_not_found`: Requested model doesn't exist
- `rate_limit_exceeded`: Too many requests
- `invalid_request_error`: Malformed request
- `server_error`: Internal server error

## Rate Limiting

Rate limit information is included in response headers:
- `x-ratelimit-limit-requests`: Maximum requests per minute
- `x-ratelimit-limit-tokens`: Maximum tokens per minute
- `x-ratelimit-remaining-requests`: Remaining requests
- `x-ratelimit-remaining-tokens`: Remaining tokens
- `x-ratelimit-reset-requests`: Time when request limit resets
- `x-ratelimit-reset-tokens`: Time when token limit resets

## Backward Compatibility

The API maintains backward compatibility with the legacy `/v1/chat/completions` endpoint. New features are available through the `/v1/responses` endpoint while maintaining support for existing integrations

## New `/v1/responses` Endpoint

### Overview
The `/v1/responses` endpoint is OpenAI's most advanced interface for generating model responses. It supports:
- Text and image inputs
- Text and JSON outputs
- Stateful interactions using previous responses
- Built-in tools (file search, web search, computer use)
- Function calling for external systems integration
- File uploads and web content fetching

### Key Features

#### 1. Multi-Modal Support
- **Text inputs**: Standard text prompts
- **Image inputs**: Direct image processing
- **File inputs**: Support for various file formats including PDFs

#### 2. Built-in Tools
- **File Search**: Search through uploaded files
- **Web Search**: Search the web for relevant information  
- **Computer Use**: Interact with computer systems
- **Code Interpreter**: Execute Python code
- **Image Generation**: Create images based on prompts

#### 3. Advanced Input Formats

##### Text Input
```json
{
  "model": "gpt-5",
  "input": "What is the weather in San Francisco?"
}
```

##### Image Input
```json
{
  "model": "gpt-5",
  "input": [
    {
      "role": "user",
      "content": [
        {"type": "input_text", "text": "What's in this image?"},
        {"type": "input_image", "image_url": "https://example.com/image.jpg"}
      ]
    }
  ]
}
```

##### File Input
```json
{
  "model": "gpt-5",
  "input": [
    {
      "role": "user",
      "content": [
        {"type": "input_text", "text": "Summarize this document"},
        {"type": "input_file", "file_url": "https://example.com/document.pdf"}
      ]
    }
  ]
}
```

### Create Response Endpoint

**POST** `https://api.openai.com/v1/responses`

#### Request Body Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `model` | string | Optional | Model ID (e.g., "gpt-5", "gpt-4.1", "o3") |
| `input` | string/array | Optional | Text, image, or file inputs |
| `instructions` | string/null | Optional | System instructions for the model |
| `conversation` | string/object | Optional | Conversation context for stateful interactions |
| `tools` | array | Optional | Available tools for the model to use |
| `tool_choice` | string | Optional | How model selects tools ("auto", "none", "required") |
| `temperature` | number | Optional | Sampling temperature (0.6-1.2, default 0.8) |
| `max_output_tokens` | integer/string | Optional | Max tokens for response (1-4096 or "inf") |
| `stream` | boolean | Optional | Enable streaming mode (default false) |
| `store` | boolean | Optional | Store response for retrieval (default true) |
| `include` | array | Optional | Additional data to include in response |
| `web_search_options` | object | Optional | Options for web search tool |
| `reasoning` | object | Optional | Configuration for reasoning models (gpt-5 and o-series) |

#### Response Format

```json
{
  "id": "resp_abc123",
  "object": "response",
  "created_at": 1752100704,
  "status": "completed",
  "model": "gpt-5",
  "output": [
    {
      "id": "msg_123",
      "type": "message",
      "role": "assistant",
      "content": [
        {
          "type": "output_text",
          "text": "Response text here..."
        }
      ]
    }
  ],
  "usage": {
    "input_tokens": 100,
    "output_tokens": 50,
    "total_tokens": 150
  }
}
```

### Tool Support

#### Web Search
```json
{
  "tools": [
    {
      "type": "web_search"
    }
  ],
  "web_search_options": {
    "enabled": true
  }
}
```

#### File Search
```json
{
  "tools": [
    {
      "type": "file_search"
    }
  ]
}
```

#### Function Calling
```json
{
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "Get current weather",
        "parameters": {
          "type": "object",
          "properties": {
            "location": {"type": "string"}
          }
        }
      }
    }
  ]
}
```

### Conversation State

Create stateful conversations using the `conversation` parameter or `previous_response_id`:

```json
{
  "model": "gpt-5",
  "input": "Follow up question",
  "previous_response_id": "resp_abc123"
}
```

Or use conversation objects:

```json
{
  "model": "gpt-5",
  "input": "New message",
  "conversation": "conv_xyz789"
}
```

### Streaming Support

Enable real-time streaming of responses:

```json
{
  "model": "gpt-5",
  "input": "Generate a long response",
  "stream": true,
  "stream_options": {
    "include_usage": true
  }
}
```

### Structured Outputs

Use JSON schema to ensure structured responses:

```json
{
  "text": {
    "format": {
      "type": "json_schema",
      "json_schema": {
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "age": {"type": "number"}
        }
      }
    }
  }
}
```

### Additional Endpoints

#### Get Response
**GET** `https://api.openai.com/v1/responses/{response_id}`

Retrieve a stored response by ID.

#### Delete Response  
**DELETE** `https://api.openai.com/v1/responses/{response_id}`

Delete a stored response.

#### Cancel Response
**POST** `https://api.openai.com/v1/responses/{response_id}/cancel`

Cancel a background response (requires `background: true`).

### Conversations API

#### Create Conversation
**POST** `https://api.openai.com/v1/conversations`

```json
{
  "items": [
    {
      "type": "message",
      "role": "user",
      "content": "Initial message"
    }
  ],
  "metadata": {}
}
```

#### List Items
**GET** `https://api.openai.com/v1/conversations/{conversation_id}/items`

#### Add Items
**POST** `https://api.openai.com/v1/conversations/{conversation_id}/items`

### Model Capabilities

#### GPT-5 Specific Features
- Enhanced reasoning capabilities with `reasoning` parameter
- Support for encrypted reasoning content
- Advanced multi-modal understanding
- Improved context handling up to larger token limits

#### O-Series Features  
- Specialized reasoning configuration
- `reasoning_effort` parameter for controlling computation
- Summary generation for reasoning traces

### Authentication

All requests require Bearer token authentication:

```bash
curl https://api.openai.com/v1/responses \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{...}'
```

### Rate Limits and Usage

The `/v1/responses` endpoint includes detailed usage statistics:

```json
{
  "usage": {
    "input_tokens": 100,
    "input_tokens_details": {
      "cached_tokens": 50,
      "text_tokens": 80,
      "audio_tokens": 20
    },
    "output_tokens": 200,
    "output_tokens_details": {
      "reasoning_tokens": 50
    },
    "total_tokens": 300
  }
}
```

### Error Handling

Standard error responses:

```json
{
  "error": {
    "type": "invalid_request_error",
    "message": "Invalid model specified",
    "code": "model_not_found"
  }
}
```

## Migration from Chat Completions to Responses

### Key Differences

1. **Endpoint**: `/v1/chat/completions` → `/v1/responses`
2. **Input Format**: `messages` → `input` (more flexible)
3. **Native File Support**: Direct file URL support
4. **Built-in Tools**: Web search, file search included
5. **Stateful Conversations**: Native conversation tracking
6. **Enhanced Outputs**: Better structured output support

### Example Migration

#### Old (Chat Completions):
```json
{
  "model": "gpt-4",
  "messages": [
    {"role": "system", "content": "You are helpful"},
    {"role": "user", "content": "Hello"}
  ]
}
```

#### New (Responses):
```json
{
  "model": "gpt-5",
  "instructions": "You are helpful",
  "input": "Hello"
}
```

## Best Practices

1. **Use GPT-5** for the most advanced capabilities
2. **Enable streaming** for real-time responses
3. **Utilize built-in tools** instead of custom implementations
4. **Store responses** for retrieval and analysis
5. **Use conversation state** for multi-turn interactions
6. **Implement structured outputs** for consistent JSON responses
7. **Handle rate limits** gracefully with exponential backoff

## Backward Compatibility

- Chat Completions endpoint (`/v1/chat/completions`) remains available
- Legacy models continue to work with existing endpoints
- New features are primarily available through `/v1/responses`

## Important Notes

1. **GPT-5 is the latest model** with the most advanced capabilities
2. **The `/v1/responses` endpoint** is the recommended interface for new projects
3. **File uploads and web search** are natively supported without external tools
4. **Conversation state management** is built into the API
5. **Structured outputs** ensure reliable JSON responses

## Example: Complete Request with All Features

```json
{
  "model": "gpt-5",
  "input": [
    {
      "role": "user",
      "content": [
        {"type": "input_text", "text": "Analyze this data and search for related info"},
        {"type": "input_file", "file_url": "https://example.com/data.csv"}
      ]
    }
  ],
  "instructions": "You are a data analyst. Be thorough and accurate.",
  "tools": [
    {"type": "web_search"},
    {"type": "file_search"},
    {
      "type": "function",
      "function": {
        "name": "process_data",
        "description": "Process the analyzed data",
        "parameters": {
          "type": "object",
          "properties": {
            "data": {"type": "array"},
            "operation": {"type": "string"}
          }
        }
      }
    }
  ],
  "tool_choice": "auto",
  "temperature": 0.7,
  "max_output_tokens": 2000,
  "stream": true,
  "store": true,
  "include": [
    "file_search_call.results",
    "message.output_text.logprobs"
  ],
  "text": {
    "format": {
      "type": "json_schema",
      "json_schema": {
        "type": "object",
        "properties": {
          "analysis": {"type": "string"},
          "findings": {"type": "array"},
          "recommendations": {"type": "array"}
        }
      }
    }
  },
  "reasoning": {
    "effort": "high"
  }
}
```

This documentation confirms that GPT-5 exists and is available through the new `/v1/responses` endpoint, which provides enhanced capabilities beyond the traditional chat completions API.

## Chat Completions API

The Chat Completions API endpoint generates model responses from a list of messages comprising a conversation. While the new `/v1/responses` endpoint is recommended for new projects, the Chat Completions API remains fully supported and continues to receive updates.

### Endpoint

**POST** `https://api.openai.com/v1/chat/completions`

### Key Features

- **Text generation** from conversational context
- **Vision capabilities** for image understanding
- **Audio inputs and outputs** (with compatible models)
- **Structured Outputs** for reliable JSON responses
- **Function calling** for tool integration
- **Streaming** for real-time responses
- **Store parameter** for retrieving completions later

### Create Chat Completion

#### Request Body Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `messages` | array | Required | List of messages in the conversation |
| `model` | string | Required | Model ID (e.g., "gpt-5", "gpt-4o", "o3") |
| `audio` | object | Optional | Parameters for audio output |
| `frequency_penalty` | number | Optional | Penalize repeated tokens (-2.0 to 2.0) |
| `logit_bias` | map | Optional | Modify token likelihood |
| `logprobs` | boolean | Optional | Return log probabilities |
| `max_completion_tokens` | integer | Optional | Max tokens for completion |
| `metadata` | map | Optional | Key-value pairs for storing info |
| `modalities` | array | Optional | Output types (["text"], ["text", "audio"]) |
| `n` | integer | Optional | Number of completions to generate |
| `parallel_tool_calls` | boolean | Optional | Enable parallel function calling |
| `prediction` | object | Optional | Predicted output configuration |
| `presence_penalty` | number | Optional | Penalize new tokens (-2.0 to 2.0) |
| `prompt_cache_key` | string | Optional | Cache key for optimization |
| `reasoning_effort` | string | Optional | Reasoning effort (minimal/low/medium/high) |
| `response_format` | object | Optional | Output format specification |
| `safety_identifier` | string | Optional | User identifier for safety |
| `service_tier` | string | Optional | Processing tier (auto/default/flex/priority) |
| `stop` | string/array | Optional | Stop sequences |
| `store` | boolean | Optional | Store completion for retrieval |
| `stream` | boolean | Optional | Enable streaming |
| `stream_options` | object | Optional | Streaming configuration |
| `temperature` | number | Optional | Sampling temperature (0-2) |
| `tool_choice` | string/object | Optional | Tool selection control |
| `tools` | array | Optional | Available tools/functions |
| `top_logprobs` | integer | Optional | Number of likely tokens to return |
| `top_p` | number | Optional | Nucleus sampling (0-1) |
| `verbosity` | string | Optional | Response verbosity (low/medium/high) |
| `web_search_options` | object | Optional | Web search configuration |

### Message Formats

#### Text Message
```json
{
  "role": "user",
  "content": "Hello, how are you?"
}
```

#### System/Developer Message
```json
{
  "role": "developer",
  "content": "You are a helpful assistant."
}
```

#### Image Input
```json
{
  "role": "user",
  "content": [
    {"type": "text", "text": "What's in this image?"},
    {
      "type": "image_url",
      "image_url": {
        "url": "https://example.com/image.jpg"
      }
    }
  ]
}
```

#### Audio Input (requires compatible model)
```json
{
  "role": "user",
  "content": [
    {"type": "text", "text": "Transcribe this audio"},
    {
      "type": "input_audio",
      "input_audio": {
        "data": "base64_audio_data",
        "format": "wav"
      }
    }
  ]
}
```

### Function Calling

```json
{
  "model": "gpt-5",
  "messages": [{"role": "user", "content": "What's the weather?"}],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "Get current weather",
        "parameters": {
          "type": "object",
          "properties": {
            "location": {
              "type": "string",
              "description": "City and state"
            }
          },
          "required": ["location"]
        }
      }
    }
  ],
  "tool_choice": "auto"
}
```

### Structured Outputs

```json
{
  "model": "gpt-5",
  "messages": [{"role": "user", "content": "Generate user data"}],
  "response_format": {
    "type": "json_schema",
    "json_schema": {
      "name": "user_data",
      "schema": {
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "age": {"type": "integer"},
          "email": {"type": "string"}
        },
        "required": ["name", "age", "email"]
      }
    }
  }
}
```

### Response Format

```json
{
  "id": "chatcmpl-abc123",
  "object": "chat.completion",
  "created": 1741569952,
  "model": "gpt-5",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "I'm doing well, thank you!",
        "refusal": null,
        "annotations": []
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 20,
    "completion_tokens": 10,
    "total_tokens": 30,
    "prompt_tokens_details": {
      "cached_tokens": 0,
      "audio_tokens": 0
    },
    "completion_tokens_details": {
      "reasoning_tokens": 0,
      "audio_tokens": 0,
      "accepted_prediction_tokens": 0,
      "rejected_prediction_tokens": 0
    }
  },
  "service_tier": "default"
}
```

### Streaming

Enable streaming for real-time responses:

```json
{
  "model": "gpt-5",
  "messages": [{"role": "user", "content": "Tell me a story"}],
  "stream": true,
  "stream_options": {
    "include_usage": true
  }
}
```

Streaming returns server-sent events:

```
data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-5","choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}

data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-5","choices":[{"index":0,"delta":{"content":"Once"}}]}

data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-5","choices":[{"index":0,"delta":{"content":" upon"}}]}

data: [DONE]
```

### Additional Chat Completion Endpoints

#### Get Chat Completion
**GET** `https://api.openai.com/v1/chat/completions/{completion_id}`

Retrieve a stored chat completion (requires `store: true`).

#### List Chat Completions
**GET** `https://api.openai.com/v1/chat/completions`

List stored chat completions with optional filters.

#### Update Chat Completion
**POST** `https://api.openai.com/v1/chat/completions/{completion_id}`

Update metadata of a stored chat completion.

#### Delete Chat Completion
**DELETE** `https://api.openai.com/v1/chat/completions/{completion_id}`

Delete a stored chat completion.

#### Get Chat Messages
**GET** `https://api.openai.com/v1/chat/completions/{completion_id}/messages`

Retrieve messages from a stored chat completion.

### Model-Specific Features

#### GPT-5 Support
- Full support in both `/v1/chat/completions` and `/v1/responses`
- Enhanced reasoning with `reasoning_effort` parameter
- Larger context windows
- Improved multi-modal understanding

#### Audio Models
- `gpt-4o-audio-preview` supports audio generation
- Use `modalities: ["text", "audio"]` for audio output
- Configure with `audio` parameter for voice selection

#### Reasoning Models (O-Series)
- `o3`, `o3-mini`, `o4-mini` support reasoning parameters
- `reasoning_effort` controls computation depth
- `verbosity` controls response detail level

### Best Practices for Chat Completions

1. **Use appropriate models**: GPT-5 for advanced tasks, GPT-4o for efficiency
2. **Implement streaming**: For better user experience with long responses
3. **Use structured outputs**: For reliable JSON responses
4. **Store important completions**: Enable retrieval with `store: true`
5. **Handle rate limits**: Implement exponential backoff
6. **Use caching**: Leverage `prompt_cache_key` for repeated queries
7. **Monitor usage**: Track token consumption via usage stats

### Example: Complete Chat Request

```json
{
  "model": "gpt-5",
  "messages": [
    {
      "role": "developer",
      "content": "You are a helpful data analyst."
    },
    {
      "role": "user",
      "content": [
        {"type": "text", "text": "Analyze this sales data"},
        {
          "type": "image_url",
          "image_url": {"url": "https://example.com/chart.png"}
        }
      ]
    }
  ],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "calculate_statistics",
        "description": "Calculate statistical measures",
        "parameters": {
          "type": "object",
          "properties": {
            "data": {"type": "array", "items": {"type": "number"}},
            "measures": {"type": "array", "items": {"type": "string"}}
          },
          "required": ["data", "measures"]
        }
      }
    }
  ],
  "temperature": 0.7,
  "max_completion_tokens": 1500,
  "response_format": {
    "type": "json_schema",
    "json_schema": {
      "name": "analysis_result",
      "schema": {
        "type": "object",
        "properties": {
          "summary": {"type": "string"},
          "insights": {"type": "array", "items": {"type": "string"}},
          "metrics": {"type": "object"}
        },
        "required": ["summary", "insights", "metrics"]
      }
    }
  },
  "reasoning_effort": "high",
  "store": true,
  "metadata": {
    "request_type": "sales_analysis",
    "department": "sales"
  }
}
```

### Comparison: Chat Completions vs Responses API

| Feature | Chat Completions | Responses API |
|---------|-----------------|---------------|
| **Endpoint** | `/v1/chat/completions` | `/v1/responses` |
| **Input Format** | `messages` array | Flexible `input` |
| **File Support** | Via base64 encoding | Native file URLs |
| **Web Search** | Via tools parameter | Built-in support |
| **Conversation State** | Manual management | Native tracking |
| **Streaming** | Supported | Supported |
| **Store/Retrieve** | Supported | Supported |
| **GPT-5 Support** | Full support | Full support |
| **Legacy Support** | Excellent | Limited |
| **Recommendation** | Existing projects | New projects |

Both endpoints fully support GPT-5 and all latest models. Choose based on your project requirements and whether you need the advanced features of the Responses API.

## Audio API

### Create Transcription

**POST** `/v1/audio/transcriptions`

Transcribes audio into text using the Whisper model.

```bash
curl https://api.openai.com/v1/audio/transcriptions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F file="@audio.mp3" \
  -F model="whisper-1" \
  -F language="en" \
  -F response_format="json" \
  -F temperature="0.2"
```

#### Parameters
- `file`: Audio file (mp3, mp4, mpeg, mpga, m4a, wav, webm)
- `model`: Model ID (whisper-1)
- `language`: ISO-639-1 language code (optional)
- `prompt`: Optional text to guide transcription
- `response_format`: json, text, srt, verbose_json, vtt
- `temperature`: Sampling temperature (0-1)
- `timestamp_granularities`: ["word", "segment"] for detailed timestamps

### Create Speech

**POST** `/v1/audio/speech`

Generates audio from text input.

```json
{
  "model": "tts-1-hd",
  "input": "Hello, this is a test of text-to-speech.",
  "voice": "nova",
  "response_format": "mp3",
  "speed": 1.0
}
```

#### Available Voices
- `nova`: Natural, expressive female voice
- `alloy`: Neutral, balanced voice
- `echo`: Male voice with depth
- `fable`: British-accented voice
- `onyx`: Deep, authoritative male voice
- `shimmer`: Warm, pleasant female voice

## Images API

### Create Image

**POST** `/v1/images/generations`

```json
{
  "model": "dall-e-3",
  "prompt": "A serene landscape with mountains at sunset",
  "n": 1,
  "size": "1024x1024",
  "quality": "hd",
  "style": "natural",
  "response_format": "url"
}
```

#### Parameters
- `model`: "dall-e-3" or "dall-e-2"
- `size`: "1024x1024", "1792x1024", "1024x1792" (DALL-E 3)
- `quality`: "standard" or "hd"
- `style`: "natural" or "vivid"
- `response_format`: "url" or "b64_json"

### Edit Image

**POST** `/v1/images/edits`

```bash
curl https://api.openai.com/v1/images/edits \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F image="@original.png" \
  -F mask="@mask.png" \
  -F prompt="Add a rainbow to the sky" \
  -F model="dall-e-2" \
  -F n=1 \
  -F size="1024x1024"
```

### Create Image Variation

**POST** `/v1/images/variations`

```bash
curl https://api.openai.com/v1/images/variations \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F image="@original.png" \
  -F model="dall-e-2" \
  -F n=2 \
  -F size="1024x1024"
```

## Embeddings API

### Create Embeddings

**POST** `/v1/embeddings`

```json
{
  "model": "text-embedding-3-large",
  "input": ["Hello world", "How are you?"],
  "encoding_format": "float",
  "dimensions": 1536
}
```

#### Available Models
- `text-embedding-3-large`: 3072 dimensions (can be reduced)
- `text-embedding-3-small`: 1536 dimensions
- `text-embedding-ada-002`: 1536 dimensions (legacy)

#### Response
```json
{
  "object": "list",
  "data": [
    {
      "object": "embedding",
      "index": 0,
      "embedding": [0.023, -0.011, ...]
    },
    {
      "object": "embedding",
      "index": 1,
      "embedding": [0.018, -0.027, ...]
    }
  ],
  "model": "text-embedding-3-large",
  "usage": {
    "prompt_tokens": 5,
    "total_tokens": 5
  }
}
```

## Fine-tuning API

### Create Fine-tuning Job

**POST** `/v1/fine_tuning/jobs`

```json
{
  "model": "gpt-4o-mini",
  "training_file": "file-abc123",
  "validation_file": "file-def456",
  "hyperparameters": {
    "n_epochs": 3,
    "batch_size": 8,
    "learning_rate_multiplier": 1.0,
    "warmup_ratio": 0.1
  },
  "suffix": "custom-model",
  "seed": 42,
  "integrations": [
    {
      "type": "wandb",
      "config": {
        "project": "my-fine-tuning",
        "entity": "my-team"
      }
    }
  ]
}
```

### Training File Format

JSONL format with conversation examples:
```jsonl
{"messages": [{"role": "system", "content": "You are a helpful assistant."}, {"role": "user", "content": "What is 2+2?"}, {"role": "assistant", "content": "2+2 equals 4."}]}
{"messages": [{"role": "user", "content": "Explain quantum physics"}, {"role": "assistant", "content": "Quantum physics is..."}]}
```

### List Fine-tuning Jobs

**GET** `/v1/fine_tuning/jobs`

### Get Fine-tuning Job

**GET** `/v1/fine_tuning/jobs/{job_id}`

### Cancel Fine-tuning Job

**POST** `/v1/fine_tuning/jobs/{job_id}/cancel`

### List Job Events

**GET** `/v1/fine_tuning/jobs/{job_id}/events`

### List Job Checkpoints

**GET** `/v1/fine_tuning/jobs/{job_id}/checkpoints`

## Batch API

Process multiple requests asynchronously at reduced cost.

### Create Batch

**POST** `/v1/batches`

```json
{
  "input_file_id": "file-abc123",
  "endpoint": "/v1/chat/completions",
  "completion_window": "24h",
  "metadata": {
    "project": "batch_analysis",
    "version": "1.0"
  }
}
```

### Input File Format

JSONL file with requests:
```jsonl
{"custom_id": "req-1", "method": "POST", "url": "/v1/chat/completions", "body": {"model": "gpt-4o", "messages": [{"role": "user", "content": "Hello"}]}}
{"custom_id": "req-2", "method": "POST", "url": "/v1/chat/completions", "body": {"model": "gpt-4o", "messages": [{"role": "user", "content": "Hi"}]}}
```

### List Batches

**GET** `/v1/batches`

### Get Batch

**GET** `/v1/batches/{batch_id}`

### Cancel Batch

**POST** `/v1/batches/{batch_id}/cancel`

## Files API

### Upload File

**POST** `/v1/files`

```bash
curl https://api.openai.com/v1/files \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F purpose="fine-tune" \
  -F file="@training_data.jsonl"
```

#### Purposes
- `fine-tune`: For fine-tuning
- `assistants`: For assistants API
- `batch`: For batch API
- `vision`: For image inputs

### List Files

**GET** `/v1/files`

### Get File

**GET** `/v1/files/{file_id}`

### Delete File

**DELETE** `/v1/files/{file_id}`

### Get File Content

**GET** `/v1/files/{file_id}/content`

## Vector Stores API

Manage document collections for semantic search.

### Create Vector Store

**POST** `/v1/vector_stores`

```json
{
  "name": "Product Documentation",
  "file_ids": ["file-123", "file-456"],
  "chunking_strategy": {
    "type": "static",
    "static": {
      "max_chunk_size_tokens": 500,
      "chunk_overlap_tokens": 100
    }
  },
  "metadata": {
    "project": "docs",
    "version": "2.0"
  },
  "expires_after": {
    "anchor": "last_active_at",
    "days": 30
  }
}
```

### List Vector Stores

**GET** `/v1/vector_stores`

### Get Vector Store

**GET** `/v1/vector_stores/{vector_store_id}`

### Update Vector Store

**POST** `/v1/vector_stores/{vector_store_id}`

### Delete Vector Store

**DELETE** `/v1/vector_stores/{vector_store_id}`

### Create Vector Store File

**POST** `/v1/vector_stores/{vector_store_id}/files`

```json
{
  "file_id": "file-789",
  "chunking_strategy": {
    "type": "auto"
  }
}
```

## Realtime API

### WebSocket Connection

**WS** `wss://api.openai.com/v1/realtime`

Establishes real-time bidirectional communication.

#### Session Configuration
```json
{
  "type": "session.update",
  "session": {
    "model": "gpt-5",
    "voice": "nova",
    "instructions": "You are a helpful assistant.",
    "modalities": ["text", "audio"],
    "input_audio_format": "pcm16",
    "output_audio_format": "pcm16",
    "input_audio_transcription": {
      "model": "whisper-1"
    },
    "turn_detection": {
      "type": "server_vad",
      "threshold": 0.5,
      "prefix_padding_ms": 300,
      "silence_duration_ms": 500
    },
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get weather information",
          "parameters": {
            "type": "object",
            "properties": {
              "location": {"type": "string"}
            },
            "required": ["location"]
          }
        }
      }
    ],
    "temperature": 0.7,
    "max_response_output_tokens": 4096
  }
}
```

#### Client Events

##### Audio Stream
```json
{
  "type": "input_audio_buffer.append",
  "audio": "base64_encoded_audio_chunk"
}
```

##### Commit Audio
```json
{
  "type": "input_audio_buffer.commit"
}
```

##### Create Response
```json
{
  "type": "response.create",
  "response": {
    "modalities": ["text", "audio"],
    "instructions": "Please be concise"
  }
}
```

#### Server Events

##### Session Created
```json
{
  "type": "session.created",
  "session": {
    "id": "sess_abc123",
    "model": "gpt-5",
    "created": 1234567890
  }
}
```

##### Audio Delta
```json
{
  "type": "response.audio.delta",
  "response_id": "resp_123",
  "item_id": "item_456",
  "output_index": 0,
  "content_index": 0,
  "delta": "base64_audio_chunk"
}
```

##### Text Delta
```json
{
  "type": "response.text.delta",
  "response_id": "resp_123",
  "item_id": "item_456",
  "output_index": 0,
  "content_index": 0,
  "delta": "Hello, how can I"
}
```

##### Function Call
```json
{
  "type": "response.function_call_arguments.delta",
  "response_id": "resp_123",
  "item_id": "item_789",
  "output_index": 0,
  "call_id": "call_abc",
  "delta": "{\"location\": \"San"
}
```

## Assistants API

Build AI assistants with persistent threads and file handling.

### Create Assistant

**POST** `/v1/assistants`

```json
{
  "model": "gpt-5",
  "name": "Data Analyst Assistant",
  "description": "Analyzes data and creates visualizations",
  "instructions": "You are a data analyst. Help users understand their data through analysis and visualization.",
  "tools": [
    {"type": "code_interpreter"},
    {"type": "file_search"},
    {
      "type": "function",
      "function": {
        "name": "create_chart",
        "description": "Create a data visualization",
        "parameters": {
          "type": "object",
          "properties": {
            "data": {"type": "array"},
            "chart_type": {"type": "string", "enum": ["bar", "line", "pie"]}
          },
          "required": ["data", "chart_type"]
        }
      }
    }
  ],
  "tool_resources": {
    "code_interpreter": {
      "file_ids": ["file-123", "file-456"]
    },
    "file_search": {
      "vector_store_ids": ["vs-789"]
    }
  },
  "metadata": {
    "department": "analytics",
    "version": "2.0"
  },
  "temperature": 0.7,
  "top_p": 0.9,
  "response_format": {
    "type": "json_object"
  }
}
```

### List Assistants

**GET** `/v1/assistants`

### Get Assistant

**GET** `/v1/assistants/{assistant_id}`

### Update Assistant

**POST** `/v1/assistants/{assistant_id}`

### Delete Assistant

**DELETE** `/v1/assistants/{assistant_id}`

## Threads API

Manage conversation threads for assistants.

### Create Thread

**POST** `/v1/threads`

```json
{
  "messages": [
    {
      "role": "user",
      "content": "Analyze this sales data and identify trends",
      "attachments": [
        {
          "file_id": "file-abc123",
          "tools": [{"type": "code_interpreter"}, {"type": "file_search"}]
        }
      ]
    }
  ],
  "tool_resources": {
    "code_interpreter": {
      "file_ids": ["file-def456"]
    },
    "file_search": {
      "vector_store_ids": ["vs-ghi789"]
    }
  },
  "metadata": {
    "user_id": "user_12345",
    "session_id": "sess_67890"
  }
}
```

### Get Thread

**GET** `/v1/threads/{thread_id}`

### Update Thread

**POST** `/v1/threads/{thread_id}`

### Delete Thread

**DELETE** `/v1/threads/{thread_id}`

### Create Run

**POST** `/v1/threads/{thread_id}/runs`

```json
{
  "assistant_id": "asst_abc123",
  "model": "gpt-5",
  "instructions": "Focus on quarterly trends and year-over-year growth",
  "additional_instructions": "Use clear visualizations",
  "additional_messages": [
    {
      "role": "user",
      "content": "Also compare with industry benchmarks"
    }
  ],
  "tools": [
    {"type": "code_interpreter"},
    {"type": "file_search"}
  ],
  "temperature": 0.7,
  "top_p": 0.9,
  "max_prompt_tokens": 5000,
  "max_completion_tokens": 2000,
  "truncation_strategy": {
    "type": "last_messages",
    "last_messages": 10
  },
  "tool_choice": "auto",
  "parallel_tool_calls": true,
  "response_format": {
    "type": "json_object"
  },
  "metadata": {
    "analysis_type": "quarterly_review"
  },
  "stream": true
}
```

### Run Status Values

- `queued`: Run is queued
- `in_progress`: Run is executing
- `requires_action`: Waiting for tool outputs
- `cancelling`: Run is being cancelled
- `cancelled`: Run was cancelled
- `failed`: Run failed
- `completed`: Run completed successfully
- `incomplete`: Run ended due to token limit
- `expired`: Run expired

### Submit Tool Outputs

**POST** `/v1/threads/{thread_id}/runs/{run_id}/submit_tool_outputs`

```json
{
  "tool_outputs": [
    {
      "tool_call_id": "call_abc123",
      "output": "{\"result\": \"Chart created successfully\"}"
    }
  ],
  "stream": true
}
```

### List Runs

**GET** `/v1/threads/{thread_id}/runs`

### Get Run

**GET** `/v1/threads/{thread_id}/runs/{run_id}`

### Update Run

**POST** `/v1/threads/{thread_id}/runs/{run_id}`

### Cancel Run

**POST** `/v1/threads/{thread_id}/runs/{run_id}/cancel`

### Create Thread and Run

**POST** `/v1/threads/runs`

Create a thread and run in one request:

```json
{
  "assistant_id": "asst_abc123",
  "thread": {
    "messages": [
      {
        "role": "user",
        "content": "Analyze this data"
      }
    ]
  },
  "model": "gpt-5",
  "stream": true
}
```

### List Run Steps

**GET** `/v1/threads/{thread_id}/runs/{run_id}/steps`

### Get Run Step

**GET** `/v1/threads/{thread_id}/runs/{run_id}/steps/{step_id}`

## Messages API

Manage messages within threads.

### Create Message

**POST** `/v1/threads/{thread_id}/messages`

```json
{
  "role": "user",
  "content": "What are the key insights from the analysis?",
  "attachments": [
    {
      "file_id": "file-xyz789",
      "tools": [{"type": "file_search"}]
    }
  ],
  "metadata": {
    "priority": "high",
    "category": "analysis"
  }
}
```

### List Messages

**GET** `/v1/threads/{thread_id}/messages`

Query parameters:
- `limit`: Number of messages to retrieve (1-100)
- `order`: "asc" or "desc"
- `after`: Cursor for pagination
- `before`: Cursor for pagination
- `run_id`: Filter by run ID

### Get Message

**GET** `/v1/threads/{thread_id}/messages/{message_id}`

### Update Message

**POST** `/v1/threads/{thread_id}/messages/{message_id}`

```json
{
  "metadata": {
    "reviewed": true,
    "rating": 5
  }
}
```

### Delete Message

**DELETE** `/v1/threads/{thread_id}/messages/{message_id}`

## Moderation API

Check content for policy compliance.

### Create Moderation

**POST** `/v1/moderations`

```json
{
  "model": "omni-moderation-latest",
  "input": [
    {
      "type": "text",
      "text": "Content to check for policy compliance"
    },
    {
      "type": "image_url",
      "image_url": {
        "url": "https://example.com/image.jpg"
      }
    }
  ]
}
```

#### Response

```json
{
  "id": "mod_abc123",
  "model": "omni-moderation-latest",
  "results": [
    {
      "flagged": false,
      "categories": {
        "harassment": false,
        "harassment/threatening": false,
        "hate": false,
        "hate/threatening": false,
        "illicit": false,
        "illicit/violent": false,
        "self-harm": false,
        "self-harm/intent": false,
        "self-harm/instructions": false,
        "sexual": false,
        "sexual/minors": false,
        "violence": false,
        "violence/graphic": false
      },
      "category_scores": {
        "harassment": 0.0001,
        "harassment/threatening": 0.00001,
        "hate": 0.00001,
        "hate/threatening": 0.000001,
        "illicit": 0.00001,
        "illicit/violent": 0.000001,
        "self-harm": 0.00001,
        "self-harm/intent": 0.000001,
        "self-harm/instructions": 0.000001,
        "sexual": 0.0001,
        "sexual/minors": 0.00001,
        "violence": 0.0001,
        "violence/graphic": 0.00001
      },
      "category_applied_input_types": {
        "harassment": ["text"],
        "violence": ["text", "image"]
      }
    }
  ]
}
```

## Models

### Available Models

#### GPT Models
- **gpt-5**: Most advanced model with multimodal capabilities
- **gpt-4o**: Optimized GPT-4 with vision
- **gpt-4o-mini**: Smaller, faster GPT-4o variant
- **gpt-4-turbo**: Latest GPT-4 Turbo
- **gpt-3.5-turbo**: Fast, efficient model

#### Reasoning Models (O-Series)
- **o3**: Advanced reasoning model
- **o3-mini**: Smaller reasoning model
- **o4-mini**: Latest mini reasoning model

#### Specialized Models
- **whisper-1**: Audio transcription
- **tts-1**: Text-to-speech
- **tts-1-hd**: High-quality text-to-speech
- **dall-e-3**: Latest image generation
- **dall-e-2**: Image generation and editing
- **text-embedding-3-large**: Large embedding model
- **text-embedding-3-small**: Small embedding model
- **omni-moderation-latest**: Content moderation

### Model Capabilities Comparison

| Model | Context | Max Output | Vision | Audio | Tools | Fine-tuning |
|-------|---------|------------|--------|-------|-------|-------------|
| gpt-5 | 128K | 8K | ✓ | ✓ | All | Coming |
| gpt-4o | 128K | 4K | ✓ | Input | Most | ✓ |
| gpt-4o-mini | 128K | 4K | ✓ | Input | Most | ✓ |
| gpt-3.5-turbo | 16K | 4K | ✗ | ✗ | Functions | ✓ |
| o3 | 128K | 32K | ✗ | ✗ | Functions | ✗ |

## Error Codes

### Client Errors (4xx)

- `400 Bad Request`: Invalid request format
- `401 Unauthorized`: Invalid API key
- `403 Forbidden`: Access denied
- `404 Not Found`: Resource not found
- `409 Conflict`: Resource conflict
- `422 Unprocessable Entity`: Invalid parameters
- `429 Too Many Requests`: Rate limit exceeded

### Server Errors (5xx)

- `500 Internal Server Error`: Server error
- `502 Bad Gateway`: Gateway error
- `503 Service Unavailable`: Service temporarily unavailable

### Error Response Format

```json
{
  "error": {
    "message": "Detailed error message",
    "type": "error_type",
    "param": "parameter_name",
    "code": "error_code"
  }
}
```

## Rate Limits

### Tier Limits

| Tier | RPM | TPM | RPD |
|------|-----|-----|-----|
| Free | 3 | 40K | 200 |
| Tier 1 | 60 | 60K | 3K |
| Tier 2 | 500 | 80K | 5K |
| Tier 3 | 5000 | 160K | 10K |
| Tier 4 | 10000 | 2M | 30K |
| Tier 5 | 30000 | 10M | 100K |

- RPM: Requests per minute
- TPM: Tokens per minute
- RPD: Requests per day

### Rate Limit Headers

```
x-ratelimit-limit-requests: 60
x-ratelimit-limit-tokens: 60000
x-ratelimit-remaining-requests: 59
x-ratelimit-remaining-tokens: 59950
x-ratelimit-reset-requests: 2024-01-01T00:01:00Z
x-ratelimit-reset-tokens: 2024-01-01T00:01:00Z
```

## Best Practices

### 1. API Key Security
- Never expose keys in client-side code
- Use environment variables
- Rotate keys regularly
- Use separate keys for different environments

### 2. Error Handling
```python
import openai
import time

def make_request_with_retry(func, *args, **kwargs):
    max_retries = 3
    for attempt in range(max_retries):
        try:
            return func(*args, **kwargs)
        except openai.RateLimitError as e:
            if attempt < max_retries - 1:
                time.sleep(2 ** attempt)  # Exponential backoff
            else:
                raise
        except openai.APIError as e:
            print(f"API error: {e}")
            raise
```

### 3. Token Optimization
- Use appropriate max_tokens settings
- Implement conversation truncation
- Cache responses when possible
- Use smaller models when appropriate

### 4. Streaming Implementation
```python
import openai

client = openai.OpenAI()

stream = client.chat.completions.create(
    model="gpt-5",
    messages=[{"role": "user", "content": "Tell me a story"}],
    stream=True
)

for chunk in stream:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="")
```

### 5. Structured Output Validation
```python
import json
from jsonschema import validate

schema = {
    "type": "object",
    "properties": {
        "name": {"type": "string"},
        "age": {"type": "integer", "minimum": 0}
    },
    "required": ["name", "age"]
}

response = client.chat.completions.create(
    model="gpt-5",
    messages=[{"role": "user", "content": "Generate user data"}],
    response_format={
        "type": "json_schema",
        "json_schema": {"name": "user", "schema": schema}
    }
)

result = json.loads(response.choices[0].message.content)
validate(instance=result, schema=schema)  # Validates output
```

## Migration Guides

### Migrating to GPT-5

1. **Update model parameter**: Change `"gpt-4"` to `"gpt-5"`
2. **Leverage new features**: 
   - Use reasoning parameter for complex tasks
   - Enable multimodal inputs
   - Utilize larger context windows
3. **Adjust token limits**: GPT-5 supports larger outputs
4. **Test thoroughly**: Responses may differ from GPT-4

### Migrating from Completions to Chat

#### Old (Completions - Deprecated)
```python
response = openai.Completion.create(
    model="text-davinci-003",
    prompt="Translate to French: Hello",
    max_tokens=100
)
```

#### New (Chat Completions)
```python
response = client.chat.completions.create(
    model="gpt-5",
    messages=[
        {"role": "system", "content": "You are a translator."},
        {"role": "user", "content": "Translate to French: Hello"}
    ],
    max_tokens=100
)
```

### Using the New Responses Endpoint

#### Benefits over Chat Completions
- Native file handling
- Built-in web search
- Conversation state management
- More flexible input formats
- Enhanced tool integration

#### When to Use Responses API
- New projects requiring advanced features
- Applications needing conversation persistence
- Multimodal applications
- Complex tool integrations

#### When to Use Chat Completions
- Existing projects with established patterns
- Simple request-response interactions
- Maximum compatibility requirements
- Well-documented use cases

## Conclusion

This documentation provides comprehensive coverage of the OpenAI Platform API, including:

1. **Latest Models**: GPT-5, O-series reasoning models, and specialized models
2. **New Endpoints**: `/v1/responses` with advanced capabilities
3. **Complete API Coverage**: All endpoints from chat to assistants to realtime
4. **Best Practices**: Security, error handling, optimization
5. **Migration Guidance**: Upgrading to newer models and endpoints

### Key Takeaways

- **GPT-5 is available** through both `/v1/chat/completions` and `/v1/responses`
- **The Responses API** offers the most advanced features for new projects
- **Backward compatibility** is maintained for existing implementations
- **Choose the right endpoint** based on your specific requirements
- **Implement proper error handling** and rate limit management
- **Use structured outputs** for reliable JSON responses
- **Consider costs** when selecting models and endpoints

### Important Notes for Cedar Project

1. **Current Issue**: Cedar's `agent_loop.rs` uses `/v1/responses` which requires special relay configuration
2. **Recommendation**: Use `/v1/chat/completions` with stable models (gpt-4o, gpt-4o-mini) for production
3. **GPT-5 Support**: While documented here, GPT-5 may not be publicly available yet
4. **Testing**: Always test with available models before deploying
5. **Monitoring**: Implement comprehensive logging for API interactions

For the latest updates, refer to the official OpenAI documentation at https://platform.openai.com/docs
