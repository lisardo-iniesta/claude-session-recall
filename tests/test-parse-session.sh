#!/usr/bin/env bash
# Test harness for parse-session.py — 7 test cases.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PARSER="$REPO_DIR/lib/parse-session.py"
TEST_DIR="/tmp/test-parse-session-$$"
SAMPLES_DIR="$TEST_DIR/samples"
OUTPUT_DIR="$TEST_DIR/output"
PASS=0
FAIL=0
TOTAL=0

rm -rf "$TEST_DIR"
mkdir -p "$SAMPLES_DIR" "$OUTPUT_DIR"

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

green() { printf "\033[32m%s\033[0m\n" "$1"; }
red() { printf "\033[31m%s\033[0m\n" "$1"; }

run_test() {
    TOTAL=$((TOTAL + 1))
}

# --- Test 1: Happy path (multi-message with text + tool_use) ---
cat > "$SAMPLES_DIR/happy.jsonl" << 'JSONL'
{"type":"progress","sessionId":"test-happy","cwd":"/Users/test/myproject","gitBranch":"main","data":{"type":"hook_progress"}}
{"type":"user","sessionId":"test-happy","cwd":"/Users/test/myproject","gitBranch":"main","message":{"role":"user","content":"How does the auth system work? I need to understand the flow before making changes."}}
{"type":"assistant","sessionId":"test-happy","cwd":"/Users/test/myproject","gitBranch":"main","message":{"model":"claude-opus-4-6","role":"assistant","content":[{"type":"thinking","thinking":"Let me analyze the auth flow..."},{"type":"text","text":"The authentication system uses a three-step flow: first the client sends credentials to the auth endpoint, then the server validates against the database, and finally issues a JWT token. The token refresh mechanism handles expiration by checking the token's exp claim before each API call. If expired, it transparently refreshes using the refresh token stored in an httpOnly cookie. The middleware stack includes rate limiting at the gateway level, CORS configuration for allowed origins, and request logging for audit trails. Each request passes through the authentication middleware which extracts the Bearer token from the Authorization header, validates its signature using the RS256 algorithm with the public key from the JWKS endpoint, checks the token expiration and issuer claims, and attaches the decoded user object to the request context for downstream handlers."},{"type":"tool_use","id":"toolu_1","name":"Read","input":{"file_path":"/src/auth.ts"}}]}}
{"type":"assistant","sessionId":"test-happy","cwd":"/Users/test/myproject","gitBranch":"main","message":{"model":"claude-opus-4-6","role":"assistant","content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"export function authenticate..."},{"type":"text","text":"Looking at the code, I can see the middleware validates tokens on every request. The key function is validateToken which checks both signature and expiration. There are also rate limiting hooks that throttle failed attempts to prevent brute force attacks. The implementation uses a sliding window counter stored in Redis with a default limit of 10 failed attempts per minute per IP address. After exceeding the limit, requests receive a 429 status code with a Retry-After header indicating when the window resets."}]}}
{"type":"user","sessionId":"test-happy","cwd":"/Users/test/myproject","gitBranch":"main","message":{"role":"user","content":"Great explanation. Let's add a logout endpoint that invalidates the refresh token."}}
{"type":"assistant","sessionId":"test-happy","cwd":"/Users/test/myproject","gitBranch":"main","timestamp":"2026-03-05T10:30:00Z","message":{"model":"claude-opus-4-6","role":"assistant","content":[{"type":"text","text":"I'll create a logout endpoint that adds the refresh token to a denylist. This is more robust than simply deleting the cookie because it handles cases where the token was copied or intercepted."}]}}
JSONL

run_test
echo -n "Test 1 (happy path): "
RESULT=$(python3 "$PARSER" "$SAMPLES_DIR/happy.jsonl" "$OUTPUT_DIR" 2>/dev/null)
if [ -n "$RESULT" ] && [ -f "$RESULT" ]; then
    if grep -q "session_id: test-happy" "$RESULT" && \
       grep -q "## User" "$RESULT" && \
       grep -q "## Assistant" "$RESULT" && \
       grep -q "authentication system" "$RESULT" && \
       ! grep -q "tool_use" "$RESULT" && \
       ! grep -q "toolu_1" "$RESULT"; then
        green "PASS"
        PASS=$((PASS+1))
    else
        red "FAIL — content mismatch"
        FAIL=$((FAIL+1))
    fi
else
    red "FAIL — no output file"
    FAIL=$((FAIL+1))
fi

# --- Test 2: Trivial session (< 200 words) — must be skipped ---
cat > "$SAMPLES_DIR/trivial.jsonl" << 'JSONL'
{"type":"user","sessionId":"test-trivial","cwd":"/Users/test/p","gitBranch":"main","message":{"role":"user","content":"hi"}}
{"type":"assistant","sessionId":"test-trivial","cwd":"/Users/test/p","gitBranch":"main","timestamp":"2026-03-05T10:00:00Z","message":{"model":"claude-opus-4-6","role":"assistant","content":[{"type":"text","text":"Hello! How can I help?"}]}}
JSONL

run_test
echo -n "Test 2 (trivial skip): "
RESULT=$(python3 "$PARSER" "$SAMPLES_DIR/trivial.jsonl" "$OUTPUT_DIR" 2>/dev/null)
if [ -z "$RESULT" ]; then
    green "PASS (correctly skipped)"
    PASS=$((PASS+1))
else
    red "FAIL — should have been skipped but produced: $RESULT"
    FAIL=$((FAIL+1))
fi

# --- Test 3: Tool-only session (no text blocks) ---
cat > "$SAMPLES_DIR/toolonly.jsonl" << 'JSONL'
{"type":"user","sessionId":"test-toolonly","cwd":"/Users/test/p","gitBranch":"main","message":{"role":"user","content":"read the file"}}
{"type":"assistant","sessionId":"test-toolonly","cwd":"/Users/test/p","gitBranch":"main","timestamp":"2026-03-05T10:00:00Z","message":{"model":"claude-opus-4-6","role":"assistant","content":[{"type":"tool_use","id":"toolu_2","name":"Read","input":{"file_path":"/tmp/x"}}]}}
JSONL

run_test
echo -n "Test 3 (tool-only skip): "
RESULT=$(python3 "$PARSER" "$SAMPLES_DIR/toolonly.jsonl" "$OUTPUT_DIR" 2>/dev/null)
if [ -z "$RESULT" ]; then
    green "PASS (correctly skipped)"
    PASS=$((PASS+1))
else
    red "FAIL — should have been skipped"
    FAIL=$((FAIL+1))
fi

# --- Test 4: Corrupted JSONL (truncated line) — must not crash ---
cat > "$SAMPLES_DIR/corrupted.jsonl" << 'JSONL'
{"type":"user","sessionId":"test-corrupt","cwd":"/Users/test/myproject","gitBranch":"main","message":{"role":"user","content":"Tell me about the architecture of our system and how the different microservices communicate with each other through the message bus and event system."}}
{"type":"assistant","sessionId":"test-corrupt","cwd":"/Users/test/myproject","gitBranch":"main","message":{"model":"claud
{"type":"assistant","sessionId":"test-corrupt","cwd":"/Users/test/myproject","gitBranch":"main","timestamp":"2026-03-05T10:00:00Z","message":{"model":"claude-opus-4-6","role":"assistant","content":[{"type":"text","text":"The system architecture follows a microservices pattern with an event-driven message bus. Each service publishes domain events that other services consume asynchronously. The message bus uses RabbitMQ with topic exchanges for flexible routing. Services communicate through well-defined protobuf schemas ensuring backward compatibility. The API gateway handles external requests and routes them to the appropriate service. Health checks and circuit breakers prevent cascade failures across the service mesh. Monitoring uses Prometheus metrics exported from each service with Grafana dashboards for visualization. The deployment pipeline uses GitLab CI with three stages: build, test, and deploy. Each microservice has its own Dockerfile optimized with multi-stage builds to minimize image size. The container orchestration layer runs on Kubernetes with Helm charts for each service defining resource limits, autoscaling policies, and network policies. Service discovery uses CoreDNS within the cluster, while external traffic enters through an Nginx ingress controller with TLS termination. The logging infrastructure aggregates logs from all services using Fluentd daemonsets that forward to Elasticsearch, with Kibana providing the search and visualization interface for debugging production issues across the distributed system."}]}}
JSONL

run_test
echo -n "Test 4 (corrupted line): "
RESULT=$(python3 "$PARSER" "$SAMPLES_DIR/corrupted.jsonl" "$OUTPUT_DIR" 2>/dev/null)
if [ -n "$RESULT" ] && [ -f "$RESULT" ]; then
    if grep -q "microservices" "$RESULT" && grep -q "message bus" "$RESULT"; then
        green "PASS (skipped bad line, kept good content)"
        PASS=$((PASS+1))
    else
        red "FAIL — content missing"
        FAIL=$((FAIL+1))
    fi
else
    red "FAIL — crashed or no output"
    FAIL=$((FAIL+1))
fi

# --- Test 5: Compacted/summary session ---
cat > "$SAMPLES_DIR/compacted.jsonl" << 'JSONL'
{"type":"summary","sessionId":"test-compact","cwd":"/Users/test/p","gitBranch":"main","summary":"This session discussed implementing a caching layer for the API.","timestamp":"2026-03-05T10:00:00Z"}
{"type":"user","sessionId":"test-compact","cwd":"/Users/test/p","gitBranch":"main","message":{"role":"user","content":"ok that's enough for today"}}
{"type":"assistant","sessionId":"test-compact","cwd":"/Users/test/p","gitBranch":"main","timestamp":"2026-03-05T10:00:00Z","message":{"model":"claude-opus-4-6","role":"assistant","content":[{"type":"text","text":"Understood, wrapping up."}]}}
JSONL

run_test
echo -n "Test 5 (compacted session): "
RESULT=$(python3 "$PARSER" "$SAMPLES_DIR/compacted.jsonl" "$OUTPUT_DIR" 2>/dev/null)
if [ -z "$RESULT" ]; then
    green "PASS (correctly skipped short compacted session)"
    PASS=$((PASS+1))
else
    red "FAIL — should have been skipped (compacted + short)"
    FAIL=$((FAIL+1))
fi

# --- Test 6: Project name uses directory name (no hardcoded path) ---
cat > "$SAMPLES_DIR/project-name.jsonl" << 'JSONL'
{"type":"user","sessionId":"test-projname","cwd":"/home/dev/my-cool-project","gitBranch":"develop","message":{"role":"user","content":"Explain the deployment pipeline in detail including the build steps, testing phases, staging environment setup, and production rollout strategy with canary deployments and automated rollback mechanisms. Also cover monitoring and alerting."}}
{"type":"assistant","sessionId":"test-projname","cwd":"/home/dev/my-cool-project","gitBranch":"develop","timestamp":"2026-03-05T14:00:00Z","message":{"model":"claude-opus-4-6","role":"assistant","content":[{"type":"text","text":"The deployment pipeline consists of five stages. First, the CI server runs unit tests and integration tests in parallel Docker containers. Then the build step creates optimized production artifacts using multi-stage Docker builds. The staging environment is provisioned automatically using Terraform and receives the new build for smoke testing. Once staging tests pass, the canary deployment begins by routing five percent of production traffic to the new version while monitoring error rates, latency percentiles, and business metrics. If all health checks pass for thirty minutes, traffic is gradually increased to full rollout. The automated rollback mechanism watches for anomalies using statistical process control charts and can revert within sixty seconds if degradation is detected. Each stage publishes metrics to our observability platform for real-time monitoring and historical analysis. The alerting system uses PagerDuty integration with escalation policies that notify the on-call engineer within two minutes of any critical threshold breach. Deployment notifications are sent to the team Slack channel with links to the monitoring dashboard and rollback button. Post-deployment validation runs synthetic transactions against production endpoints to verify correctness."}]}}
JSONL

run_test
echo -n "Test 6 (project name from dir): "
RESULT=$(python3 "$PARSER" "$SAMPLES_DIR/project-name.jsonl" "$OUTPUT_DIR" 2>/dev/null)
if [ -n "$RESULT" ] && [ -f "$RESULT" ]; then
    # Project name should be "my-cool-project" (directory name), not hardcoded
    if grep -q "project: my-cool-project" "$RESULT"; then
        green "PASS"
        PASS=$((PASS+1))
    else
        red "FAIL — project name not extracted from directory"
        cat "$RESULT" | head -10
        FAIL=$((FAIL+1))
    fi
else
    red "FAIL — no output file"
    FAIL=$((FAIL+1))
fi

# --- Test 7: Date from explicit timestamp (not last loop variable) ---
cat > "$SAMPLES_DIR/timestamp.jsonl" << 'JSONL'
{"type":"user","sessionId":"test-date","cwd":"/Users/test/p","gitBranch":"main","timestamp":"2026-01-15T09:00:00Z","message":{"role":"user","content":"Help me design a comprehensive caching strategy for our API that handles cache invalidation, TTL policies, cache warming, and distributed cache synchronization across multiple data centers. Include monitoring and debugging strategies."}}
{"type":"assistant","sessionId":"test-date","cwd":"/Users/test/p","gitBranch":"main","timestamp":"2026-01-15T09:05:00Z","message":{"model":"claude-opus-4-6","role":"assistant","content":[{"type":"text","text":"For a robust distributed caching strategy, I recommend a layered approach. The first layer uses in-process caches with short TTLs for frequently accessed data. The second layer uses Redis clusters with longer TTLs and supports pub/sub for cache invalidation events. The third layer uses CDN edge caching for static and semi-static responses. Cache warming runs on deployment by pre-populating popular queries from the previous cache state. The invalidation strategy uses event-driven updates where write operations publish domain events that trigger targeted cache purges. For cross-datacenter synchronization, we use a replicated log that each datacenter consumes independently, ensuring eventual consistency with conflict resolution based on vector clocks and last-writer-wins semantics. TTL policies are configured per resource type: user profiles get fifteen minutes, product listings get five minutes, and real-time data bypasses cache entirely. For monitoring, instrument cache hit rates, miss rates, and eviction counts per resource type using Prometheus counters and histograms. Set up Grafana dashboards showing cache efficiency over time with anomaly detection alerts. For debugging, add request-level cache trace headers that show which layers served the response and whether it was a hit or miss at each level."}]}}
{"type":"last-prompt","lastPrompt":"y","sessionId":"test-date"}
JSONL

run_test
echo -n "Test 7 (date from timestamp): "
RESULT=$(python3 "$PARSER" "$SAMPLES_DIR/timestamp.jsonl" "$OUTPUT_DIR" 2>/dev/null)
if [ -n "$RESULT" ] && [ -f "$RESULT" ]; then
    # Date should be 2026-01-15 from the timestamp, not today's date
    if grep -q "date: 2026-01-15" "$RESULT"; then
        green "PASS"
        PASS=$((PASS+1))
    else
        red "FAIL — date not extracted from timestamp"
        grep "date:" "$RESULT"
        FAIL=$((FAIL+1))
    fi
else
    red "FAIL — no output file"
    FAIL=$((FAIL+1))
fi

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed out of $TOTAL tests"
if [ "$FAIL" -eq 0 ]; then
    green "ALL TESTS PASSED"
    exit 0
else
    red "SOME TESTS FAILED"
    exit 1
fi
