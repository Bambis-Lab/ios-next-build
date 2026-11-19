#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${SIM_ID:?}" "${XCTESTRUN_PATH:?}" "${RUNNER_TEMP:?}"
tls="$(mktemp -d "$RUNNER_TEMP/ios173-wss.XXXXXX")"
python="$RUNNER_TEMP/ios173-wss-venv/bin/python"
# This CA is freshly generated in the disposable runner, installed ONLY in
# the selected simulator's trust store. No trust overrides in application code.
cat > "$tls/root.cnf" <<'EOF'
[req]
distinguished_name=dn
prompt=no
x509_extensions=ca
[dn]
CN=IOSNext ephemeral CI test root
[ca]
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
EOF
openssl req -new -x509 -newkey rsa:2048 -nodes -days 1 -config "$tls/root.cnf" \
  -keyout "$tls/ca.key" -out "$tls/ca.crt" > /dev/null 2>&1
openssl x509 -in "$tls/ca.crt" -outform der -out "$tls/ca.der"
for name in good wrong; do
  if [ "$name" = good ]; then san="IP:127.0.0.1"; else san="DNS:wrong.invalid"; fi
  cat > "$tls/$name.ext" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=$san
EOF
  openssl req -new -newkey rsa:2048 -nodes -subj "/CN=IOSNext synthetic $name" \
    -keyout "$tls/$name.key" -out "$tls/$name.csr" > /dev/null 2>&1
  openssl x509 -req -in "$tls/$name.csr" -CA "$tls/ca.crt" -CAkey "$tls/ca.key" \
    -CAcreateserial -days 1 -extfile "$tls/$name.ext" -out "$tls/$name.crt" > /dev/null 2>&1
  openssl verify -CAfile "$tls/ca.crt" "$tls/$name.crt" > /dev/null
done
second=""
if [ "${1:-}" = dual ]; then
  # The workflow has already reserved and booted both exact destinations.
  second="$(cat build/ios173/dual-simulator/created-udid.txt)"
  test -s build/ios173/dual-simulator/simulators.json
fi
install_test_root() {
  python3 - "$1" "$tls/ca.der" <<'PY'
import sys
sys.path.insert(0, "Scripts/Acceptance")
from boot_simulator import run_bounded
run_bounded(["xcrun","simctl","keychain",sys.argv[1],"add-root-cert",sys.argv[2]],timeout=180)
PY
}
install_test_root "$SIM_ID"
if [ -n "$second" ]; then install_test_root "$second"; fi
"$python" Scripts/Acceptance/audio_network_fixture.py serve > "$tls/server.log" 2>&1 &
server_pid=$!
"$python" Scripts/Acceptance/native_wss_proxy.py "$tls" > "$tls/proxy.log" 2>&1 &
proxy_pid=$!
cleanup() {
  kill "$server_pid" "$proxy_pid" 2>/dev/null || true
  wait "$server_pid" "$proxy_pid" 2>/dev/null || true
  if [ -n "$second" ]; then
    python3 - "$second" <<'PY' || true
import sys
sys.path.insert(0, "Scripts/Acceptance")
from boot_simulator import run_bounded
run_bounded(["xcrun","simctl","shutdown",sys.argv[1]],timeout=30)
PY
  fi
}
trap cleanup EXIT
for _ in $(seq 1 30); do
  kill -0 "$server_pid" "$proxy_pid"
  if grep -q SYNTHETIC_AUDIO_READY "$tls/server.log" && grep -q SYNTHETIC_WSS_READY "$tls/proxy.log"; then break; fi
  sleep 1
done
grep -q SYNTHETIC_AUDIO_READY "$tls/server.log"
grep -q SYNTHETIC_WSS_READY "$tls/proxy.log"
if [ "${1:-}" = dual ]; then
  python3 Scripts/Acceptance/run_two_native_simulators.py run "$second"
  exit 0
fi
xcodebuild test-without-building -collect-test-diagnostics never \
  -xctestrun "$XCTESTRUN_PATH" -destination "platform=iOS Simulator,id=$SIM_ID" \
  -parallel-testing-enabled NO -disable-concurrent-destination-testing \
  -resultBundlePath build/ios173/NativeWSS.xcresult \
  '-only-testing:IOSNextTests/FamilyAudioNetworkTests' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY="-" \
  2>&1 | tee build/ios173/NativeWSS.log
grep -Fq "Test Suite 'FamilyAudioNetworkTests' passed" build/ios173/NativeWSS.log
grep -Eq '\*\* TEST (EXECUTE )?SUCCEEDED \*\*' build/ios173/NativeWSS.log
echo "IOS173_NATIVE_WSS_SHORT_SYNTHETIC=PASS"
