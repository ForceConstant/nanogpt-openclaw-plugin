#!/bin/bash
# Integration test script for nano-gpt-plugin using clawhub installation
# Installs the published plugin from clawhub instead of local build

set -euo pipefail

# Configuration
DATE=$(date +%Y-%m-%d)
PLUGIN_DIR="/workspace/nano-gpt-plugin"
REMOTE_HOST="ssh_gateway"

echo "Starting integration test for nano-gpt-plugin (clawhub)"
echo "Date: $DATE"
echo "Remote host: $REMOTE_HOST"


set -x

# 1) Remove existing plugin, reset config, and install from clawhub
echo "Step 1: Installing plugin from clawhub..."
ssh -o ConnectTimeout=120 "$REMOTE_HOST" "set -x ; rm -rf /home/node/.openclaw/extensions/nano-gpt 2>/dev/null; rm ~/.openclaw/agents/main/sessions/* ; rm -f ~/.openclaw/openclaw.json ; openclaw plugins install clawhub:@forceconstant/nano-gpt"

# 2) Onboard with NanoGPT (before gateway starts, so config exists)
echo "Step 2: Onboarding with NanoGPT..."
ssh -o ConnectTimeout=30 "$REMOTE_HOST" "openclaw onboard --non-interactive --accept-risk --nano-gpt-api-key \"$NANOGPT_API_KEY\" --flow quickstart --skip-health"

# 3) Start gateway
echo "Step 3: Starting gateway..."
ssh -o ConnectTimeout=30 "$REMOTE_HOST" "nohup openclaw gateway run > /tmp/gateway.log 2>&1 & sleep 5; openclaw gateway health"

# 4) Set default model
echo "Step 4: Setting default model..."
ssh -o ConnectTimeout=30 "$REMOTE_HOST" "openclaw models set nano-gpt/minimax/minimax-m2.7"

ssh -o ConnectTimeout=30 "$REMOTE_HOST" "openclaw models list"

# 5) Run test agent with proper session ID
echo "Step 5: Running test agent..."
ssh -o ConnectTimeout=30 "$REMOTE_HOST" "
  SESSION_ID=\"test-nano-clawhub-\$(date +%s)\"
  echo \"Using session ID: \$SESSION_ID\"
  openclaw agent --session-id \"\$SESSION_ID\" --message 'My name is Test. You are Helper. Say hello.' --timeout 120

  # Give it a moment to finish
  sleep 2

  # Save the session ID for collection
  echo \"\$SESSION_ID\" > /tmp/last_session_id.txt
"

# 6) Wait a bit more for file to be written
echo "Step 6: Waiting for session file to be written..."
sleep 3

# 7) Collect gateway logs (contains prepareExtraParams debug output)
echo "Step 7: Collecting gateway logs..."
mkdir -p "$PLUGIN_DIR/test_results/$DATE"
scp "$REMOTE_HOST:/tmp/gateway.log" "$PLUGIN_DIR/test_results/$DATE/gateway.log" 2>/dev/null || true

# 8) Collect results
echo "Step 8: Collecting results..."
LAST_SESSION_ID=$(ssh -o ConnectTimeout=30 "$REMOTE_HOST" "cat /tmp/last_session_id.txt 2>/dev/null || echo 'test-nano-clawhub-$(date +%s)'")
echo "Looking for session: $LAST_SESSION_ID"

scp "$REMOTE_HOST:/home/node/.openclaw/agents/main/session/${LAST_SESSION_ID}.jsonl" "$PLUGIN_DIR/test_results/$DATE/" 2>/dev/null || true

# Also collect any test-nano files from recent runs as fallback
scp "$REMOTE_HOST:/home/node/.openclaw/agents/main/sessions/test-nano-*.jsonl" "$PLUGIN_DIR/test_results/$DATE/" 2>/dev/null || true

echo "Results collected to: $PLUGIN_DIR/test_results/$DATE/"
ls -la "$PLUGIN_DIR/test_results/$DATE/" || echo "No files in results directory"

echo "Integration test (clawhub) completed successfully!"
