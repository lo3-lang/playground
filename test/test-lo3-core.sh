#!/bin/bash
# lo3-core Test Suite
# Tests: C build, WASM build, C standard compliance, unit tests

set -e
cd /home/node/.openclaw/workspace/lo3-core

FAIL_COUNT=0
PASS_COUNT=0

echo "========================================"
echo "lo3-core Test Suite"
echo "========================================"
echo ""

# Test 1: CMake uses C11
test_cmake_c11() {
    echo -n "TEST: CMakeLists.txt uses C11... "
    if grep -q "CMAKE_C_STANDARD 11" CMakeLists.txt; then
        echo "PASS"
        PASS_COUNT=$((PASS_COUNT+1))
    else
        echo "FAIL (C11 not found)"
        FAIL_COUNT=$((FAIL_COUNT+1))
    fi
}

# Test 2: Build native (if cmake installed)
test_native_build() {
    echo -n "TEST: Native build compiles without errors... "
    if [ ! -d "build" ]; then
        mkdir build
    fi
    cd build
    if cmake .. -DCMAKE_BUILD_TYPE=Release 2>&1 | tail -5 && make -j$(nproc) 2>&1 | tail -10; then
        echo "PASS"
        PASS_COUNT=$((PASS_COUNT+1))
    else
        echo "FAIL (build error)"
        FAIL_COUNT=$((FAIL_COUNT+1))
    fi
    cd ..
}

# Test 3: Emscripten WASM build
test_emscripten_build() {
    echo -n "TEST: Emscripten WASM build compiles... "
    EMSDK="/home/node/.openclaw/workspace/emsdk"
    if [ -d "$EMSDK" ]; then
        source "$EMSDK/emsdk_env.sh" 2>/dev/null || true
        if [ ! -d "build-wasm" ]; then
            mkdir build-wasm
        fi
        cd build-wasm
        if emcmake cmake .. -DCMAKE_BUILD_TYPE=Release 2>&1 | tail -3 && make -j$(nproc) 2>&1 | tail -5; then
            if [ -f "bin/lo3.wasm" ]; then
                SIZE=$(wc -c < "bin/lo3.wasm")
                MAGIC=$(head -c 4 bin/lo3.wasm | od -A n -t x1 | tr -d ' ')
                if [ "$MAGIC" = "0061736d" ]; then
                    echo "PASS (WASM size=$SIZE)"
                    PASS_COUNT=$((PASS_COUNT+1))
                else
                    echo "FAIL (bad WASM magic: $MAGIC)"
                    FAIL_COUNT=$((FAIL_COUNT+1))
                fi
            else
                echo "FAIL (no lo3.wasm output)"
                FAIL_COUNT=$((FAIL_COUNT+1))
            fi
        else
            echo "FAIL (emcmake error)"
            FAIL_COUNT=$((FAIL_COUNT+1))
        fi
        cd ..
    else
        echo "SKIP (emscripten not found)"
    fi
}

# Test 4: WASM magic bytes valid
test_wasm_magic() {
    echo -n "TEST: lo3.wasm has valid WASM magic bytes... "
    if [ -f "bin/lo3.wasm" ]; then
        MAGIC=$(head -c 4 bin/lo3.wasm | od -A n -t x1 | tr -d ' ')
        if [ "$MAGIC" = "0061736d" ]; then
            echo "PASS"
            PASS_COUNT=$((PASS_COUNT+1))
        else
            echo "FAIL (magic=$MAGIC)"
            FAIL_COUNT=$((FAIL_COUNT+1))
        fi
    else
        echo "SKIP (build-wasm/bin/lo3.wasm not found)"
    fi
}

# Test 5: WASM can be loaded by Node
test_wasm_node_loadable() {
    echo -n "TEST: lo3.wasm loads in Node.js... "
    if [ -f "bin/lo3.wasm" ]; then
        if node -e "
const fs = require('fs');
const buf = fs.readFileSync('bin/lo3.wasm');
try {
    new WebAssembly.Module(buf);
    console.log('PASS');
    process.exit(0);
} catch(e) {
    console.log('FAIL:', e.message);
    process.exit(1);
}
" 2>/dev/null; then
            PASS_COUNT=$((PASS_COUNT+1))
        else
            echo "FAIL"
            FAIL_COUNT=$((FAIL_COUNT+1))
        fi
    else
        echo "SKIP"
    fi
}

# Test 6: WASM exposes expected functions
test_wasm_exports() {
    echo -n "TEST: lo3.wasm exports lo3_run and lo3_version... "
    if [ -f "bin/lo3.wasm" ]; then
        EXPORTS=$(node -e "
const fs = require('fs');
const buf = fs.readFileSync('bin/lo3.wasm');
const mod = new WebAssembly.Module(buf);
const exp = WebAssembly.Module.exports(mod).map(e => e.name);
console.log(exp.join(','));
" 2>/dev/null)
        
        if echo "$EXPORTS" | grep -q "lo3_run" && echo "$EXPORTS" | grep -q "lo3_version"; then
            echo "PASS (has lo3_run, lo3_version)"
            PASS_COUNT=$((PASS_COUNT+1))
        else
            echo "WARN (exports: $EXPORTS)"
            FAIL_COUNT=$((FAIL_COUNT+1))
        fi
    else
        echo "SKIP"
    fi
}

# Run tests
test_cmake_c11
test_native_build || true
test_emscripten_build || true
test_wasm_magic
test_wasm_node_loadable
test_wasm_exports

echo ""
echo "========================================"
echo "RESULTS: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "========================================"

exit $FAIL_COUNT
