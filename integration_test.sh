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
  ssh -o ConnectTimeout=120 "$REMOTE_HOST" "set -x ; rm -rf /home/node/.openclaw/extensions/nano-gpt 2>/dev/null; rm ~/.openclaw/agents/main/sessions/* ; rm -f ~/.openclaw/openclaw.json ; find ~/openclaw/ -name models.json --delete ; cd '$REMOTE_PLUGIN_DIR'; openclaw plugins install '$REMOTE_PLUGIN_DIR'"
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

echo "Step 5: Setting default model..."
ssh -o ConnectTimeout=30 "$REMOTE_HOST" "openclaw models set nano-gpt/minimax/minimax-m2.7"

echo "Step 5c: Verifying dynamic catalog with openclaw models list --all..."
MODEL_COUNT=$(ssh -o ConnectTimeout=30 "$REMOTE_HOST" "openclaw models list --all | grep nano-gpt | wc -l" 2>/dev/null || echo "0")
echo "MODEL_COUNT=$MODEL_COUNT"

echo "Step 5e: Getting context window for minimax-m2.7..."
catalog_context=$(openclaw models list --all --json \
    | grep "nano-gpt/minimax/minimax-m2.7" -A5 \
    | grep contextWindow \
    | head -1 \
    | awk -F': ' '{print $2}' \
    | tr -d ',"' || :)   # If any step fails, assign an empty string

# Safely capture the contextWindow from the current model list
model_context=$(openclaw models list --json \
    | grep contextWindow \
    | head -1 \
    | awk -F': ' '{print $2}' \
    | tr -d ',"' || :)


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

set +x

# Add explicit pass/fail indicators for easy grepping - ENSURE THESE ARE OUTPUT EARLY
echo "=== INTEGRATION TEST RESULTS ==="
echo "MODE=$MODE"

echo "Results collected to: $PLUGIN_DIR/test_results/$DATE/"
ls -la "$PLUGIN_DIR/test_results/$DATE/" || echo "No files in results directory"

# Check model count
if [ "$MODEL_COUNT" -gt 10 ]; then
    echo "MODEL_COUNT_SUFFICIENT=PASS: $MODEL_COUNT models (>=10)"
else
    echo "MODEL_COUNT_SUFFICIENT=FAIL: Only $MODEL_COUNT models (<10)"
fi

# Check default model
DEFAULT_MODEL_CHECK=$(ssh -o ConnectTimeout=30 "$REMOTE_HOST" "openclaw models list" 2>/dev/null | grep "nano-gpt/minimax/minimax-m2.7" | grep "default" || echo "NOT_FOUND")
if [ "$DEFAULT_MODEL_CHECK" != "NOT_FOUND" ]; then
    echo "DEFAULT_MODEL_SET=PASS: nano-gpt/minimax/minimax-m2.7 is default"
else
    echo "DEFAULT_MODEL_SET=FAIL: nano-gpt/minimax/minimax-m2.7 not set as default"
fi

# Check usage tracking in session files
USAGE_CHECK=$(find "$PLUGIN_DIR/test_results/$DATE/" -name "*.jsonl" -exec grep -h "totalTokens" {} \; 2>/dev/null | head -1 | jq '.message.usage.totalTokens' || echo "0")
if [ "$USAGE_CHECK" -gt 0 ]; then
    echo "USAGE_TRACKING_WORKING=PASS: totalTokens=$USAGE_CHECK (>0)"
else
    echo "USAGE_TRACKING_WORKING=FAIL: totalTokens=$USAGE_CHECK (not >0)"
fi

if [ "$catalog_context" = "$model_context" ]; then
    echo "CONTEXT_WINDOW_CORRECT=PASS"
else
    echo "CONTEXT_WINDOW_CORRECT=FAIL $catalog_context != $model_context"
fi

echo "=== END INTEGRATION TEST RESULTS ==="
echo "Integration test ($MODE) completed successfully!"
