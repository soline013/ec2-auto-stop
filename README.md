# EC2 Auto Stop

Docker Compose 컨테이너 로그 기반 EC2 자동 중지 스크립트

## 목적

컨테이너 로그가 일정 시간 동안 없으면 EC2 인스턴스를 자동으로 중지하여 비용을 절감합니다.

## 사용법

```bash
# 1. EC2에서 레포 클론
git clone https://github.com/soline013/ec2-auto-stop.git
cd ec2-auto-stop

# 2. Docker 설치 (Docker 없는 경우)
./setup-docker.sh

# 3. 자동 중지 스크립트 설치
./install.sh

# 4. 테스트 컨테이너 실행
cd test-compose
docker compose up -d
```

## 기본 설정 (테스트용)

| 항목 | 값 |
|------|-----|
| cron 주기 | 1분 |
| 유휴 임계값 | 3분 |
| COMPOSE_DIR | `/home/ubuntu/ec2-auto-stop/test-compose` |

## 운영 설정 변경

```bash
# /opt/auto-stop/auto-stop.sh
IDLE_THRESHOLD=3600  # 1시간

# /etc/cron.d/ec2-auto-stop
*/30 * * * * root /opt/auto-stop/auto-stop.sh  # 30분마다
COMPOSE_DIR=/home/ubuntu/your-app  # 실제 앱 경로
```

## 로그 확인

```bash
# auto-stop 로그
cat /var/log/auto-stop.log
tail -f /var/log/auto-stop.log

# cron 로그
journalctl -u cron -f        # Ubuntu/Debian
cat /var/log/cron            # Amazon Linux/CentOS
```

## 동작 방식

1. cron이 주기적으로 `auto-stop.sh` 실행
2. `docker compose ps`로 실행 중인 컨테이너 확인
3. 각 컨테이너의 마지막 로그 타임스탬프 확인
4. 가장 최근 로그 기준 유휴 시간 계산
5. 유휴 시간 >= 임계값이면 EC2 중지

## 안전 장치

- `docker compose ps` 실패 시 → 중지 보류
- 실행 중인 컨테이너 없음 → 중지 보류
- 유효한 로그 타임스탬프 없음 → 중지 보류
- Lock 파일로 중복 실행 방지

## 재설치 (설정 변경 후)

```bash
cd ~/ec2-auto-stop
git pull
./install.sh
```
