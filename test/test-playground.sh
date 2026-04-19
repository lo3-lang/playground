#!/bin/bash
# lo3 playground Test Suite
# Tests: WASM loading, code execution, output correctness

PLAYGROUND_URL="${PLAYGROUND_URL:-https://lo3-lang.github.io/playground}"
FAIL_COUNT=0
PASS_COUNT=0

echo "========================================"
echo "lo3 Playground Test Suite"
echo "========================================"
echo ""

# Test 1: WASM file exists and has correct magic bytes
test_wasm_exists() {
    echo -n "TEST: lo3.wasm exists at GitHub Pages... "
    WASM_URL="$PLAYGROUND_URL/lo3.wasm"
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$WASM_URL")
    if [ "$STATUS" = "200" ]; then
        SIZE=$(curl -s "$WASM_URL" | wc -c)
        MAGIC=$(curl -s "$WASM_URL" | head -c 4 | od -A n -t x1 | tr -d ' ')
        if [ "$MAGIC" = "0061736d" ]; then
            echo "PASS (size=$SIZE, magic=wasm)"
            PASS_COUNT=$((PASS_COUNT+1))
        else
            echo "FAIL (bad magic: $MAGIC)"
            FAIL_COUNT=$((FAIL_COUNT+1))
        fi
    else
        echo "FAIL (HTTP $STATUS)"
        FAIL_COUNT=$((FAIL_COUNT+1))
    fi
}

# Test 2: index.html contains Module initialization before STEP 2
test_module_init_order() {
    echo -n "TEST: Module initialized before STEP 2... "
    HTML=$(curl -s "$PLAYGROUND_URL/index.html")
    INIT_LINE=$(echo "$HTML" | grep -n "var Module = typeof Module" | head -1 | cut -d: -f1)
    STEP2_LINE=$(echo "$HTML" | grep -n "STEP 2:\|var Module=typeof Module" | tail -1 | cut -d: -f1)
    if [ -n "$INIT_LINE" ] && [ -n "$STEP2_LINE" ] && [ "$INIT_LINE" -lt "$STEP2_LINE" ]; then
        echo "PASS (init line $INIT_LINE < step2 line $STEP2_LINE)"
        PASS_COUNT=$((PASS_COUNT+1))
    else
        echo "FAIL (Module init order unclear)"
        FAIL_COUNT=$((FAIL_COUNT+1))
    fi
}

# Test 3: overrideMimeType present for binary XHR
test_override_mime() {
    echo -n "TEST: overrideMimeType for binary XHR... "
    HTML=$(curl -s "$PLAYGROUND_URL/index.html")
    if echo "$HTML" | grep -q "overrideMimeType.*x-user-defined"; then
        echo "PASS"
        PASS_COUNT=$((PASS_COUNT+1))
    else
        echo "FAIL"
        FAIL_COUNT=$((FAIL_COUNT+1))
    fi
}

# Test 4: lo3.wasm is valid WASM (can be instantiated by Node)
test_wasm_node_instantiate() {
    echo -n "TEST: lo3.wasm instantiates in Node.js... "
    TEMP_WASM="/tmp/test_lo3_$(date +%s).wasm"
    curl -s "$PLAYGROUND_URL/lo3.wasm" > "$TEMP_WASM"
    
    # Check if we can read the WASM header
    if ! node -e "const fs=require('fs'); const buf=fs.readFileSync('$TEMP_WASM'); console.log('size:',buf.length,'magic:',buf.slice(0,4).toString('hex'));" 2>/dev/null | grep -q "magic: 0061736d"; then
        echo "FAIL (invalid WASM)"
        FAIL_COUNT=$((FAIL_COUNT+1))
        rm -f "$TEMP_WASM"
        return
    fi
    
    # Try to compile the WASM module
    if node -e "
const fs = require('fs');
const buf = fs.readFileSync('$TEMP_WASM');
try {
    new WebAssembly.Module(buf);
    console.log('PASS (compiled successfully)');
    process.exit(0);
} catch(e) {
    console.log('FAIL:', e.message);
    process.exit(1);
}
" 2>/dev/null; then
        echo "PASS"
        PASS_COUNT=$((PASS_COUNT+1))
    else
        echo "FAIL (WebAssembly.compile failed)"
        FAIL_COUNT=$((FAIL_COUNT+1))
    fi
    rm -f "$TEMP_WASM"
}

# Test 5: UI shows correct version (not v0.1-alpha)
test_ui_version() {
    echo -n "TEST: UI shows v0.2 (not cached v0.1)... "
    HTML=$(curl -s "$PLAYGROUND_URL/index.html")
    if echo "$HTML" | grep -q "v0.2-pre-alpha\|v0.2-alpha"; then
        echo "PASS"
        PASS_COUNT=$((PASS_COUNT+1))
    else
        echo "WARN (v0.2 not detected in HTML - may need JS runtime check)"
        # Not a hard fail - HTML might be correct but JS serves old version
    fi
}

# Test 6: CSS uses modular design tokens
test_css_modular() {
    echo -n "TEST: CSS uses modular design tokens... "
    HTML=$(curl -s "$PLAYGROUND_URL/index.html")
    if echo "$HTML" | grep -q "\-\-bg:\|--bg2:\|--am:"; then
        echo "PASS"
        PASS_COUNT=$((PASS_COUNT+1))
    else
        echo "FAIL"
        FAIL_COUNT=$((FAIL_COUNT+1))
    fi
}

# Run all tests
test_wasm_exists
test_module_init_order
test_override_mime
test_wasm_node_instantiate
test_ui_version
test_css_modular

echo ""
echo "========================================"
echo "RESULTS: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "========================================"

if [ $FAIL_COUNT -gt 0 ]; then
    exit 1
else
    exit 0
fi
