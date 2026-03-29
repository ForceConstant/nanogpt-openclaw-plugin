# Integration Test Commands for nano-gpt-plugin

## Steps executed:

1. Copied plugin to ssh_gateway:
   - `scp -r /workspace/nano-gpt-plugin ssh_gateway:/tmp/` (initially failed due to .git permissions)
   - Created clean tarball: `tar --exclude='.git' -czf nano-gpt-plugin-clean.tar.gz nano-gpt-plugin`
   - `scp /workspace/nano-gpt-plugin-clean.tar.gz ssh_gateway:/tmp/`
   - Extracted on gateway: `tar -xzf nano-gpt-plugin-clean.tar.gz`

2. Set up environment:
   - `mkdir -p /tmp/openclaw_state_$(date +%Y-%m-%d)`
   - Verified NANOGPT_API_KEY: `echo $NANOGPT_API_KEY` (sk-nano-cd2f9d04-e120-4743-b13b-3c770ba17fb8)

3. Installed plugin:
   - `openclaw plugins install .` (in /tmp/nano-gpt-plugin)
   - Required gateway restart due to plugin installation

4. Configured gateway:
   - Set gateway mode to local: `openclaw config set gateway.mode local`
   - Started gateway: `nohup openclaw gateway > /tmp/gateway.log 2>&1 &`
   - Waited for gateway to be ready (checked with `openclaw gateway status`)

5. Onboarded with NanoGPT API key:
   - `openclaw onboard --non-interactive --accept-risk --nano-gpt-api-key $NANOGPT_API_KEY`

6. Set default model:
   - `openclaw models set nano-gpt/nvidia/nemotron-3-super-120b-a12b`

7. Ran integration test:
   - `openclaw agent --session-id integration-test --message "Hello"`

8. Collected results:
   - Copied session file: `scp ssh_gateway:/tmp/openclaw_state_2026-03-29/agents/main/sessions/integration-test.jsonl /workspace/nano-gpt-plugin/test_results/2026-03-29/`
   - Created this commands.md file.

## Notes:
- The test succeeded and the agent responded with: "Hey. I just came online. Who am I? Who are you?"
- The model used was nano-gpt/nvidia/nemotron-3-super-120b-a12b as set.
- The integration test procedure from AGENTS.md was followed with minor adjustments for permission issues and gateway configuration.
