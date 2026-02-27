#!/bin/bash

# ─────────────────────────────────────────
# install.sh
# EC2 자동 중지 스크립트 설치
# ─────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/auto-stop"

echo "=== EC2 자동 중지 스크립트 설치 ==="

# root 권한 확인
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] root 권한으로 실행해주세요: sudo $0"
    exit 1
fi

# 설치 디렉토리 생성
echo "[1/5] 설치 디렉토리 생성: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# 스크립트 복사
echo "[2/5] 스크립트 복사"
cp "$SCRIPT_DIR/auto-stop.sh" "$INSTALL_DIR/"
chmod 755 "$INSTALL_DIR/auto-stop.sh"

# cron 설정
echo "[3/5] cron 설정 (/etc/cron.d/ec2-auto-stop)"
cp "$SCRIPT_DIR/ec2-auto-stop.cron" /etc/cron.d/ec2-auto-stop
chmod 644 /etc/cron.d/ec2-auto-stop

# logrotate 설정
echo "[4/5] logrotate 설정 (/etc/logrotate.d/auto-stop)"
cp "$SCRIPT_DIR/auto-stop.logrotate" /etc/logrotate.d/auto-stop
chmod 644 /etc/logrotate.d/auto-stop

# 로그 파일 초기화
echo "[5/5] 로그 파일 초기화"
touch /var/log/auto-stop.log
chmod 640 /var/log/auto-stop.log

echo ""
echo "=== 설치 완료 ==="
echo ""
echo "설정 확인:"
echo "  - 스크립트: $INSTALL_DIR/auto-stop.sh"
echo "  - cron:     /etc/cron.d/ec2-auto-stop (30분마다)"
echo "  - 로그:     /var/log/auto-stop.log"
echo ""
echo "COMPOSE_DIR 수정이 필요하면:"
echo "  sudo vi $INSTALL_DIR/auto-stop.sh"
echo ""
echo "테스트 실행:"
echo "  sudo $INSTALL_DIR/auto-stop.sh"
