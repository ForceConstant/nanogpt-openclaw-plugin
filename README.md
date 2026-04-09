# nano-gpt-plugin

NanoGPT provider plugin for OpenClaw

## Features

- Dynamic model catalog from `https://nano-gpt.com/api/v1/models?detailed=true`
- Auto-populates model capabilities (vision, reasoning, context window, pricing)
- Handles `NANOGPT_API_KEY` environment variable
- Provides `openclaw onboard --nano-gpt-api-key <key>` flow
- Includes `include_usage: true` on all outgoing requests for accurate token tracking
- Subscription usage tracking via `/api/subscription/v1/usage`
- Balance checking via `/api/check-balance`
- Supports all NanoGPT model families: OpenAI, Anthropic, Google, xAI, DeepSeek, Moonshot, Qwen, Groq, and 50+ more

## Installation

### From clawhub

```bash
openclaw plugins install clawhub:@forceconstant/nano-gpt
openclaw onboard --non-interactive --nano-gpt-api-key "$NANOGPT_API_KEY" --flow quickstart
```
- Note for multi-agent setups, you will need to copy the auth-profile.json to each agent.
- Recommend also deleting each agents models.json to make sure all models are up to date.

### Local development

Clone this repository and link it:

```bash
git clone <this-repo>
cd nano-gpt-plugin
pnpm install
pnpm run build
```

Then, in your OpenClaw workspace, you can use the plugin by referencing the built `dist` directory.

## Usage

### Onboarding

To add your NanoGPT API key:

```bash
openclaw onboard --nano-gpt-api-key <your-key>
```

This will store the key in your OpenClaw configuration.

### Using models

Once onboarded, you can use any model from NanoGPT by referencing it with the `nano-gpt/` prefix:

```bash
openclaw chat --model nano-gpt/openai/gpt-5.2 "Hello, world!"
```

Or in your agent configuration:

```json
{
  "model": "nano-gpt/anthropic/claude-opus-4.6"
}
```

### Usage and balance

To check your usage and balance:

```bash
openclaw status
```

This will show your daily/monthly token usage and remaining balance.

## Configuration

The plugin does not require any additional configuration beyond the API key.

## Development

### Building

```bash
pnpm run build
```

### Testing

```bash
pnpm test
```

### Linting

```bash
pnpm run lint
```

## License

MIT
