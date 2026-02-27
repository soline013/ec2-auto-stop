#!/bin/bash

# ─────────────────────────────────────────
# auto-stop.sh
# docker compose 컨테이너 로그 기반 EC2 자동 중지 스크립트
# ─────────────────────────────────────────

# pipefail 제거 → 파이프라인 중간 실패가 스크립트 전체를 죽이지 않도록
set -uo pipefail

# ── 상수 ──────────────────────────────────
LOCK_FILE="/var/run/auto-stop.lock"
LOG_FILE="/var/log/auto-stop.log"
IDLE_THRESHOLD=180  # 테스트용 3분 (운영 시 3600으로 변경)
COMPOSE_DIR="${COMPOSE_DIR:-/home/ubuntu/ec2-auto-stop/test-compose}"  # 환경변수 또는 기본값

# ── 절대경로 ──────────────────────────────
DOCKER="/usr/bin/docker"
SHUTDOWN="/sbin/shutdown"

# ── 로그 함수 ────────────────────────────
log() {
    echo "[$(TZ=Asia/Seoul date '+%Y-%m-%d %H:%M:%S KST')] $*" >> "$LOG_FILE"
}

# ── Lock 획득 + stale 처리 ───────────────
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    log "[SKIP] 이미 실행 중인 인스턴스 존재 (lock 획득 실패)"
    exit 0
fi

# 정상/비정상 종료 모두 lock 파일 제거
trap 'rm -f "$LOCK_FILE"' EXIT

# ── 메인 로직 ────────────────────────────
log "[START] 유휴 상태 점검 시작"

# 실행 중인 컨테이너 목록 수집
CONTAINERS=$(
    $DOCKER compose -f "$COMPOSE_DIR/docker-compose.yml" ps \
        --status running \
        --format "{{.Name}}" 2>/dev/null
) || {
    log "[ERROR] docker compose ps 실패 → 중지 보류"
    exit 1
}

if [[ -z "$CONTAINERS" ]]; then
    log "[WARN] 실행 중인 컨테이너 없음 → 중지 보류"
    exit 0
fi

NOW=$(date +%s)
LATEST_LOG_TIME=0

while IFS= read -r CONTAINER; do
    [[ -z "$CONTAINER" ]] && continue

    # || true → 컨테이너 조회 실패해도 스크립트 계속 진행
    LAST_LOG=$(
        $DOCKER logs --tail 1 --timestamps "$CONTAINER" 2>&1 \
        | grep -oP '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}' \
        | head -1
    ) || true

    if [[ -z "$LAST_LOG" ]]; then
        log "[INFO] $CONTAINER: 로그 없음"
        continue
    fi

    # || true → date 파싱 실패해도 스크립트 계속 진행
    LOG_EPOCH=$(date -d "${LAST_LOG}Z" +%s 2>/dev/null) || true
    LOG_EPOCH=${LOG_EPOCH:-0}

    ELAPSED=$(( NOW - LOG_EPOCH ))
    LAST_LOG_KST=$(TZ=Asia/Seoul date -d "${LAST_LOG}Z" '+%Y-%m-%d %H:%M:%S')
    log "[INFO] $CONTAINER: 마지막 로그 ${LAST_LOG_KST} KST (${ELAPSED}초 전)"

    (( LOG_EPOCH > LATEST_LOG_TIME )) && LATEST_LOG_TIME=$LOG_EPOCH

done <<< "$CONTAINERS"

# ── 판정 ─────────────────────────────────
if [[ $LATEST_LOG_TIME -eq 0 ]]; then
    log "[WARN] 유효한 로그 타임스탬프 없음 → 안전을 위해 중지 보류"
    exit 0
fi

TOTAL_IDLE=$(( NOW - LATEST_LOG_TIME ))
log "[INFO] 전체 최신 로그 기준 유휴 시간: ${TOTAL_IDLE}초 (임계값: ${IDLE_THRESHOLD}초)"

if (( TOTAL_IDLE >= IDLE_THRESHOLD )); then
    log "[ACTION] 유휴 임계값 초과 → EC2 인스턴스 중지"
    $SHUTDOWN -h now
else
    log "[OK] 유휴 임계값 미달, 유지"
fi
