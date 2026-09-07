#!/bin/bash
# 创建本机自签名代码签名证书「ClipMate Dev」并导入登录钥匙串。
#
# 用途：make-app.sh 自动探测该证书用于签名。签名后 macOS TCC 按
# "证书 + Bundle ID" 记录辅助功能等授权，应用重新打包不再要求重新授权。
# （ad-hoc 签名按每次构建的哈希记录，打包一次失效一次。）
#
# 重复运行安全：已存在同名有效证书时直接退出。
set -euo pipefail

IDENTITY="ClipMate Dev"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "==> 证书「$IDENTITY」已存在，无需创建"
    security find-identity -v -p codesigning | grep "$IDENTITY"
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/clipmate.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = ClipMate Dev
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = critical, CA:false
subjectKeyIdentifier = hash
CNF

echo "==> 生成自签名代码签名证书（10 年有效期）"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -config "$WORK/clipmate.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

openssl pkcs12 -export -out "$WORK/clipmate-dev.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -password pass:clipmate-dev -name "$IDENTITY" 2>/dev/null

echo "==> 导入登录钥匙串（允许 /usr/bin/codesign 使用）"
security import "$WORK/clipmate-dev.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P clipmate-dev -T /usr/bin/codesign

echo "==> 设置证书信任（代码签名用途）"
security add-trusted-cert -r trustRoot \
    -k "$HOME/Library/Keychains/login.keychain-db" "$WORK/cert.pem"

echo "==> 校验"
security find-identity -v -p codesigning | grep "$IDENTITY" \
    && echo "==> 完成：make-app.sh 现在会自动使用此证书签名" \
    || { echo "!! 证书未通过 codesigning 策略校验，请改用钥匙串访问的证书助理手动创建"; exit 1; }
