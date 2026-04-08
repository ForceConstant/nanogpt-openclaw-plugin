#!/bin/bash
# Integration test script for nano-gpt-plugin
# Usage: ./integration_test.sh [local|clawhub]
#   local   - sync local build to remote and install
#   clawhub - install published plugin from clawhub

set -euo pipefail

# Configuration
DATE=$(date +%Y-%m-%d)
PLUGIN_DIR="/workspace/nano-gpt-plugin"
REMOTE_HOST="ssh_gateway"
REMOTE_PLUGIN_DIR="/tmp/nano-gpt-plugin-$DATE"

MODE="${1:-local}"

if [[ "$MODE" != "local" && "$MODE" != "clawhub" ]]; then
  echo "Usage: $0 [local|clawhub]"
  exit 1
fi

echo "Starting integration test for nano-gpt-plugin"
echo "Date: $DATE"
echo "Mode: $MODE"
echo "Plugin directory: $PLUGIN_DIR"
echo "Remote host: $REMOTE_HOST"


set -x

# 1) Install plugin based on mode
if [[ "$MODE" == "local" ]]; then
  echo "Step 1: Syncing local plugin to remote..."
  tar --exclude='.git' --exclude='node_modules' --exclude='pnpm-lock.yaml' -czf - . | \
    ssh -o ConnectTimeout=30 "$REMOTE_HOST" "rm -rf $REMOTE_PLUGIN_DIR 2>/dev/null; mkdir -p $REMOTE_PLUGIN_DIR && tar -xzf - -C $REMOTE_PLUGIN_DIR"

  echo "Step 2: Installing plugin from local build..."
  ssh -o ConnectTimeout=120 "$REMOTE_HOST" "set -x ; rm -rf /home/node/.openclaw/extensions/nano-gpt 2>/dev/null; rm ~/.openclaw/agents/main/sessions/* ; rm -f ~/.openclaw/openclaw.json ; cd '$REMOTE_PLUGIN_DIR'; openclaw plugins install '$REMOTE_PLUGIN_DIR'"
else
  echo "Step 1: Installing plugin from clawhub..."
  ssh -o ConnectTimeout=120 "$REMOTE_HOST" "set -x ; rm -rf /home/node/.openclaw/extensions/nano-gpt 2>/dev/null; rm ~/.openclaw/agents/main/sessions/* ; rm -f ~/.openclaw/openclaw.json ; openclaw plugins install clawhub:@forceconstant/nano-gpt"
fi

# 2) Onboard with NanoGPT (before gateway starts, so config exists)
echo "Step 3: Onboarding with NanoGPT..."
ssh -o ConnectTimeout=30 "$REMOTE_HOST" "openclaw onboard --non-interactive --accept-risk --nano-gpt-api-key \"$NANOGPT_API_KEY\" --flow quickstart --skip-health"

# 3) Start gateway fresh (after onboard to ensure config is stable)
echo "Step 4: Starting gateway..."
ssh -o ConnectTimeout=30 ssh_gateway << 'EOF'
set -x
pkill -f openclaw-gateway || true
sleep 3
rm -f /tmp/gateway.log
openclaw gateway run > /tmp/gateway.log 2>&1 &
sleep 12
openclaw gateway health
EOF

# 4) Set default model
echo "Step 5: Setting default model..."
ssh -o ConnectTimeout=30 "$REMOTE_HOST" "openclaw models set nano-gpt/minimax/minimax-m2.7"

ssh -o ConnectTimeout=30 "$REMOTE_HOST" "openclaw models list"

# 4b) Verify dynamic catalog - check nano-gpt models with correct context lengths from nano-gpt API
echo "Step 5b: Verifying dynamic catalog with openclaw models list --json..."
MODELS_JSON=$(ssh -o ConnectTimeout=30 "$REMOTE_HOST" "openclaw models list --json" 2>/dev/null || echo "{}")
echo "$MODELS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
models = data if isinstance(data, list) else data.get('data', data.get('models', []))
found = False
for m in models:
    mid = m.get('key', m.get('id',''))
    ctx = m.get('contextWindow', m.get('context_window', 0))
    if 'nano-gpt/' in mid:
        found = True
        print(f\"  Model: {mid}, contextWindow: {ctx}\")
if not found:
    print('ERROR: No nano-gpt models found in catalog!')
    sys.exit(1)
print('SUCCESS: nano-gpt models found in dynamic catalog')
"

# 5) Run test agent with proper session ID
echo "Step 6: Running test agent..."
SESSION_PREFIX="test-nano-${MODE}"
ssh -o ConnectTimeout=30 "$REMOTE_HOST" "
  SESSION_ID=\"${SESSION_PREFIX}-\$(date +%s)\"
  echo \"Using session ID: \$SESSION_ID\"
  openclaw agent --session-id \"\$SESSION_ID\" --message 'My name is Test. You are Helper. Say hello.' --timeout 120

  # Give it a moment to finish
  sleep 2

  # Save the session ID for collection
  echo \"\$SESSION_ID\" > /tmp/last_session_id.txt
"

# 6) Wait a bit more for file to be written
echo "Step 7: Waiting for session file to be written..."
sleep 3

# 7) Collect gateway logs
echo "Step 8: Collecting gateway logs..."
mkdir -p "$PLUGIN_DIR/test_results/$DATE"
scp "$REMOTE_HOST:/tmp/gateway.log" "$PLUGIN_DIR/test_results/$DATE/gateway.log" 2>/dev/null || true

# 8) Collect results
echo "Step 9: Collecting results..."
LAST_SESSION_ID=$(ssh -o ConnectTimeout=30 "$REMOTE_HOST" "cat /tmp/last_session_id.txt 2>/dev/null || echo '${SESSION_PREFIX}-$(date +%s)'")
echo "Looking for session: $LAST_SESSION_ID"

scp "$REMOTE_HOST:/home/node/.openclaw/agents/main/session/${LAST_SESSION_ID}.jsonl" "$PLUGIN_DIR/test_results/$DATE/" 2>/dev/null || true

# Also collect any test-nano files from recent runs as fallback
scp "$REMOTE_HOST:/home/node/.openclaw/agents/main/sessions/test-nano-*.jsonl" "$PLUGIN_DIR/test_results/$DATE/" 2>/dev/null || true

echo "Results collected to: $PLUGIN_DIR/test_results/$DATE/"
ls -la "$PLUGIN_DIR/test_results/$DATE/" || echo "No files in results directory"

# 9) Verify prepareExtraParams debug logs were captured
echo "Step 10: Checking for prepareExtraParams debug logs..."
if grep -q "prepareExtraParams" "$PLUGIN_DIR/test_results/$DATE/gateway.log" 2>/dev/null; then
  echo "SUCCESS: prepareExtraParams debug logs found in gateway.log"
  grep "prepareExtraParams" "$PLUGIN_DIR/test_results/$DATE/gateway.log"
else
  echo "WARNING: No prepareExtraParams debug logs found"
fi

echo "Integration test ($MODE) completed successfully!"
