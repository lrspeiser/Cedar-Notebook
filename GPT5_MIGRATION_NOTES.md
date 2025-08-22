# GPT-5 Migration Documentation

## Date: August 22, 2025

### Summary
Successfully migrated Cedar CLI from GPT-4/chat completions API to GPT-5 responses API, which became fully available on August 1, 2025.

### Key Changes Made

1. **Removed all GPT-4 and chat/completions backward compatibility code**
   - Eliminated model-based conditional logic that selected between endpoints
   - Removed all references to the legacy `/v1/chat/completions` endpoint
   - Removed fallback logic for parsing old `choices` array format

2. **Standardized on GPT-5 /v1/responses API**
   - All LLM calls now use `/v1/responses` endpoint exclusively
   - Using GPT-5 model: `gpt-5-2025-08-07` (current production version)

### Critical Implementation Details

#### Request Format (What Works)
```json
{
  "model": "gpt-5-2025-08-07",
  "input": "single string input",  // NOT "input_items" array
  "text": {
    "format": {
      "type": "json_object"
    }
  }
}
```

#### Parameters That Break GPT-5 (DO NOT USE)
1. **`max_output_tokens`** - Causes GPT-5 to return empty content
2. **`temperature`** - Not supported by GPT-5 responses API
3. **`messages` array** - Use single `input` string instead
4. **`response_format`** - Use `text.format.type` for JSON mode
5. **`input_items`** - The correct parameter is `input` (single string)

#### Response Format
GPT-5 returns an `output` array with typed items:
```json
{
  "output": [
    { "type": "reasoning", ... },  // Optional reasoning trace
    { "type": "message", "content": [ 
      { "type": "text", "text": "actual response content" } 
    ]}
  ]
}
```

### Why Previous Implementation Failed

1. **Incorrect parameter names**: Used `input_items` instead of `input`
2. **Breaking parameters**: Included `max_output_tokens` which causes empty responses
3. **Unsupported parameters**: Used `temperature` which isn't supported
4. **Wrong response format**: Used `response_format` instead of `text.format`
5. **Mixed API patterns**: Tried to support both old and new APIs simultaneously

### Testing Recommendations

1. Always use model `gpt-5-2025-08-07` or later
2. Test with the exact request format specified above
3. Never add `max_output_tokens` or `temperature` parameters
4. Verify response parsing handles the `output` array structure

### Files Modified

- `/crates/notebook_core/src/agent_loop.rs`
  - Removed all GPT-4/chat completions compatibility code
  - Standardized on GPT-5 responses API
  - Added comprehensive documentation about what breaks GPT-5

### Notes for Future Development

- GPT-5 responses API is now the standard for all new OpenAI models
- The old chat/completions API should be considered deprecated
- Always consult the latest OpenAI documentation for any new parameters
- Be extremely careful about adding new parameters - test thoroughly as they may break output
